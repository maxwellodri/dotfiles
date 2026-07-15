/**
 * snippet_expansion — `$name` text snippets with autocomplete.
 *
 * A lightweight text-expansion macro for reusable prompt fragments. A snippet
 * is either a file `<PI_CODING_AGENT_DIR>/snippets/<name>.md` or a directory
 * `<PI_CODING_AGENT_DIR>/snippets/<name>/` whose entry is the hardcoded file
 * `snippet.md` (the dotfiles wrapper points that env at `pi/snippets/`). The
 * directory layout lets you co-locate metadata next to the body — e.g.
 * `pi/snippets/swarm/{snippet.md, LICENSE_INFO.md}`. Either way, reference it
 * inline:
 *
 *   review this against $rust-style and tell me what's wrong
 *
 *   → the literal `$rust-style` token is replaced (in the context copy sent
 *     to the model — the stored session keeps what you typed) with the full
 *     contents of `snippets/rust-style.md`, right where the token sat.
 *
 * Two halves, both standard pi extension hooks:
 *
 *   1. **Autocomplete** (session_start → addAutocompleteProvider): typing `$`
 *      lists snippet names; the first markdown line of each is shown as the
 *      description. Stacks on top of fuzzy-filter.ts (which owns `@`); the
 *      two never fight because each only acts on its own trigger and
 *      delegates everything else to `inner`.
 *
 *   2. **Expansion** (context event → inline replace): finds `$name` tokens
 *      in the latest user message and substitutes the snippet body. Mirrors
 *      prompt_expansion.ts's `@path` handling but simpler — snippets are pure
 *      text macros, so there's no synthetic read tool-call, just inline
 *      substitution in the (mutable, per-turn) context copy.
 *
 * Name rules (also enforced by the token regexes):
 *   - `[a-zA-Z0-9_-]+` only — keeps the autocomplete token unambiguous and
 *     side-steps `$5.00` / `$HOME`-style false matches (the run stops at the
 *     first char outside that class, and a token only expands if a snippet by
 *     that name exists, so `$HOME` is a no-op unless you actually create
 *     `HOME.md` or `HOME/snippet.md`).
 *   - `$` must sit at a token boundary: preceded by start-of-string or
 *     whitespace (`foo$bar` is NOT a snippet ref). Same boundary `@` uses.
 *
 * `$` was chosen over the originally-suggested `~` because `~` collides with
 * home-dir expansion (`@~/...`, shell `~`). `$` still looks like a shell
 * variable, but the "expand only if the file exists" guard makes that benign.
 *
 * Guards / trade-offs (deliberate, mirrors prompt_expansion.ts):
 *   - only the latest user message is expanded (keeps history lean; injection
 *     is non-destructive so re-expansion each turn is cheap and idempotent)
 *   - file contents are mtime-cached; the directory listing for autocomplete
 *     has a short TTL cache (readdir per keystroke would be wasteful)
 *   - no size cap on snippet bodies — you authored them to be injected whole;
 *     re-add a cap if context bloat bites
 *
 * Load: auto-discovered from pi/extensions/*.ts (= ~/.pi/agent/extensions);
 * `/reload` after edits. Add snippets anytime — the TTL cache refreshes them
 * within LIST_CACHE_TTL_MS.
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import type { Dirent } from "node:fs";
import { join } from "node:path";
import { homedir } from "node:os";

/** Valid snippet name: alphanumeric, underscore, hyphen. No dots/slashes. */
const VALID_NAME = /^[a-zA-Z0-9_-]+$/;

/**
 * Hardcoded entry filename for the directory layout. A snippet directory
 * `<name>/` is recognised iff it contains this file; any siblings (e.g.
 * `LICENSE_INFO.md`) are co-located metadata, not snippets themselves.
 */
const SNIPPET_ENTRY_FILENAME = "snippet.md";

/**
 * Complete `$name` token for expansion. Preceded by start-of-string or
 * whitespace; captures the boundary in group 1 so the replacement can
 * preserve it. Name char class stops at the first non-name char, so `$5.00`
 * yields name `5` (and is a no-op unless `5.md` exists).
 */
const SNIPPET_TOKEN = /(^|\s)\$([a-zA-Z0-9_-]+)/g;

/**
 * Trailing `$<partial>` at the cursor, for autocomplete. Anchored to the end
 * of the text-before-cursor; partial may be empty (bare `$` just typed).
 * Boundary is `[ \t]` (not `\s`) so it doesn't match across a newline.
 */
const SNIPPET_TOKEN_PARTIAL = /(?:^|[ \t])\$([a-zA-Z0-9_-]*)$/;

/** TTL for the cached directory listing (autocomplete fires per keystroke). */
const LIST_CACHE_TTL_MS = 2000;
const MAX_SUGGESTIONS = 50;

// absPath -> { mtimeMs, text } — body is re-read only when the file changes.
const bodyCache = new Map<string, { mtimeMs: number; text: string }>();

// Cached name listing; cheap because readdir of a small dir is fast, but
// keystroke-frequency still justifies a brief TTL with in-flight dedupe.
let listCache: { names: string[]; ts: number } | null = null;
let listInflight: Promise<string[]> | null = null;

/** Resolve the snippets dir from the env the `pi` wrapper exports. */
function snippetsDir(): string {
	const base = process.env.PI_CODING_AGENT_DIR ?? join(homedir(), ".pi", "agent");
	return join(base, "snippets");
}

/**
 * Resolve a snippet name to its source file. Two layouts are supported:
 *
 *   1. file layout:      <snippets>/<name>.md
 *   2. directory layout: <snippets>/<name>/snippet.md
 *
 * The file layout wins when both exist, preserving the original behaviour
 * (and so a stale `<name>.md` shadows a half-migrated directory until the
 * author removes it — which is the least surprising option). Returns null if
 * neither layout is present or the name is invalid.
 */
function resolveSnippetFile(name: string): string | null {
	if (!VALID_NAME.test(name)) return null;
	const dir = snippetsDir();
	const fileLayout = join(dir, `${name}.md`);
	if (existsSync(fileLayout)) return fileLayout;
	const dirLayout = join(dir, name, SNIPPET_ENTRY_FILENAME);
	if (existsSync(dirLayout)) return dirLayout;
	return null;
}

/**
 * List valid snippet names (without extension), sorted alphabetically.
 * Returns [] if the dir is missing or unreadable — autocomplete then falls
 * through to the inner provider, so a snippets-less setup is a quiet no-op.
 */
function listSnippets(): string[] {
	let entries: Dirent[];
	try {
		entries = readdirSync(snippetsDir(), { withFileTypes: true });
	} catch {
		return [];
	}
	const dir = snippetsDir();
	// Dedupe: if both <name>.md and <name>/ exist, file-layout wins (matches
	// resolveSnippetFile), so the name should appear only once.
	const nameSet = new Set<string>();
	for (const e of entries) {
		// File layout: <name>.md
		if (e.isFile() && e.name.endsWith(".md")) {
			const name = e.name.slice(0, -3);
			if (VALID_NAME.test(name)) nameSet.add(name);
			continue;
		}
		// Directory layout: <name>/snippet.md
		if (e.isDirectory()) {
			const name = e.name;
			if (!VALID_NAME.test(name)) continue;
			if (existsSync(join(dir, name, SNIPPET_ENTRY_FILENAME))) {
				nameSet.add(name);
			}
		}
	}
	return [...nameSet].sort((a, b) => a.localeCompare(b));
}

/**
 * TTL-cached + in-flight-deduped listing. readdirSync is sync, but wrapping
 * it in a (resolved) promise lets the caller stay uniform with the async
 * autocomplete contract and dedupes concurrent calls within the same tick.
 */
async function getSnippetNames(): Promise<string[]> {
	if (listCache && Date.now() - listCache.ts < LIST_CACHE_TTL_MS) {
		return listCache.names;
	}
	if (listInflight) return listInflight;
	listInflight = Promise.resolve().then(() => {
		const names = listSnippets();
		if (names.length) listCache = { names, ts: Date.now() };
		listInflight = null;
		return names;
	});
	return listInflight;
}

/** Read a snippet body, mtime-cached. Returns null if missing/unreadable. */
function readSnippet(name: string): string | null {
	const absPath = resolveSnippetFile(name);
	if (!absPath) return null;
	let st;
	try {
		st = statSync(absPath);
	} catch {
		return null;
	}
	const cached = bodyCache.get(absPath);
	if (cached && cached.mtimeMs === st.mtimeMs) return cached.text;
	try {
		const text = readFileSync(absPath, "utf8");
		bodyCache.set(absPath, { mtimeMs: st.mtimeMs, text });
		return text;
	} catch {
		return null;
	}
}

/**
 * First non-blank line of a snippet, with any leading markdown `#` heading
 * markers stripped — used as the autocomplete description. Capped so a giant
 * first line can't blow out the popup.
 */
function firstLine(text: string): string {
	const line = text.split("\n").find((l) => l.trim()) ?? "";
	return line.replace(/^\s*#+\s*/, "").trim().slice(0, 80);
}

export default function (pi: ExtensionAPI) {
	// --- 1. Autocomplete: `$` lists snippet names --------------------------
	pi.on("session_start", (_event, ctx) => {
		ctx.ui.addAutocompleteProvider((inner: any) => ({
			// Union `$` in regardless of stacking order with fuzzy-filter.ts
			// (which passes triggerCharacters through unchanged). Whoever ends
			// up outermost reports the union; passthrough wrappers preserve it.
			triggerCharacters: Array.from(
				new Set([...(inner.triggerCharacters ?? []), "$"]),
			),
			shouldTriggerFileCompletion: (...a: any[]) =>
				inner.shouldTriggerFileCompletion?.(...a),
			applyCompletion: (...a: any[]) => inner.applyCompletion(...a),

			async getSuggestions(
				lines: string[],
				cursorLine: number,
				cursorCol: number,
				options: any,
			) {
				const before = (lines[cursorLine] ?? "").slice(0, cursorCol);
				const m = before.match(SNIPPET_TOKEN_PARTIAL);
				if (!m) {
					return inner.getSuggestions(lines, cursorLine, cursorCol, options);
				}
				const partial = m[1] ?? "";

				const names = await getSnippetNames();
				if (options?.signal?.aborted || names.length === 0) {
					return inner.getSuggestions(lines, cursorLine, cursorCol, options);
				}

				// Empty partial (bare `$`) → offer everything; else prefix-match.
				// Prefix match (not fuzzy) on purpose: snippet names are short
				// and user-authored, so exact-ish recall is clearer than
				// subsequence noise. Swap to fuzzyFilter if the corpus grows.
				const matches = partial
					? names.filter((n) => n.startsWith(partial))
					: names;
				if (matches.length === 0) {
					return inner.getSuggestions(lines, cursorLine, cursorCol, options);
				}

				return {
					prefix: `$${partial}`,
					items: matches.slice(0, MAX_SUGGESTIONS).map((n) => {
						const text = readSnippet(n);
						const desc = text ? firstLine(text) : "";
						return {
							value: `$${n}`,
							label: n,
							...(desc ? { description: desc } : {}),
						};
					}),
				};
			},
		}));
	});

	// --- 2. Expansion: inline `$name` → snippet body -----------------------
	pi.on("context", async (event, _ctx) => {
		const messages = event.messages;

		// find the most recent user message
		let lastUser = -1;
		for (let i = messages.length - 1; i >= 0; i--) {
			if (messages[i].role === "user") {
				lastUser = i;
				break;
			}
		}
		if (lastUser === -1) return;

		const msg: any = messages[lastUser];
		const content = msg.content;

		// Replace every `$name` (that resolves to an existing snippet) with its
		// body, preserving the captured leading boundary (start-of-string or
		// the whitespace char). Unknown names are left byte-for-byte intact so
		// `$HOME`, `$5`, etc. pass through untouched.
		const expand = (s: string): string =>
			s.replace(SNIPPET_TOKEN, (whole, boundary: string, name: string) => {
				const text = readSnippet(name);
				return text == null ? whole : `${boundary}${text}`;
			});

		let mutated = false;
		if (typeof content === "string") {
			const next = expand(content);
			if (next !== content) {
				msg.content = next;
				mutated = true;
			}
		} else if (Array.isArray(content)) {
			for (const part of content) {
				if (part && part.type === "text" && typeof part.text === "string") {
					const next = expand(part.text);
					if (next !== part.text) {
						part.text = next;
						mutated = true;
					}
				}
			}
		}

		if (mutated) return { messages };
	});
}
