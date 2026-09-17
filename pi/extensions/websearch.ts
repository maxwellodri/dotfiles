/**
 * websearch.ts — pi tool wrapping the Brave Search API: v1 web search,
 * locale-derived country/language, key from `pass show brave_search_api_key`.
 *
 * WHY a tool: typed params (no quoting/flag fumbles), structured details,
 * collapsed TUI rendering. node fetch — the key never touches argv.
 *
 * Load: auto-discovered from pi/extensions/*.ts; /reload after edits.
 */
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { Type } from "typebox";
import { Text } from "@earendil-works/pi-tui";
import type { AgentToolResult, ExtensionAPI } from "@earendil-works/pi-coding-agent";

const pexec = promisify(execFile);

const ENDPOINT = "https://api.search.brave.com/res/v1/web/search";
const PASS_ENTRY = "brave_search_api_key";
const DEFAULT_COUNT = 10;

// Locale-derived country bias / result language: en_AU.UTF-8 -> au / en.
// Unparseable locale (C, unset) -> omit both params; Brave then applies none.
const LOCALE =
	process.env.LC_ALL || process.env.LC_MESSAGES || process.env.LANG || "";
const LOCALE_MATCH = /^([a-z]{2,3})(?:_([A-Z]{2}))?/i.exec(LOCALE.trim());
const SEARCH_LANG = LOCALE_MATCH?.[1]?.toLowerCase() ?? "";
const COUNTRY = LOCALE_MATCH?.[2]?.toLowerCase() ?? "";

interface BraveResult {
	title?: string;
	url?: string;
	description?: string;
}

/** pass lookup is a gpg decrypt — cache for the session. */
let cachedKey: string | undefined;

async function getApiKey(): Promise<string> {
	if (cachedKey) return cachedKey;
	const { stdout } = await pexec("pass", ["show", PASS_ENTRY]);
	cachedKey = stdout.trim();
	return cachedKey;
}

function stripTags(s: string): string {
	return s.replace(/<[^>]*>/g, "");
}

async function braveSearch(query: string, count: number, signal: AbortSignal) {
	const key = await getApiKey();
	const params = [
		`q=${encodeURIComponent(query)}`,
		`count=${count}`,
		...(COUNTRY ? [`country=${COUNTRY}`] : []),
		...(SEARCH_LANG ? [`search_lang=${SEARCH_LANG}`] : []),
	];
	const res = await fetch(`${ENDPOINT}?${params.join("&")}`, {
		headers: { "X-Subscription-Token": key, Accept: "application/json" },
		signal: AbortSignal.any([signal, AbortSignal.timeout(15_000)]),
	});
	const body = await res.json().catch(() => undefined);
	if (!res.ok) {
		const detail =
			body && typeof body === "object"
				? JSON.stringify((body as any).error ?? body)
				: `HTTP ${res.status}`;
		throw new Error(`Brave API ${res.status}: ${detail}`);
	}
	return (((body as any)?.web?.results ?? []) as BraveResult[]).filter((r) => r.url);
}

function formatResults(results: BraveResult[]): string {
	return results
		.map(
			(r, i) =>
				`${i + 1}. ${r.title ?? "Untitled"}\n   ${r.url}\n   ${
					r.description ? stripTags(r.description) : "No description"
				}\n`,
		)
		.join("");
}

function errorResult(e: unknown): AgentToolResult<any> {
	const msg = e instanceof Error ? e.message : String(e);
	return {
		content: [{ type: "text", text: `Error: ${msg}` }],
		details: { error: true },
	};
}

export default function (pi: ExtensionAPI) {
	pi.registerTool({
		name: "web_search",
		label: "Web Search",
		description:
			"Keyword-driven web search via the Brave Search API. " +
			"Returns ranked results (title, URL, snippet). " +
			"Use to verify information and fact-check claims; " +
			"use the browser for reading a specific page.",
		parameters: Type.Object({
			query: Type.String({ description: "Search query" }),
			count: Type.Optional(
				Type.Integer({
					minimum: 1,
					maximum: 20,
					description: `Number of results (default ${DEFAULT_COUNT})`,
				}),
			),
		}),
		async execute(_id, params, signal = new AbortController().signal): Promise<AgentToolResult<any>> {
			const count = params.count ?? DEFAULT_COUNT;
			try {
				const results = await braveSearch(params.query, count, signal);
				return {
					content: [{ type: "text", text: formatResults(results) }],
					details: { query: params.query, count, results },
				};
			} catch (e) {
				return errorResult(e);
			}
		},
		renderCall(args, theme) {
			const query = args.query || "…";
			const extra = args.count ? theme.fg("muted", ` (${args.count})`) : "";
			return new Text(
				`${theme.fg("toolTitle", theme.bold("web_search"))} ${theme.fg("accent", query)}${extra}`,
				0,
				0,
			);
		},
		renderResult(result, { expanded }, theme) {
			const output = result.content
				.filter((p: any) => p.type === "text")
				.map((p: any) => p.text)
				.join("\n");
			const isError = Boolean(result.details?.error);
			if (!expanded && !isError) {
				const n = result.details?.results?.length ?? 0;
				return new Text(theme.fg("muted", `${n} result${n === 1 ? "" : "s"}`), 0, 0);
			}
			return new Text(theme.fg(isError ? "error" : "toolOutput", output), 0, 0);
		},
	});
}
