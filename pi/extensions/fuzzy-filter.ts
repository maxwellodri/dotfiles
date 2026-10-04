/**
 * fuzzy-filter.ts — fzf-style subsequence fuzzy for `@` file mentions (pi's
 * default scoring keeps only contiguous substrings, so @fs misses footer.ts).
 * Wraps the autocomplete provider; everything non-@ delegates to inner
 * unchanged. fd listing is query-independent, so it's cached briefly.
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { fuzzyFilter } from "@earendil-works/pi-tui";
import { spawn } from "node:child_process";

const MAX_FD_RESULTS = 5000;
const MAX_SUGGESTIONS = 50;
const CACHE_TTL_MS = 3000;

let fdCache: { cwd: string; paths: string[]; ts: number } | null = null;
let fdInflight: Promise<string[]> | null = null;

/** Strip the leading `@` / `@"` from an @-prefix token. */
function parseAtPrefix(prefix: string): { raw: string; quoted: boolean } | null {
	if (prefix.startsWith('@"')) return { raw: prefix.slice(2), quoted: true };
	if (prefix.startsWith("@")) return { raw: prefix.slice(1), quoted: false };
	return null;
}

/** Build the inserted value, quoting if needed (spaces or explicit @" form). */
function buildValue(p: string, quoted: boolean): string {
	return quoted || p.includes(" ") ? `@"${p}"` : `@${p}`;
}

/**
 * Extract a trailing unquoted `@`-token from the text before the cursor.
 * Quoted `@"…"` with spaces falls through to the inner provider (pi handles it,
 * just without fuzzy). Good enough: the common case is an unquoted `@path`.
 */
function extractAtToken(text: string): string | null {
	const m = text.match(/(?:^|\s)(@[^@\s]*)$/);
	return m ? m[1] : null;
}

/** List files+dirs under basePath with fd (respects .gitignore, hidden, follow). */
function runFd(basePath: string, fdPath: string): Promise<string[]> {
	const args = [
		"--base-directory",
		basePath,
		"--max-results",
		String(MAX_FD_RESULTS),
		"--type",
		"f",
		"--type",
		"d",
		"--follow",
		"--hidden",
		"--exclude",
		".git",
		"--exclude",
		".git/*",
		"--exclude",
		".git/**",
	];
	return new Promise((resolve) => {
		const child = spawn(fdPath, args, { stdio: ["ignore", "pipe", "pipe"] });
		let stdout = "";
		child.stdout.setEncoding("utf-8");
		child.stdout.on("data", (c: string) => {
			stdout += c;
		});
		child.on("error", () => resolve([]));
		child.on("close", () =>
			resolve(
				stdout
					.trim()
					.split("\n")
					.filter(Boolean)
					.map((l) => l.replace(/\\/g, "/")),
			),
		);
	});
}

/** Cached fd listing (query-independent), with in-flight dedupe. */
async function getFdList(basePath: string, fdPath: string): Promise<string[]> {
	if (fdCache && fdCache.cwd === basePath && Date.now() - fdCache.ts < CACHE_TTL_MS) {
		return fdCache.paths;
	}
	if (fdInflight) return fdInflight;
	fdInflight = runFd(basePath, fdPath)
		.then((paths) => {
			if (paths.length) fdCache = { cwd: basePath, paths, ts: Date.now() };
			fdInflight = null;
			return paths;
		})
		.catch(() => {
			fdInflight = null;
			return [];
		});
	return fdInflight;
}

export default function (pi: ExtensionAPI) {
	pi.on("session_start", (_event, ctx) => {
		ctx.ui.addAutocompleteProvider((inner: any) => ({
			triggerCharacters: inner.triggerCharacters,
			shouldTriggerFileCompletion: (...a: any[]) => inner.shouldTriggerFileCompletion?.(...a),
			applyCompletion: (...a: any[]) => inner.applyCompletion(...a),

			async getSuggestions(lines: string[], cursorLine: number, cursorCol: number, options: any) {
				const before = (lines[cursorLine] || "").slice(0, cursorCol);
				const token = extractAtToken(before);
				if (!token) return inner.getSuggestions(lines, cursorLine, cursorCol, options);
				const parsed = parseAtPrefix(token);
				if (!parsed) return inner.getSuggestions(lines, cursorLine, cursorCol, options);
				const { raw, quoted } = parsed;

				const fdPath = inner.fdPath ?? "fd";
				const basePath = inner.basePath ?? ctx.cwd;
				let paths: string[];
				try {
					paths = await getFdList(basePath, fdPath);
				} catch {
					return inner.getSuggestions(lines, cursorLine, cursorCol, options);
				}
				if (options?.signal?.aborted || paths.length === 0) return null;

				// True subsequence fuzzy over the full relative path (fzf-style).
				// fuzzyFilter tokenises the query on / and whitespace; every token
				// must subsequence-match, then results are ranked by match quality.
				const ranked = fuzzyFilter(paths, raw, (p) => p).slice(0, MAX_SUGGESTIONS);
				if (ranked.length === 0) return null;

				return {
					items: ranked.map((rel) => {
						const base = rel.split("/").pop() || rel;
						return { value: buildValue(rel, quoted), label: base, description: rel };
					}),
					prefix: token,
				};
			},
		}));
	});
}
