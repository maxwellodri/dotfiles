/**
 * format-on-write.ts — run an in-place code formatter after the write/edit
 * tools commit a file, picked by extension. rustfmt (.rs), ruff (.py),
 * prettier (js/ts/json/css/html/md/yaml family).
 *
 * Hook choice: tool_result, not tool_call. tool_call fires BEFORE the tool
 * runs and can only block; the file doesn't exist yet, so an in-place
 * formatter has nothing to read. tool_result fires after the write lands, and
 * can patch the result content so the model is told what happened — including
 * the important case of a formatter rejecting unparseable code (rustfmt on
 * broken Rust), which gives the model a free syntax check.
 *
 * Safety:
 *  - best-effort: a formatter problem never turns a successful write into an
 *    error result, we only annotate.
 *  - each binary is PATH-checked once (cached); missing tools are skipped
 *    silently, so the table may list tools a given box lacks.
 *  - aborted via ctx.signal, bounded by a 30s timeout, cwd = project root so
 *    rustfmt.toml / Cargo.toml / .prettierrc are picked up.
 *  - files under node_modules/ or .git/ are skipped.
 *  - files are snapshotted before/after (up to 1 MiB) so reported deltas are
 *    real, not assumed.
 *
 * Override defaults with pi/format-on-write.json:
 *   { "map": { ".rs": ["rustfmt", "--edition", "2021"], ".nix": ["nixfmt"] },
 *     "disable": [".json"] }
 * `map` replaces the default table; `disable` removes entries. Each value is
 * the formatter argv minus the file path (appended at run time).
 *
 * rustfmt note: standalone `rustfmt file.rs` defaults to edition 2015 unless a
 * rustfmt.toml sets `edition`. If you want 2021/2024 without a rustfmt.toml,
 * set ".rs": ["rustfmt", "--edition", "2021"] in the config above.
 *
 * Load: auto-discovered from pi/extensions/*.ts; `/reload` after edits.
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { spawnSync } from "node:child_process";
import { existsSync, readFileSync, statSync } from "node:fs";
import { dirname, extname, isAbsolute, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

type FormatterConfig = {
	map?: Record<string, string[]>;
	disable?: string[];
};

const PRETTIER = ["prettier", "--write"];

const DEFAULT_FORMATTERS: Record<string, string[]> = {
	".rs": ["rustfmt"],
	".py": ["ruff", "format"],
	".js": PRETTIER,
	".mjs": PRETTIER,
	".cjs": PRETTIER,
	".ts": PRETTIER,
	".jsx": PRETTIER,
	".tsx": PRETTIER,
	".json": PRETTIER,
	".jsonc": PRETTIER,
	".css": PRETTIER,
	".scss": PRETTIER,
	".html": PRETTIER,
	".vue": PRETTIER,
	".svelte": PRETTIER,
	".md": PRETTIER,
	".mdx": PRETTIER,
	".yaml": PRETTIER,
	".yml": PRETTIER,
};

const FORMAT_TIMEOUT_MS = 30_000;
const SNAPSHOT_MAX_BYTES = 1_000_000;

function loadConfig(): Record<string, string[]> {
	let table = { ...DEFAULT_FORMATTERS };
	try {
		const here = dirname(fileURLToPath(import.meta.url));
		const cfgPath = join(here, "..", "format-on-write.json");
		if (existsSync(cfgPath)) {
			const raw = JSON.parse(readFileSync(cfgPath, "utf-8")) as FormatterConfig;
			if (raw.map) table = { ...raw.map };
			for (const ext of raw.disable ?? []) delete table[ext.toLowerCase()];
		}
	} catch {
		// bad/missing config — fall back to defaults, never break the agent.
	}
	return table;
}

function lineCount(s: string): number {
	let n = 1;
	for (let i = 0; i < s.length; i++) if (s.charCodeAt(i) === 10) n++;
	return n;
}

export default function (pi: ExtensionAPI) {
	const formatters = loadConfig();
	const onPath = new Map<string, boolean>();

	const hasBin = (bin: string): boolean => {
		const hit = onPath.get(bin);
		if (hit !== undefined) return hit;
		// `command -v` is POSIX sh; avoids `which` portability issues.
		const r = spawnSync("sh", ["-c", `command -v ${JSON.stringify(bin)} >/dev/null 2>&1`]);
		const ok = r.status === 0;
		onPath.set(bin, ok);
		return ok;
	};

	const shouldSkip = (abs: string): boolean =>
		abs.includes("/node_modules/") || abs.includes("/.git/");

	pi.on("tool_result", async (event, ctx) => {
		if (event.toolName !== "write" && event.toolName !== "edit") return;
		if (event.isError) return; // write/edit already failed; nothing to format

		const rel = (event.input as { path?: unknown }).path;
		if (typeof rel !== "string" || rel.length === 0) return;
		const ext = extname(rel).toLowerCase();
		const argv = formatters[ext];
		if (!argv || argv.length === 0) return;

		const [bin, ...args] = argv;
		const abs = isAbsolute(rel) ? rel : resolve(ctx.cwd, rel);
		if (shouldSkip(abs) || !existsSync(abs) || !hasBin(bin)) return;

		const note = await formatAndReport(pi, bin, args, abs, ctx.cwd, ctx.signal);
		if (note) {
			return { content: [...event.content, { type: "text" as const, text: note }] };
		}
		return undefined;
	});
}

async function formatAndReport(
	pi: ExtensionAPI,
	bin: string,
	args: string[],
	abs: string,
	cwd: string,
	signal: AbortSignal | undefined,
): Promise<string | undefined> {
	let before: string | undefined;
	try {
		if (statSync(abs).size <= SNAPSHOT_MAX_BYTES) before = readFileSync(abs, "utf-8");
	} catch {
		/* unreadable / vanished — proceed without a before snapshot */
	}

	let res;
	try {
		res = await pi.exec(bin, [...args, abs], { cwd, signal, timeout: FORMAT_TIMEOUT_MS });
	} catch (err) {
		return `[${bin}] skipped: failed to launch (${err instanceof Error ? err.message : String(err)})`;
	}

	if (res.killed) return `[${bin}] skipped: timed out or aborted`;

	if (res.code !== 0) {
		// Formatter rejected the file (e.g. rustfmt parse error). Surface it —
		// strong signal the model wrote broken code.
		const detail = (res.stderr || res.stdout || "").trim().split("\n")[0] ?? "";
		return `[${bin}] SKIPPED — exit ${res.code}${detail ? `: ${detail}` : ""}`;
	}

	if (before === undefined) return `[${bin}] formatted`;

	try {
		const after = readFileSync(abs, "utf-8");
		if (after === before) return undefined; // already formatted — stay quiet
		return `[${bin}] reformatted: ${lineCount(before)} → ${lineCount(after)} lines`;
	} catch {
		return `[${bin}] formatted`;
	}
}
