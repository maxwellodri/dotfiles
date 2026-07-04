/**
 * fuzzy-filter.ts — make the `@` file mention fzf-like (true subsequence fuzzy)
 * instead of pi's default contiguous-substring matching.
 *
 * pi's built-in `@` completion shells out to `fd` (fuzzy at the fd layer) but
 * then `scoreEntry` keeps only *contiguous-substring* matches (exact /
 * startsWith / includes) and drops everything else — so `@fs` won't find
 * `footer.ts`. Slash commands already use pi-tui's `fuzzyFilter` (subsequence);
 * this extension points the same engine at `@` files.
 *
 * Mechanism: `ctx.ui.addAutocompleteProvider(factory)` wraps the base provider.
 * The factory is `(inner) => wrapped` and sees EVERY query (the `@` case is not
 * short-circuited away from us — we ARE the outer wrapper). For `@` queries we
 * run `fd` (reusing pi's own detected binary + flags via `inner.fdPath` /
 * `inner.basePath`) to list candidates, then `fuzzyFilter` for subsequence
 * ranking. Everything else — slash commands, plain paths, `applyCompletion`
 * (insertion / quoting) — is delegated to `inner` unchanged, so behavior stays
 * identical to pi outside of `@`.
 *
 * The fd listing is query-independent, so we cache it briefly (CACHE_TTL_MS) and
 * dedupe in-flight runs: the first keystroke pays the fd cost, subsequent ones
 * are instant fuzzy over the cached list.
 *
 * Notes / trade-offs:
 *  - Results are treated as files (no directory trailing-slash / "continue
 *    typing into a dir"). pi's own `@` fuzzy path doesn't distinguish dirs from
 *    `fd` output either; and fzf-style means you type more of the path rather
 *    than drilling in. Plain (non-`@`) path completion still navigates dirs via
 *    the inner provider.
 *  - Recall is capped by MAX_FD_RESULTS (fd lists at most that many). Fine for
 *    typical repos; bump it for huge monorepos.
 *
 * Load: auto-discovered from pi/extensions/*.ts (= ~/.pi/agent/extensions);
 * `/reload` after edits. `autocompleteProviderWrappers` is reset by pi on
 * reload, so no stacking guard is needed.
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
