/**
 * prompt_expansion — inline @path references into the prompt.
 *
 * pi's TUI inserts `@path` references as plain-text pointers; the model has to
 * call `read` to see them. This extension expands `@path` tokens in the most
 * recent user message by appending each referenced target's contents below the
 * original prompt, leaving what the user typed byte-for-byte intact:
 *
 *   read through @foobar.ts and tell me what you think.
 *
 *   @foobar.ts:
 *   <foobar.ts contents>
 *
 * Directories expand to a sorted entry listing (subdirectories suffixed with
 * `/`, symlinks with `@`) — like `ls -1 -F`:
 *
 *   what's in @pi/extensions/?
 *
 *   @pi/extensions/:
 *   footer.ts
 *   fuzzy-filter.ts
 *   herald.ts
 *
 * Hidden entries (names starting with `.`) are included only when there are
 * few of them (see LIMIT_HIDDEN_FILES). When included, the header is the bare
 * `@<dir>/:`. When omitted, pi appends a note so the model knows it's seeing a
 * partial listing:
 *
 *   @<dir>/ (hidden files omitted):
 *   <visible entries only>
 *
 * Hook: `context` event (fires before each LLM call with a deep copy of the
 * messages — non-destructive, the session keeps the literal `@path` text).
 *
 * Guards:
 *   - only @-prefixed refs (no bare-filename inference)
 *   - binary files are skipped via the NUL-byte heuristic (same as git /
 *     ripgrep): if the file contains any 0x00 byte it's treated as binary.
 *     An 8KB head sample is checked first so a huge binary is rejected
 *     without reading it all; if clean, the full file is injected.
 *   - directories are listed one level deep (never recursed); `.`/`..` excluded
 *   - no size cap on text files or entry count (deliberate; re-add one if
 *     context bloat bites)
 *   - file contents are mtime-cached so repeated turns don't re-read unchanged
 *     files; directory listings are re-read each turn (cheap readdir, and the
 *     listing may change between turns)
 *   - only the latest user message is expanded (keeps history lean)
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { statSync, openSync, readSync, closeSync, readdirSync } from "node:fs";
import type { Stats, Dirent } from "node:fs";
import { resolve as resolvePath, isAbsolute } from "node:path";
import { homedir } from "node:os";

const SAMPLE_BYTES = 8192;

/**
 * Hidden-entry threshold for directory listings. Flow: count a directory's
 * hidden entries (names starting with `.`); if the count exceeds this limit,
 * list visible entries only (and annotate the header accordingly), otherwise
 * list visible + hidden.
 */
const LIMIT_HIDDEN_FILES = 50;

// @ matches only when preceded by start-of-string or whitespace — kept
// consistent with the autocomplete trigger (fuzzy-filter.ts), which pi-tui's
// compiled Editor hardcodes to the same boundary and no extension can widen.
// So (@foo)/[@foo]/{@foo} are intentionally NOT treated as mentions. Also
// does not match after letters/quotes/backticks, so emails (foo@bar.com) and
// code spans (`@foo`) are left alone.
const AT_TOKEN = /(^|\s)@(\S+)/g;
const TRAIL_PUNCT = /[.,;:!?)]+$/;

// absPath -> { mtimeMs, text: string | null }  (null = known-unreadable/binary)
// Only files are cached; directory listings are re-read each turn.
const cache = new Map<string, { mtimeMs: number; text: string | null }>();

interface Resolved {
	absPath: string;
	header: string; // e.g. "@foobar.ts:" / "@<dir>/:" / "@<dir>/ (hidden files omitted):"
	body: string;
}

function resolveRef(ref: string, cwd: string): Resolved | null {
	let p = ref.startsWith("~") ? homedir() + ref.slice(1) : ref;
	p = isAbsolute(p) ? p : resolvePath(cwd, p);

	let st: Stats;
	try {
		st = statSync(p);
	} catch {
		return null;
	}

	if (st.isDirectory()) return resolveDir(ref, p);
	if (st.isFile()) return resolveFile(ref, p, st.size, st.mtimeMs);
	return null;
}

/** Read a regular file, returning its full text (or null if binary/unreadable). */
function resolveFile(
	ref: string,
	absPath: string,
	size: number,
	mtimeMs: number,
): Resolved | null {
	const cached = cache.get(absPath);
	if (cached && cached.mtimeMs === mtimeMs) {
		return cached.text == null ? null : { absPath, header: `@${ref}:`, body: cached.text };
	}

	// Text vs binary: NUL-byte heuristic (git/ripgrep method). Check an 8KB
	// head sample first so a multi-GB binary is rejected without reading it
	// all; if the sample is clean, read the full file.
	let fd: number;
	try {
		fd = openSync(absPath, "r");
	} catch {
		return null;
	}
	try {
		const sampleLen = Math.min(size, SAMPLE_BYTES);
		if (sampleLen > 0) {
			const sample = Buffer.alloc(sampleLen);
			readSync(fd, sample, 0, sampleLen, 0);
			if (sample.includes(0)) {
				cache.set(absPath, { mtimeMs, text: null });
				return null;
			}
		}
		const full = Buffer.alloc(size);
		if (size > 0) readSync(fd, full, 0, size, 0);
		const text = full.toString("utf8");
		cache.set(absPath, { mtimeMs, text });
		return { absPath, header: `@${ref}:`, body: text };
	} finally {
		closeSync(fd);
	}
}

/**
 * List a directory's entries (one level deep), gating hidden entries by count.
 * Hidden included (≤ LIMIT)  → bare header "@<dir>/:".
 * Hidden omitted (> LIMIT)   → "@<dir>/ (hidden files omitted):".
 */
function resolveDir(ref: string, absPath: string): Resolved | null {
	let entries: Dirent[];
	try {
		entries = readdirSync(absPath, { withFileTypes: true });
	} catch {
		return null;
	}
	// readdirSync already excludes "." and "..".
	const hiddenCount = entries.reduce(
		(n, e) => n + (e.name.startsWith(".") ? 1 : 0),
		0,
	);
	const includeHidden = hiddenCount <= LIMIT_HIDDEN_FILES;

	const body = entries
		.filter((e) => includeHidden || !e.name.startsWith("."))
		.sort(compareEntries)
		.map(entryLabel)
		.join("\n");

	const dirRef = ref.endsWith("/") ? ref : ref + "/";
	const header = includeHidden ? `@${dirRef}:` : `@${dirRef} (hidden files omitted):`;
	return { absPath, header, body };
}

/** Case-insensitive alphabetical sort (matches `ls` ordering well enough). */
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

function extractRefs(text: string): string[] {
	const refs: string[] = [];
	let m: RegExpExecArray | null;
	AT_TOKEN.lastIndex = 0;
	while ((m = AT_TOKEN.exec(text)) !== null) {
		const path = m[2].replace(TRAIL_PUNCT, "");
		if (path) refs.push(path);
	}
	// de-dup by as-typed form, preserve order
	return [...new Set(refs)];
}

/** Build the appended block, or null if nothing resolvable. */
function buildAppendBlock(text: string, cwd: string): string | null {
	const refs = extractRefs(text);
	if (refs.length === 0) return null;
	const blocks: string[] = [];
	const seen = new Set<string>(); // by resolved absPath
	for (const ref of refs) {
		const resolved = resolveRef(ref, cwd);
		if (!resolved || seen.has(resolved.absPath)) continue;
		seen.add(resolved.absPath);
		blocks.push(`${resolved.header}\n${resolved.body}`);
	}
	return blocks.length > 0 ? blocks.join("\n") : null;
}

export default function (pi: ExtensionAPI) {
	pi.on("context", async (event, ctx) => {
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

		// collect text from the message
		let text: string | undefined;
		if (typeof content === "string") {
			text = content;
		} else if (Array.isArray(content)) {
			text = content
				.filter((c: any) => c && c.type === "text")
				.map((c: any) => c.text)
				.join("\n");
		}
		if (!text) return;

		const append = buildAppendBlock(text, ctx.cwd);
		if (!append) return;

		const addition = "\n\n" + append;
		if (typeof content === "string") {
			msg.content = content + addition;
		} else if (Array.isArray(content)) {
			// append as a new text part; leave original parts untouched
			content.push({ type: "text", text: addition });
		} else {
			return;
		}

		return { messages };
	});
}
