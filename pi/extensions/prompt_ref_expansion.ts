/**
 * prompt_ref_expansion — inline @path file references into the prompt.
 *
 * pi's TUI inserts `@path` references as plain-text pointers; the model has to
 * call `read` to see them. This extension expands `@path` tokens in the most
 * recent user message by appending each referenced file's contents below the
 * original prompt, leaving what the user typed byte-for-byte intact:
 *
 *   read through @foobar.ts and tell me what you think.
 *
 *   @foobar.ts:
 *   <foobar.ts contents>
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
 *   - no size cap on text files (deliberate; re-add one if context bloat bites)
 *   - mtime-cached so repeated turns don't re-read unchanged files
 *   - only the latest user message is expanded (keeps history lean)
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { statSync, openSync, readSync, closeSync } from "node:fs";
import { resolve as resolvePath, isAbsolute } from "node:path";
import { homedir } from "node:os";

const SAMPLE_BYTES = 8192;

// @ matches only when preceded by start-of-string or whitespace — kept
// consistent with the autocomplete trigger (fuzzy-filter.ts), which pi-tui's
// compiled Editor hardcodes to the same boundary and no extension can widen.
// So (@foo)/[@foo]/{@foo} are intentionally NOT treated as mentions. Also
// does not match after letters/quotes/backticks, so emails (foo@bar.com) and
// code spans (`@foo`) are left alone.
const AT_TOKEN = /(^|\s)@(\S+)/g;
const TRAIL_PUNCT = /[.,;:!?)]+$/;

// absPath -> { mtimeMs, text: string | null }  (null = known-unreadable)
const cache = new Map<string, { mtimeMs: number; text: string | null }>();

interface Resolved {
	absPath: string;
	text: string;
}

function resolveRef(ref: string, cwd: string): Resolved | null {
	let p = ref.startsWith("~") ? homedir() + ref.slice(1) : ref;
	p = isAbsolute(p) ? p : resolvePath(cwd, p);

	let st: { isFile: () => boolean; size: number; mtimeMs: number };
	try {
		const s = statSync(p);
		st = { isFile: s.isFile.bind(s), size: s.size, mtimeMs: s.mtimeMs };
	} catch {
		return null;
	}
	if (!st.isFile()) return null;

	const cached = cache.get(p);
	if (cached && cached.mtimeMs === st.mtimeMs) {
		return cached.text == null ? null : { absPath: p, text: cached.text };
	}

	// Text vs binary: NUL-byte heuristic (git/ripgrep method). Check an 8KB
	// head sample first so a multi-GB binary is rejected without reading it
	// all; if the sample is clean, read the full file.
	let fd: number;
	try {
		fd = openSync(p, "r");
	} catch {
		return null;
	}
	try {
		const sampleLen = Math.min(st.size, SAMPLE_BYTES);
		if (sampleLen > 0) {
			const sample = Buffer.alloc(sampleLen);
			readSync(fd, sample, 0, sampleLen, 0);
			if (sample.includes(0)) {
				cache.set(p, { mtimeMs: st.mtimeMs, text: null });
				return null;
			}
		}
		const full = Buffer.alloc(st.size);
		if (st.size > 0) readSync(fd, full, 0, st.size, 0);
		const text = full.toString("utf8");
		cache.set(p, { mtimeMs: st.mtimeMs, text });
		return { absPath: p, text };
	} finally {
		closeSync(fd);
	}
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
		blocks.push(`@${ref}:\n${resolved.text}`);
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
