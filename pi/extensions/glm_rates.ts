/**
 * glm_rates.ts — `/glm_rates` slash command that fetches your Z.ai / GLM
 * coding-plan quota & usage and renders it as a card in the chat transcript
 * (TUI-only; never sent to the LLM).
 *
 * Unlike a background monitor, this is strictly on-demand: each invocation
 * hits the public Z.ai monitor endpoint once and appends a fresh card.
 *
 *   GET https://api.z.ai/api/monitor/usage/quota/limit
 *   Authorization: Bearer <api key>
 *
 * The response shape is reverse-engineered from the live API (the magmast/
 * pi-glm-usage reference repo is private/404, so the request shape was derived
 * by probing the endpoint directly). Notable fields:
 *
 *   data.level            plan tier, e.g. "pro"
 *   data.limits[].type    "TOKENS_LIMIT" | "TIME_LIMIT" | ...
 *   data.limits[].percentage   0..100 — share of the quota already USED
 *   data.limits[].currentValue / usage / remaining  window figures for
 *       TIME_LIMIT: currentValue = used, usage = total allowance (quota),
 *       remaining = left. (The API names the quota field "usage".)
 *   data.limits[].nextResetTime  epoch-ms when the window rolls over
 *   data.limits[].usageDetails   per-model breakdown (TIME_LIMIT window)
 *   data.limits[].unit / number  opaque enum codes for window size/period;
 *                                 undocumented mapping, so not surfaced in the card.
 *
 * Any arguments to /glm_rates are ignored; the command always pretty-prints
 * the current quota as a single card.
 *
 * API key resolution order (first non-empty wins):
 *   GLM_RATES_API_KEY, ZAI_API_KEY, Z_AI_API_KEY, GLM_API_KEY,
 *   ZHIPUAI_API_KEY, BIGMODEL_API_KEY
 *
 * Override the endpoint with GLM_RATES_ENDPOINT if Z.ai moves it.
 *
 * Load: auto-discovered from pi/extensions/*.ts (= ~/.pi/agent/extensions);
 * `/reload` after edits.
 */
import type { ExtensionAPI, Theme } from "@earendil-works/pi-coding-agent";
import { Box, Text } from "@earendil-works/pi-tui";

const DEFAULT_ENDPOINT = "https://api.z.ai/api/monitor/usage/quota/limit";
const REQUEST_TIMEOUT_MS = 15_000;

// --- response types (reverse-engineered; coded defensively) ----------------

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

interface GlmRatesEntry {
	fetchedAt: number; // epoch ms
	data: QuotaData;
}

// --- api key resolution -----------------------------------------------------

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
	const endpoint = process.env.GLM_RATES_ENDPOINT?.trim() || DEFAULT_ENDPOINT;
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

// --- rendering --------------------------------------------------------------

function renderCard(entry: GlmRatesEntry, theme: Theme): Box {
	const { data } = entry;
	const now = Date.now();
	const box = new Box(1, 0, (text) => theme.bg("customMessageBg", text));

	// Title: "GLM Coding Plan · <level>"
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
							`  resets ${formatRelative(limit.nextResetTime, now)} (${formatDateTime(limit.nextResetTime)})`,
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

	return box;
}

// --- extension factory ------------------------------------------------------

export default function (pi: ExtensionAPI) {
	pi.registerEntryRenderer<GlmRatesEntry>("glm-rates", (entry, _options, theme) => {
		const data = entry.data ?? { fetchedAt: Date.now(), data: {} };
		return renderCard(data, theme);
	});

	pi.registerCommand("glm_rates", {
		description: "Fetch & display Z.ai / GLM coding-plan quota and usage",
		handler: async (_args, ctx) => {
			const key = resolveApiKey();
			if (!key) {
				ctx.ui.notify(
					`No GLM/Z.ai API key found. Set one of: ${KEY_ENV_VARS.join(", ")}`,
					"error",
				);
				return;
			}

			if (ctx.hasUI) ctx.ui.setStatus("glm-rates", "Fetching GLM rates…");

			const controller = new AbortController();
			const timer = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
			try {
				const data = await fetchQuota(key, controller.signal);
				pi.appendEntry<GlmRatesEntry>("glm-rates", { fetchedAt: Date.now(), data });
			} catch (e) {
				const msg =
					e instanceof ApiError
						? e.message
						: e instanceof Error && e.name === "AbortError"
							? `request timed out after ${REQUEST_TIMEOUT_MS / 1000}s`
							: e instanceof Error
								? e.message
								: String(e);
				ctx.ui.notify(`GLM rates: ${msg}`, "error");
			} finally {
				clearTimeout(timer);
				if (ctx.hasUI) ctx.ui.setStatus("glm-rates", undefined);
			}
		},
	});
}
