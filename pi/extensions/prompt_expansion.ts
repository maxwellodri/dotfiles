// ─────────────────────────────────────────────────────────────────────────────
// Portions adapted from pi-file-injector — https://github.com/dabstractor/pi-file-injector
//
// MIT License
//
// Copyright (c) 2026 Dustin Schultz
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
// ─────────────────────────────────────────────────────────────────────────────

/**
 * prompt_expansion — inline `@path` references into the prompt as pre-read files.
 *
 * pi's TUI inserts `@path` references as plain-text pointers; the model has to
 * call `read` to see them. This extension resolves `@path` tokens at submit time
 * and delivers the contents to the model BEFORE it replies, so there is no
 * read round-trip. What the user typed stays byte-for-byte intact.
 *
 * ## Architecture (input → before_agent_start → persistent custom message)
 *
 *   - `input` event — fires once per submit (interactive TUI, `pi -p`, RPC).
 *     Detects `@path` tokens, resolves each to a file or directory, builds
 *     pi-native `<file name="abs">…</file>` blocks, and stashes them in a
 *     closure var. Returns the prompt VERBATIM (`action:"transform"` with the
 *     original text) so the stored message keeps its `@` markers — cancel /
 *     fork / `/tree`-re-open re-triggers injection automatically (the editor
 *     prefill still shows `@foo`, so re-submitting re-injects).
 *   - `before_agent_start` event — fires right after `input` in the same
 *     `prompt()` call. Publishes the stashed blocks as ONE custom message
 *     (`customType:"promptExpansion.injected"`) appended after the user
 *     message. That message is a `CustomMessageEntry` — it PERSISTS in the
 *     session and participates in LLM context on every subsequent turn until
 *     compaction prunes it. So an `@mention` is STICKY: the file stays in
 *     context for later turns without re-injection. (This is the key win over
 *     a `context`-event approach, which is non-persistent and would have to
 *     re-inject every turn — more CPU and a worse compaction story.)
 *   - `session_start` — registers a `MessageRenderer` so the injected items
 *     render as one compact green `read <path>` / `ls <dir>/` line each
 *     (ctrl+o to expand) instead of dumping raw `<file>` blocks into the chat.
 *
 * Adapted from dabstractor/pi-file-injector (the `#@file` extension): same
 * input+before_agent_start+custom-message mechanism and budget-aware paging,
 * but keeping our bare-`@` trigger and our directory-listing semantics. Image
 * handling is deliberately omitted — binary files (images included) get a note
 * block, since the target model has no image support.
 *
 * ## What gets delivered
 *
 *   - **Text files**: whole contents in a `<file name="abs">…</file>` block
 *     when they fit the remaining context budget; otherwise an 8KB head block
 *     plus a paging directive telling the model to `read` the rest at
 *     `offset:N, limit:2000`. Budget-aware, never a silent hard truncation.
 *   - **Empty files**: `<file name="abs">\n\n</file>` (pi-native empty block).
 *   - **Binary files** (NUL-byte heuristic — incl. images): a
 *     `<binary file — contents not injected; use the read tool if needed>` note.
 *   - **Directories**: an `ls -F`-style listing (one level deep, `/` and `@`
 *     suffixes, hidden entries gated by count) as a text block — `read` has no
 *     directory equivalent. Empty directories annotate `(empty directory)`.
 *   - **Missing / unreadable**: left as written; nothing injected.
 *
 * ## Guards
 *
 *   - only `@`-prefixed refs at a token boundary (start, or after a non-word
 *     char) — matches `(@foo)` / `[@foo]`, not mid-word `foo@bar.com`, and not
 *     `#@foo` (`#` excluded). Unicode-aware.
 *   - the `input` handler short-circuits (`continue`) for extension-origin
 *     input (loop prevention), mid-stream steering (latency), and prompts with
 *     no `@` at all.
 *   - per-path try/catch: a resolution/read error leaves that token verbatim
 *     and never throws — one bad path can't fail the submit.
 *   - de-dup by resolved absolute path (`@./a.ts` + `@a.ts` inject once).
 *
 * Hook order is guaranteed: pi runs `input` → … → `before_agent_start` in one
 * awaited `prompt()` call, so the closure handoff is race-free. `/reload` after
 * edits (auto-discovered from pi/extensions/*.ts).
 */
import type { ExtensionAPI, InputEvent, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { highlightCode, getLanguageFromPath } from "@earendil-works/pi-coding-agent";
import { Box, Text, type Component } from "@earendil-works/pi-tui";
import { promises as fs } from "node:fs";
import type { Dirent } from "node:fs";
import * as path from "node:path";
import * as os from "node:os";

// ── trigger & token cleaning ────────────────────────────────────────────────
// `@` at start-of-string or after a non-word char (Unicode-aware negative
// lookbehind). Matches `(@foo)` / `[@foo]` / `>@foo`; does NOT match mid-word
// (`foo@bar.com`) or `#@foo` (`#` is excluded so a hypothetical `#@` syntax is
// left alone). Mirrors pi-file-injector's BARE_AT_RE boundary (collision-free).
const AT_TOKEN = /(^|(?<![\p{L}\p{N}_#]))@(\S+)/gu;
const TRAILING_PUNCT = ".,;:!?\")]}>'";

// ── budget / paging constants (parity with the read tool + pi-file-injector) ─
const BINARY_SAMPLE = 8000; // NUL-byte heuristic sample window (git/ripgrep method)
const PAGED_THRESHOLD = 0.6; // inject whole if fileCost ≤ PAGED_THRESHOLD · remaining
const MARGIN = 8192; // safety bytes subtracted from the remaining budget
const HEAD_CHARS = 8192; // paged head size in UTF-16 code units (~read's 2000-line head)
const DEFAULT_RESERVE = 8192; // fallback output reserve when ctx.model is absent
const READ_LIMIT = 2000; // read tool DEFAULT_MAX_LINES — the paging directive's page size
const LIMIT_HIDDEN_FILES = 50; // list hidden entries only when there are ≤ this many

/** Per-injected-item metadata for the renderer (NOT sent to the model — only `content` is). */
interface FileDetail {
	path: string; // absolute resolved path
	kind: "text" | "binary" | "paged" | "dir";
	body?: string; // displayable body (file contents / head / dir listing); renderer-only
	range?: string; // paged: ":<startLine>-" resume range (read-tool style)
	directive?: string; // paged: the <paged: …> instruction text, shown when expanded
}

interface Injections {
	blocks: string[]; // pi-native <file> blocks + dir text blocks → joined into message content
	details: FileDetail[]; // one per injected item, in encounter order → renderer
	injected: number;
	paged: number;
}

/** Strip trailing punctuation/glue that `\S+` glues onto a path token. */
function cleanToken(raw: string): string {
	let s = raw;
	while (s.length > 0 && TRAILING_PUNCT.includes(s[s.length - 1])) s = s.slice(0, -1);
	return s;
}

/** Expand a leading `~` / `~/`, then resolve against cwd. Absolute paths pass through. */
function expandTilde(p: string): string {
	if (p === "~") return os.homedir();
	if (p.startsWith("~/")) return path.join(os.homedir(), p.slice(2));
	return p;
}

/** Extract de-duplicated (by as-typed token) `@path` refs from the prompt, in order. */
function extractRefs(text: string): string[] {
	const refs: string[] = [];
	const seen = new Set<string>();
	let m: RegExpExecArray | null;
	AT_TOKEN.lastIndex = 0;
	while ((m = AT_TOKEN.exec(text)) !== null) {
		const tok = cleanToken(m[2]);
		if (tok && !seen.has(tok)) {
			seen.add(tok);
			refs.push(tok);
		}
	}
	return refs;
}

/** NUL-byte heuristic (git/ripgrep): binary if any 0x00 in the first BINARY_SAMPLE bytes. */
function isBinary(buf: Buffer): boolean {
	const n = Math.min(buf.length, BINARY_SAMPLE);
	for (let i = 0; i < n; i++) if (buf[i] === 0) return true;
	return false;
}

/** `<file name="abs">\n<content>\n</file>` — pi's native attached-file block (CLI @file parity). */
function formatTextFileBlock(abs: string, content: string): string {
	return '<file name="' + abs + '">\n' + content + "\n</file>";
}

/** Binary note (em dash U+2014). No decoded garbage; points the model at the read tool. */
function formatBinaryBlock(abs: string): string {
	return '<file name="' + abs + '"><binary file \u2014 contents not injected; use the read tool if needed></file>';
}

/** Paged directive: tells the model exactly where the head stopped and how to read the rest. */
function formatPagedDirectiveBlock(abs: string, len: number, startLine: number, injectedLines: number): string {
	return (
		'<file name="' +
		abs +
		'"><paged: ' +
		len +
		" chars; head delivered " +
		injectedLines +
		" complete lines; read the rest with the read tool at offset:" +
		startLine +
		", limit:" +
		READ_LIMIT +
		", incrementing offset by " +
		READ_LIMIT +
		" until done></file>"
	);
}

/** UTF-16 head slice, backed past a lone high surrogate so it never splits a pair. */
function headSlice(content: string): string {
	let s = content.slice(0, HEAD_CHARS);
	const last = s.charCodeAt(s.length - 1);
	const next = content.charCodeAt(HEAD_CHARS);
	if (last >= 0xd800 && last <= 0xdbff && next >= 0xdc00 && next <= 0xdfff) s = s.slice(0, -1);
	return s;
}

/** Count complete lines (newlines) in the head, so the directive resumes with no data loss. */
function headCompleteLineCount(head: string): number {
	let n = 0;
	for (let i = 0; i < head.length; i++) if (head.charCodeAt(i) === 0x0a) n++;
	return n;
}

// ── directory listing (kept from the prior prompt_expansion; read can't do dirs) ─
function compareEntries(a: Dirent, b: Dirent): number {
	const x = a.name.toLowerCase();
	const y = b.name.toLowerCase();
	return x < y ? -1 : x > y ? 1 : 0;
}

/** `ls -F`-style label: directories → `/`, symlinks → `@`, else bare name. */
function entryLabel(e: Dirent): string {
	const suffix = e.isDirectory() ? "/" : e.isSymbolicLink() ? "@" : "";
	return e.name + suffix;
}

/** List a directory one level deep, gating hidden entries by count. Never throws. */
async function listDir(absPath: string): Promise<{ header: string; body: string } | null> {
	let entries: Dirent[];
	try {
		entries = await fs.readdir(absPath, { withFileTypes: true });
	} catch {
		return null;
	}
	const hiddenCount = entries.reduce((n, e) => n + (e.name.startsWith(".") ? 1 : 0), 0);
	const includeHidden = hiddenCount <= LIMIT_HIDDEN_FILES;
	const body =
		entries.length === 0
			? "(empty directory)"
			: entries
					.filter((e) => includeHidden || !e.name.startsWith("."))
					.sort(compareEntries)
					.map(entryLabel)
					.join("\n");
	const header = includeHidden ? `@${absPath}/:` : `@${absPath}/ (hidden files omitted):`;
	return { header, body };
}

/** Remaining context budget (tokens), or null when unknown → caller injects whole. */
function computeRemaining(ctx: ExtensionContext): number | null {
	try {
		const usage = ctx.getContextUsage();
		if (!usage || usage.tokens === null) return null; // unknown (e.g. right after compaction)
		const reserve = ctx.model?.maxTokens ?? DEFAULT_RESERVE;
		return Math.max(0, usage.contextWindow - usage.tokens - reserve - MARGIN);
	} catch {
		return null;
	}
}

/**
 * Resolve every `@path` in `text` into `<file>` blocks (files) or text listings
 * (directories). Best-effort sequential budgeting: each delivered file subtracts
 * its cost from `remaining` so a run of files can tip later ones onto the paged
 * path. Never throws — per-path failures leave that token verbatim.
 */
export async function buildInjections(text: string, ctx: ExtensionContext): Promise<Injections> {
	const refs = extractRefs(text);
	let remaining = computeRemaining(ctx);
	const blocks: string[] = [];
	const details: FileDetail[] = [];
	const seen = new Set<string>(); // by resolved absolute path
	let injected = 0;
	let paged = 0;

	for (const ref of refs) {
		const abs = path.resolve(ctx.cwd, expandTilde(ref));
		if (seen.has(abs)) continue; // dedup before any I/O

		let st;
		try {
			st = await fs.stat(abs);
		} catch {
			continue; // missing → leave verbatim
		}
		seen.add(abs); // claim (delivered, or explicitly skipped below — a dup would skip too)

		if (st.isDirectory()) {
			const listing = await listDir(abs);
			if (!listing) continue; // unreadable dir → leave verbatim
			blocks.push(`${listing.header}\n${listing.body}`);
			details.push({ path: abs, kind: "dir", body: `${listing.header}\n${listing.body}` });
			injected++;
			continue;
		}
		if (!st.isFile()) continue; // socket / fifo / etc. → leave verbatim

		let buf: Buffer;
		try {
			buf = await fs.readFile(abs);
		} catch {
			continue; // unreadable file → leave verbatim
		}

		if (isBinary(buf)) {
			blocks.push(formatBinaryBlock(abs));
			details.push({ path: abs, kind: "binary" });
			injected++;
			continue;
		}

		const content = buf.toString("utf8");
		const fileCost = Math.ceil(content.length / 4);
		// Whole when: budget unknown, or it fits the threshold, or it's sub-head-sized
		// (a sub-head file has nothing to page — a directive would point past EOF).
		if (remaining === null || fileCost <= PAGED_THRESHOLD * remaining || content.length <= HEAD_CHARS) {
			blocks.push(formatTextFileBlock(abs, content));
			details.push({ path: abs, kind: "text", body: content });
			if (remaining !== null) remaining = Math.max(0, remaining - fileCost);
		} else {
			const head = headSlice(content);
			const headLines = headCompleteLineCount(head);
			const startLine = headLines + 1; // 1-indexed line AFTER the complete lines in the head
			blocks.push(formatTextFileBlock(abs, head));
			blocks.push(formatPagedDirectiveBlock(abs, content.length, startLine, headLines));
			details.push({
				path: abs,
				kind: "paged",
				body: head,
				range: `:${startLine}-`,
				directive: `<paged: ${content.length} chars; head delivered ${headLines} complete lines; read the rest at offset:${startLine}, limit:${READ_LIMIT}>`,
			});
			paged++;
			if (remaining !== null) remaining = Math.max(0, remaining - Math.ceil(HEAD_CHARS / 4));
		}
		injected++;
	}

	return { blocks, details, injected, paged };
}

// ── TUI rendering ────────────────────────────────────────────────────────────
/** Leading `~` for a home-relative path, for readable display (read-tool parity). */
function tildify(abs: string): string {
	const home = os.homedir();
	return home && abs.startsWith(home + "/") ? "~" + abs.slice(home.length) : abs;
}

function expandHint(theme: any): string {
	return " " + theme.fg("dim", "(ctrl+o to expand)");
}

/** One collapsed line per item, read-tool-style: `read <path>` / `ls <dir>/`. */
function itemLine(d: FileDetail, theme: any): string {
	const isDir = d.kind === "dir";
	const title = theme.fg("toolTitle", theme.bold(isDir ? "ls" : "read"));
	const p = theme.fg("accent", tildify(d.path) + (isDir ? "/" : ""));
	if (d.kind === "binary") return `${title} ${p} ${theme.fg("dim", "(binary \u2014 not injected)")}`;
	if (d.kind === "paged") return `${title} ${p}${theme.fg("warning", d.range ?? "")}`;
	return `${title} ${p}`;
}

/**
 * Renders the injected-items custom message as a compact green box: one line per
 * item when collapsed, full contents (syntax-highlighted for files, raw for
 * dirs) plus the paging directive when expanded via ctrl+o. Mirrors the read
 * tool's rendering. Bodies come from `details` (renderer-only, never sent to the
 * model) so a file containing a literal `</file>` can't mis-truncate display.
 */
function renderInjected(message: any, opts: { expanded?: boolean }, theme: any): Component {
	const files: FileDetail[] = message?.details?.files ?? [];
	const box = new Box(1, 1, (t: string) => theme.bg("toolSuccessBg", t));
	if (files.length === 0) {
		box.addChild(
			new Text(theme.fg("toolTitle", theme.bold("read")) + " " + theme.fg("dim", "(injected)") + expandHint(theme), 0, 0),
		);
		return box;
	}
	for (let i = 0; i < files.length; i++) {
		const d = files[i];
		box.addChild(new Text(itemLine(d, theme) + (i === 0 ? expandHint(theme) : ""), 0, 0));
		if (opts.expanded && typeof d.body === "string") {
			if (d.kind === "binary") continue; // nothing to show
			if (d.kind === "dir") {
				box.addChild(new Text(theme.fg("toolOutput", d.body), 0, 0));
			} else {
				const lang = getLanguageFromPath(d.path);
				const rendered = lang ? highlightCode(d.body, lang).join("\n") : d.body;
				box.addChild(new Text(theme.fg("toolOutput", rendered), 0, 0));
				if (d.kind === "paged" && d.directive) {
					box.addChild(new Text(theme.fg("dim", d.directive), 0, 0));
				}
			}
		}
	}
	return box;
}

// ── extension entry ──────────────────────────────────────────────────────────
export default function (pi: ExtensionAPI) {
	// One-shot handoff stash from the input handler to before_agent_start. input
	// produces the work (file I/O + blocks/details); before_agent_start publishes
	// it as the custom message after the user message. prompt() runs input → … →
	// before_agent_start sequentially (one awaited call), so there is no race.
	// Cleared unconditionally in before_agent_start (one-shot per submit) so a
	// later no-`@` prompt never re-delivers a stale stash.
	let pending: { blocks: string[]; details: FileDetail[] } | null = null;

	pi.on("session_start", () => {
		// Register the chat renderer ONCE. customType MUST match before_agent_start's
		// "promptExpansion.injected" exactly (the handshake). No hasUI guard — the
		// renderer fn is only invoked in TUI mode; it's a no-op in print/json.
		pi.registerMessageRenderer("promptExpansion.injected", (message: any, opts: any, theme: any) =>
			renderInjected(message, opts, theme),
		);
	});

	pi.on("input", async (event: InputEvent, ctx: ExtensionContext) => {
		if (event.source === "extension") return { action: "continue" }; // loop prevention
		if (event.streamingBehavior === "steer") return { action: "continue" }; // skip mid-stream steering
		if (!event.text?.includes("@")) return { action: "continue" }; // cheap pre-check before regex/IO

		const { blocks, details, injected, paged } = await buildInjections(event.text, ctx);
		if (injected === 0) return { action: "continue" }; // nothing resolved → prompt byte-for-byte

		pending = { blocks, details };

		if (ctx.hasUI) {
			const msg = `@ expanded ${injected} file${injected === 1 ? "" : "s"}${paged > 0 ? `, ${paged} paged` : ""}`;
			ctx.ui.notify(msg, "info");
		}

		// text VERBATIM: the prompt is never modified, so cancel/fork//tree re-open
		// re-triggers injection. images pass through untouched.
		return { action: "transform" as const, text: event.text, images: event.images ?? [] };
	});

	pi.on("before_agent_start", async () => {
		if (!pending) return undefined; // no @, or short-circuited, or nothing resolved
		const { blocks, details } = pending;
		pending = null; // clear regardless — one-shot per submit
		return {
			message: {
				customType: "promptExpansion.injected", // the renderer's registered customType
				content: blocks.join("\n\n"), // every <file>/dir block → sent to the LLM
				display: true, // render in the TUI (renderer registered above)
				details: { files: details }, // renderer metadata; NOT extra model text
			},
		};
	});
}
