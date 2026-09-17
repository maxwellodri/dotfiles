/**
 * llm_rates.ts — `/llm_rates` slash command that fetches quota/usage for each
 * LLM provider we pay for and renders one card per provider in the chat
 * transcript (TUI-only; never sent to the LLM). `/glm_rates` is kept as an
 * alias. Strictly on-demand: each invocation hits the provider APIs once.
 *
 * Sections:
 *   GLM (Z.ai coding plan — the regular agentic usage)
 *     GET https://api.z.ai/api/monitor/usage/quota/limit
 *     Authorization: Bearer <api key>
 *     Response shape reverse-engineered from the live API. Notable fields:
 *       data.level            plan tier, e.g. "pro"
 *       data.limits[].type    "TOKENS_LIMIT" | "TIME_LIMIT" | ...
 *       data.limits[].percentage   0..100 — share of the quota already USED
 *       data.limits[].currentValue / usage / remaining  window figures for
 *           TIME_LIMIT: currentValue = used, usage = total allowance (quota),
 *           remaining = left. (The API names the quota field "usage".)
 *       data.limits[].nextResetTime  epoch-ms when the window rolls over
 *       data.limits[].usageDetails   per-model breakdown (TIME_LIMIT window)
 *
 *   OpenRouter (PayGo credits — the nvim oneshot traffic)
 *     GET https://openrouter.ai/api/v1/credits   (inference key)
 *     Two shapes depending on account vintage:
 *       legacy:  { total_credits, total_usage }        balance = granted - used
 *       current: { label, usage, usage24h, usage7d, limit, limit_remaining }
 *     POST https://openrouter.ai/api/v1/analytics/query  (management key)
 *       body: { metrics: ["total_usage"], granularity: "hour"|"day",
 *               startTime, endTime }  (ISO-8601)
 *       → data.data[].total_usage, summed into 24h/7d spend windows when the
 *       credits shape doesn't carry them. (The /activity endpoint is a dead
 *       end: management keys authenticate but return no rows.)
 *     Management key resolution: OPENROUTER_MANAGEMENT_API_KEY env, else
 *     `pass show openrouter_management_key`; without it the windows render a
 *     note.
 *
 * API key resolution (first non-empty wins):
 *   GLM:        GLM_RATES_API_KEY, ZAI_API_KEY, Z_AI_API_KEY, GLM_API_KEY,
 *               ZHIPUAI_API_KEY, BIGMODEL_API_KEY
 *   OpenRouter: OPENROUTER_API_KEY
 *
 * Endpoint override: GLM_RATES_ENDPOINT.
 *
 * Load: auto-discovered from pi/extensions/*.ts (= ~/.pi/agent/extensions);
 * `/reload` after edits.
 */
import type { ExtensionAPI, ExtensionCommandContext, Theme } from "@earendil-works/pi-coding-agent";
import { Box, Text } from "@earendil-works/pi-tui";
import { execFile } from "node:child_process";
import { promisify } from "node:util";

const REQUEST_TIMEOUT_MS = 15_000;

// --- GLM response types (reverse-engineered; coded defensively) -----------

interface UsageDetail {
	modelCode?: string;
	usage?: number;
}

interface QuotaLimit {
	type?: string; // "TOKENS_LIMIT" | "TIME_LIMIT" | ...
	unit?: number; // opaque window-unit enum
	number?: number; // opaque window-count enum
	usage?: number; // amount consumed in the current window
	currentValue?: number;
	remaining?: number;
	total?: number;
	percentage?: number; // 0..100 — share of the quota already used
	nextResetTime?: number; // epoch ms
	usageDetails?: UsageDetail[];
}

interface QuotaData {
	level?: string;
	limits?: QuotaLimit[];
}

interface QuotaResponse {
	code?: number;
	msg?: string;
	success?: boolean;
	data?: QuotaData;
}

// --- OpenRouter types --------------------------------------------------------

interface OrCredits {
	label?: string;
	usage?: number;
	usage24h?: number;
	usage7d?: number;
	limit?: number | null;
	limit_remaining?: number | null;
	total_credits?: number;
	total_usage?: number;
}

interface AnalyticsResponse {
	data?: { data?: { total_usage?: number }[] };
}

interface UsageWindow {
	label: string; // "24h" | "7d"
	usd: number;
}

interface OpenRouterData {
	label?: string;
	balanceRemaining: number | null;
	granted: number | null;
	windows: UsageWindow[];
	windowsNote?: string; // why windows are missing
}

// --- combined entry appended by the command --------------------------------

interface LlmRatesEntry {
	fetchedAt: number; // epoch ms
	glm?: QuotaData;
	glmError?: string;
	openrouter?: OpenRouterData;
	openRouterError?: string;
}

/** glm_rates entries from pre-rename sessions */
interface GlmRatesEntry {
	fetchedAt: number;
	data: QuotaData;
}

// --- api key resolution -------------------------------------------------------

const KEY_ENV_VARS = [
	"GLM_RATES_API_KEY",
	"ZAI_API_KEY",
	"Z_AI_API_KEY",
	"GLM_API_KEY",
	"ZHIPUAI_API_KEY",
	"BIGMODEL_API_KEY",
];

function resolveApiKey(): string | undefined {
	for (const name of KEY_ENV_VARS) {
		const v = process.env[name];
		if (v && v.trim()) return v.trim();
	}
	return undefined;
}

const execFileP = promisify(execFile);

/** management key for analytics/query: env, else the password store */
async function resolveMgmtKey(): Promise<string | undefined> {
	const env = process.env.OPENROUTER_MANAGEMENT_API_KEY?.trim();
	if (env) return env;
	try {
		const { stdout } = await execFileP("pass", ["show", "openrouter_management_key"], { timeout: 10_000 });
		const v = stdout.trim();
		return v || undefined;
	} catch {
		return undefined;
	}
}

// --- formatting helpers (pure) ---------------------------------------------

/** "in 3h 12m", "in 4d 5h", "in 45m", "in 12s", "now". */
function formatRelative(targetMs: number, now: number): string {
	let secs = Math.round((targetMs - now) / 1000);
	if (secs <= 0) return "now";
	const days = Math.floor(secs / 86400);
	secs %= 86400;
	const hours = Math.floor(secs / 3600);
	secs %= 3600;
	const mins = Math.floor(secs / 60);
	secs %= 60;
	const parts: string[] = [];
	if (days) parts.push(`${days}d`);
	if (hours) parts.push(`${hours}h`);
	if (mins && !days) parts.push(`${mins}m`); // skip minutes once days appear
	if (secs && !days && !hours) parts.push(`${secs}s`);
	if (!parts.length) parts.push("<1m");
	return "in " + parts.join(" ");
}

function formatDateTime(ms: number): string {
	const d = new Date(ms);
	const pad = (n: number) => String(n).padStart(2, "0");
	const day = d.toLocaleDateString(undefined, { month: "short", day: "numeric" });
	return `${day} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

function formatNumber(n: number): string {
	if (!Number.isFinite(n)) return "—";
	if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(n % 1_000_000 ? 1 : 0)}M`;
	if (n >= 1_000) return `${(n / 1_000).toFixed(n % 1_000 ? 1 : 0)}k`;
	return String(n);
}

function formatUsd(usd: number): string {
	if (!Number.isFinite(usd)) return "—";
	if (usd >= 1) return `$${usd.toFixed(2)}`;
	if (usd >= 0.01) return `$${usd.toFixed(3)}`;
	return `$${usd.toFixed(4)}`;
}

function bar(pct: number, width = 20): string {
	const clamped = Math.max(0, Math.min(100, pct));
	const filled = Math.round((clamped / 100) * width);
	return "█".repeat(filled) + "░".repeat(Math.max(0, width - filled));
}

/** color keyed off how much of the quota is already USED */
function pctColor(theme: Theme, pct: number): string {
	return theme.fg(pct >= 90 ? "error" : pct >= 70 ? "warning" : "success", "");
}

const LIMIT_LABELS: Record<string, string> = {
	TOKENS_LIMIT: "Token quota",
	TIME_LIMIT: "Tool / MCP calls",
	REQUEST_LIMIT: "Requests",
};

// render order (lower first); unknown types fall after the known ones
const LIMIT_ORDER: Record<string, number> = {
	TOKENS_LIMIT: 0,
	TIME_LIMIT: 1,
};

function limitLabel(limit: QuotaLimit): string {
	return (limit.type && LIMIT_LABELS[limit.type]) || limit.type || "Limit";
}

/** resolve a usable percentage (0..100) or undefined when unknowable */
function resolvePct(limit: QuotaLimit): number | undefined {
	if (typeof limit.percentage === "number" && Number.isFinite(limit.percentage)) {
		return limit.percentage;
	}
	const usage = typeof limit.usage === "number" ? limit.usage : undefined;
	const remaining = typeof limit.remaining === "number" ? limit.remaining : undefined;
	if (usage != null && remaining != null) {
		const total = usage + remaining;
		if (total > 0) return (usage / total) * 100;
	}
	return undefined;
}

// --- api --------------------------------------------------------------------

class ApiError extends Error {}

async function fetchQuota(key: string, signal: AbortSignal): Promise<QuotaData> {
	const endpoint = process.env.GLM_RATES_ENDPOINT?.trim() || "https://api.z.ai/api/monitor/usage/quota/limit";
	const res = await fetch(endpoint, {
		method: "GET",
		headers: { Authorization: `Bearer ${key}`, Accept: "application/json" },
		signal,
	});
	if (!res.ok) {
		throw new ApiError(`HTTP ${res.status}${res.statusText ? ` ${res.statusText}` : ""}`);
	}
	let json: QuotaResponse;
	try {
		json = (await res.json()) as QuotaResponse;
	} catch {
		throw new ApiError("invalid JSON response");
	}
	if (!json.success) {
		throw new ApiError(`API error: ${json.msg ?? "unknown"} (code ${json.code ?? "?"})`);
	}
	if (!json.data) throw new ApiError("API returned no data");
	return json.data;
}

// --- openrouter api -----------------------------------------------------------

async function fetchOpenRouter(key: string, mgmtKey: string | undefined, signal: AbortSignal): Promise<OpenRouterData> {
	const res = await fetch("https://openrouter.ai/api/v1/credits", {
		headers: { Authorization: `Bearer ${key}`, Accept: "application/json" },
		signal,
	});
	if (!res.ok) throw new ApiError(`credits HTTP ${res.status}`);
	let json: { data?: OrCredits };
	try {
		json = (await res.json()) as typeof json;
	} catch {
		throw new ApiError("credits: invalid JSON response");
	}
	const c = json.data;
	if (!c) throw new ApiError("credits: no data");

	const data: OpenRouterData = { balanceRemaining: null, granted: null, windows: [] };

	if (typeof c.limit_remaining === "number") {
		data.balanceRemaining = c.limit_remaining;
		if (typeof c.limit === "number") data.granted = c.limit;
		if (typeof c.usage24h === "number") data.windows.push({ label: "24h", usd: c.usage24h });
		if (typeof c.usage7d === "number") data.windows.push({ label: "7d", usd: c.usage7d });
	} else if (typeof c.total_credits === "number" && typeof c.total_usage === "number") {
		data.granted = c.total_credits;
		data.balanceRemaining = c.total_credits - c.total_usage;
	}

	// legacy credits shape carries no windows; query the analytics API with
	// the management key instead
	if (!data.windows.length) {
		if (mgmtKey) {
			const windows: { label: string; usd: number }[] = [];
			let err: string | undefined;
			const spans: { label: string; granularity: string; ms: number }[] = [
				{ label: "24h", granularity: "hour", ms: 24 * 3600e3 },
				{ label: "7d", granularity: "day", ms: 7 * 24 * 3600e3 },
			];
			for (const span of spans) {
				const res = await fetch("https://openrouter.ai/api/v1/analytics/query", {
					method: "POST",
					headers: { Authorization: `Bearer ${mgmtKey}`, "Content-Type": "application/json" },
					body: JSON.stringify({
						metrics: ["total_usage"],
						granularity: span.granularity,
						startTime: new Date(Date.now() - span.ms).toISOString(),
						endTime: new Date().toISOString(),
					}),
					signal,
				});
				if (!res.ok) {
					err = `analytics HTTP ${res.status}`;
					break;
				}
				let json: AnalyticsResponse;
				try {
					json = (await res.json()) as AnalyticsResponse;
				} catch {
					err = "analytics: invalid JSON response";
					break;
				}
				const usd = (json.data?.data ?? []).reduce(
					(acc, r) => acc + (typeof r.total_usage === "number" ? r.total_usage : 0),
					0,
				);
				windows.push({ label: span.label, usd });
			}
			if (err) data.windowsNote = err;
			else data.windows = windows;
		} else {
				data.windowsNote =
					"24h/7d need a management key (OPENROUTER_MANAGEMENT_API_KEY or pass openrouter_management_key)";
			}
	}

	return data;
}

// --- rendering --------------------------------------------------------------

function renderGlmSection(data: QuotaData, theme: Theme, box: Box): void {
	const level = data.level ?? "unknown";
	box.addChild(
		new Text(
			`${theme.fg("accent", theme.bold("GLM Coding Plan"))} ${theme.fg("dim", "·")} ${theme.fg("accent", level)}`,
			0,
			0,
		),
	);

	const limits = data.limits ?? [];
	if (limits.length === 0) {
		box.addChild(new Text(theme.fg("dim", "no usage limits reported"), 0, 0));
	} else {
		const ordered = [...limits].sort(
			(a, b) => (LIMIT_ORDER[a.type ?? ""] ?? 99) - (LIMIT_ORDER[b.type ?? ""] ?? 99),
		);
		for (const limit of ordered) {
			const pct = resolvePct(limit);

			// label
			box.addChild(new Text(theme.fg("muted", limitLabel(limit)), 0, 0));

			// progress bar + percentage
			const barStr = pct != null ? bar(pct) : "░".repeat(20);
			const barColor = pct != null ? pctColor(theme, pct) : theme.fg("dim", "");
			const pctStr = pct != null ? `${Math.round(pct)}% used` : "usage unknown";
			box.addChild(new Text(`  ${barColor}${barStr} ${theme.fg("dim", pctStr)}`, 0, 0));

			// reset time on its own line
			if (typeof limit.nextResetTime === "number") {
				box.addChild(
					new Text(
						theme.fg(
							"dim",
							`  resets ${formatRelative(limit.nextResetTime, Date.now())} (${formatDateTime(limit.nextResetTime)})`,
						),
						0,
						0,
					),
				);
			}

			// concrete usage figures: currentValue = used, usage = total allowance
			// (cross-checked against `percentage` on the TIME_LIMIT window)
			const used = typeof limit.currentValue === "number" ? limit.currentValue : undefined;
			const quota = typeof limit.usage === "number" ? limit.usage : undefined;
			const remaining = typeof limit.remaining === "number" ? limit.remaining : undefined;
			const figures: string[] = [];
			if (used != null && quota != null) {
				figures.push(`used ${formatNumber(used)} / ${formatNumber(quota)}`);
			}
			if (remaining != null) figures.push(`${formatNumber(remaining)} remaining`);
			if (figures.length) {
				box.addChild(new Text(`  ${theme.fg("dim", figures.join("  ·  "))}`, 0, 0));
			}

			// per-tool breakdown — identifies which augmented/MCP tools the window
			// meters (seen on TIME_LIMIT: search-prime, web-reader, zread)
			const tools = limit.usageDetails?.filter((d) => d && d.modelCode);
			if (tools && tools.length) {
				const segs = tools.map((d) => `${d.modelCode} ${formatNumber(d.usage ?? 0)}`);
				box.addChild(new Text(`  ${theme.fg("dim", segs.join("  ·  "))}`, 0, 0));
			}
		}
	}
}

function renderOpenRouterSection(data: OpenRouterData, theme: Theme, box: Box): void {
	const label = data.label ? ` ${theme.fg("dim", "·")} ${theme.fg("accent", data.label)}` : "";
	box.addChild(
		new Text(`${theme.fg("accent", theme.bold("OpenRouter PayGo"))}${label}`, 0, 0),
	);

	box.addChild(new Text(theme.fg("muted", "Credit balance"), 0, 0));
	const bal: string[] = [];
	if (data.balanceRemaining != null) bal.push(`${formatUsd(data.balanceRemaining)} remaining`);
	if (data.granted != null && data.granted > 0) bal.push(`${formatUsd(data.granted)} granted`);
	box.addChild(new Text(`  ${theme.fg("dim", bal.join("  ·  ") || "unknown")}`, 0, 0));
	if (
		data.balanceRemaining != null &&
		data.granted != null &&
		data.granted > 0
	) {
		const usedPct = ((data.granted - data.balanceRemaining) / data.granted) * 100;
		box.addChild(
			new Text(`  ${pctColor(theme, usedPct)}${bar(usedPct)} ${theme.fg("dim", `${Math.round(usedPct)}% used`)}`, 0, 0),
		);
	}

	box.addChild(new Text(theme.fg("muted", "Spend"), 0, 0));
	if (data.windows.length) {
		const segs = data.windows.map((w) => `${w.label} ${formatUsd(w.usd)}`);
		box.addChild(new Text(`  ${theme.fg("dim", segs.join("  ·  "))}`, 0, 0));
	} else if (data.windowsNote) {
		box.addChild(new Text(theme.fg("dim", `  ${data.windowsNote}`), 0, 0));
	}
}

function renderErrorSection(title: string, msg: string, theme: Theme, box: Box): void {
	box.addChild(new Text(`${theme.fg("accent", theme.bold(title))}`, 0, 0));
	box.addChild(new Text(theme.fg("error", `  ${msg}`), 0, 0));
}

function renderCard(entry: LlmRatesEntry, theme: Theme): Box {
	const box = new Box(1, 0, (text) => theme.bg("customMessageBg", text));
	let first = true;
	const sep = () => {
		if (!first) box.addChild(new Text(" ", 0, 0));
		first = false;
	};

	if (entry.glm) {
		sep();
		renderGlmSection(entry.glm, theme, box);
	} else if (entry.glmError) {
		sep();
		renderErrorSection("GLM Coding Plan", entry.glmError, theme, box);
	}

	if (entry.openrouter) {
		sep();
		renderOpenRouterSection(entry.openrouter, theme, box);
	} else if (entry.openRouterError) {
		sep();
		renderErrorSection("OpenRouter PayGo", entry.openRouterError, theme, box);
	}

	return box;
}

// --- extension factory ------------------------------------------------------

const DESCRIPTION = "Fetch & display provider quota/usage cards (GLM plan, OpenRouter credits)";

export default function (pi: ExtensionAPI) {
	// glm-rates entries from pre-rename sessions
	pi.registerEntryRenderer<GlmRatesEntry>("glm-rates", (entry, _options, theme) => {
		const box = new Box(1, 0, (text) => theme.bg("customMessageBg", text));
		renderGlmSection(entry.data?.data ?? {}, theme, box);
		return box;
	});

	pi.registerEntryRenderer<LlmRatesEntry>("llm-rates", (entry, _options, theme) =>
		renderCard(entry.data ?? { fetchedAt: Date.now() }, theme),
	);

	const handler = async (_args: string, ctx: ExtensionCommandContext) => {
		const glmKey = resolveApiKey();
		const orKey = process.env.OPENROUTER_API_KEY?.trim() || undefined;
		const mgmtKey = await resolveMgmtKey();

		if (!glmKey && !orKey) {
			ctx.ui.notify(
				`No provider credentials: GLM needs one of ${KEY_ENV_VARS.join(", ")}; OpenRouter needs OPENROUTER_API_KEY`,
				"error",
			);
			return;
		}

		if (ctx.hasUI) ctx.ui.setStatus("llm-rates", "Fetching rates…");

		const entry: LlmRatesEntry = { fetchedAt: Date.now() };

		const glmTask = glmKey
			? (async () => {
					const c = new AbortController();
					const t = setTimeout(() => c.abort(), REQUEST_TIMEOUT_MS);
					try {
						entry.glm = await fetchQuota(glmKey, c.signal);
					} catch (e) {
						entry.glmError = errMessage(e, REQUEST_TIMEOUT_MS);
					} finally {
						clearTimeout(t);
					}
				})()
			: Promise.resolve();

		const orTask = orKey
			? (async () => {
					const c = new AbortController();
					const t = setTimeout(() => c.abort(), REQUEST_TIMEOUT_MS);
					try {
						entry.openrouter = await fetchOpenRouter(orKey, mgmtKey, c.signal);
					} catch (e) {
						entry.openRouterError = errMessage(e, REQUEST_TIMEOUT_MS);
					} finally {
						clearTimeout(t);
					}
				})()
			: Promise.resolve();

		await Promise.all([glmTask, orTask]);
		pi.appendEntry<LlmRatesEntry>("llm-rates", entry);

		if (ctx.hasUI) ctx.ui.setStatus("llm-rates", undefined);
	};

	pi.registerCommand("llm_rates", { description: DESCRIPTION, handler });
}

function errMessage(e: unknown, timeoutMs: number): string {
	if (e instanceof ApiError) return e.message;
	if (e instanceof Error && e.name === "AbortError") return `request timed out after ${timeoutMs / 1000}s`;
	return e instanceof Error ? e.message : String(e);
}
