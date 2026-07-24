/**
 * prompt_expansion — inline @path references into the prompt.
 *
 * pi's TUI inserts `@path` references as plain-text pointers; the model has to
 * call `read` to see them. This extension expands `@path` tokens in the most
 * recent user message so the contents are already in context, leaving what the
 * user typed byte-for-byte intact.
 *
 *   - **Files** are expanded as a synthetic `read` tool call: an assistant
 *     message carrying one `toolCall` block per file, immediately followed by
 *     matching `toolResult` messages with the file contents. To the model this
 *     is indistinguishable from having called `read` itself, which makes it
 *     unmistakable that a read was already performed (the original motivation:
 *     pasted-text appends were sometimes not recognized as a read the agent
 *     could rely on, so it would re-`read` the same file).
 *
 *       read through @foobar.ts and tell me what you think.
 *
 *       → [user message, unchanged]
 *         [assistant: toolCall read { path: "foobar.ts" }]
 *         [toolResult read: <foobar.ts contents>]
 *
 *     Empty files/dirs are annotated: an empty file's toolResult is
 *     `(empty file)` (the real `read` tool returns a blank string, which
 *     leaves the model unsure a read even happened) and an empty directory's
 *     listing body is `(empty directory)` (rather than a bare header line).
 *
 *   - **Directories** have no `read` equivalent, so they expand to a sorted
 *     entry listing (subdirectories suffixed with `/`, symlinks with `@`) —
 *     like `ls -1 -F` — appended as text below the prompt:
 *
 *       what's in @pi/extensions/?
 *
 *       @pi/extensions/:
 *       footer.ts
 *       fuzzy-filter.ts
 *       herald.ts
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
 * messages — non-destructive, the session keeps the literal `@path` text; the
 * synthetic read messages exist only in the copy sent to the LLM).
 *
 * Guards:
 *   - only @-prefixed refs (no bare-filename inference)
 *   - binary files are skipped via the NUL-byte heuristic (same as git /
 *     ripgrep): if the file contains any 0x00 byte it's treated as binary and
 *     no synthetic read is emitted for it. An 8KB head sample is checked first
 *     so a huge binary is rejected without reading it all; if clean, the full
 *     file is read.
 *   - directories are listed one level deep (never recursed); `.`/`..` excluded
 *   - no size cap on text files or entry count (deliberate; re-add one if
 *     context bloat bites)
 *   - file contents are mtime-cached so repeated turns don't re-read unchanged
 *     files; directory listings are re-read each turn (cheap readdir, and the
 *     listing may change between turns)
 *   - only the latest user message is expanded (keeps history lean); because
 *     injection is non-destructive, the synthetic reads are re-injected each
 *     turn (cheap — cached) and land right after the user message, so on later
 *     turns the model still sees "it already read these files" before its own
 *     earlier responses.
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

/** A resolved file reference, to be turned into a synthetic read tool call. */
interface FileResolved {
	kind: "file";
	absPath: string;
	ref: string; // as-typed path, exactly what `read` would receive
	text: string;
}

/** A resolved directory reference, to be appended as a text listing. */
interface DirResolved {
	kind: "dir";
	absPath: string;
	header: string; // "@<dir>/:" / "@<dir>/ (hidden files omitted):"
	body: string;
}

type Resolved = FileResolved | DirResolved;

/** A file injection ready to become a toolCall + toolResult pair. */
interface FileInject {
	id: string; // shared by the toolCall block and its toolResult
	ref: string;
	absPath: string;
	text: string;
}

let idCounter = 0;
/** Unique id for a synthetic tool call (matches `toolCall.id` ↔ `toolResult.toolCallId`). */
function syntheticId(): string {
	return `promptexp_${Date.now().toString(36)}_${(idCounter++).toString(36)}`;
}

/**
 * Zeroed Usage for synthetic assistant messages. The AssistantMessage type
 * requires `usage`, and several pi paths read it without null-checks
 * (getSessionStats sums usage.input/.cost.total; getContextUsage calls
 * calculateContextTokens(usage)). All-zero keeps those readers safe while
 * ensuring the message is *not* counted as real token/cost usage —
 * getAssistantUsage / getContextTokens treat a 0-total usage as "no usage"
 * and skip past it.
 */
const ZERO_USAGE = {
	input: 0,
	output: 0,
	cacheRead: 0,
	cacheWrite: 0,
	totalTokens: 0,
	cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 },
};

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
): FileResolved | null {
	const cached = cache.get(absPath);
	if (cached && cached.mtimeMs === mtimeMs) {
		return cached.text == null ? null : { kind: "file", absPath, ref, text: cached.text };
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
		return { kind: "file", absPath, ref, text };
	} finally {
		closeSync(fd);
	}
}

/**
 * List a directory's entries (one level deep), gating hidden entries by count.
 * Hidden included (≤ LIMIT)  → bare header "@<dir>/:".
 * Hidden omitted (> LIMIT)   → "@<dir>/ (hidden files omitted):".
 */
function resolveDir(ref: string, absPath: string): DirResolved | null {
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

	const body =
		entries.length === 0
			? "(empty directory)"
			: entries
					.filter((e) => includeHidden || !e.name.startsWith("."))
					.sort(compareEntries)
					.map(entryLabel)
					.join("\n");

	const dirRef = ref.endsWith("/") ? ref : ref + "/";
	const header = includeHidden ? `@${dirRef}:` : `@${dirRef} (hidden files omitted):`;
	return { kind: "dir", absPath, header, body };
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

interface Injections {
	fileInjects: FileInject[];
	dirBlocks: string[]; // pre-formatted "header\nbody" listings
}

/**
 * Resolve every @path in `text` into either a synthetic read (files) or a text
 * listing block (directories). De-duplicated by resolved absPath.
 */
function buildInjections(text: string, cwd: string): Injections {
	const refs = extractRefs(text);
	const fileInjects: FileInject[] = [];
	const dirBlocks: string[] = [];
	const seen = new Set<string>(); // by resolved absPath
	for (const ref of refs) {
		const resolved = resolveRef(ref, cwd);
		if (!resolved || seen.has(resolved.absPath)) continue;
		seen.add(resolved.absPath);
		if (resolved.kind === "file") {
			fileInjects.push({ id: syntheticId(), ref, absPath: resolved.absPath, text: resolved.text });
		} else {
			dirBlocks.push(`${resolved.header}\n${resolved.body}`);
		}
	}
	return { fileInjects, dirBlocks };
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

		const { fileInjects, dirBlocks } = buildInjections(text, ctx.cwd);
		if (fileInjects.length === 0 && dirBlocks.length === 0) return;

		let mutated = false;

		// 1) Directory listings: append as text below the user message (no read
		//    tool — read has no directory equivalent).
		if (dirBlocks.length > 0) {
			const addition = "\n\n" + dirBlocks.join("\n");
			if (typeof content === "string") {
				msg.content = content + addition;
				mutated = true;
			} else if (Array.isArray(content)) {
				// append as a new text part; leave original parts untouched
				content.push({ type: "text", text: addition });
				mutated = true;
			}
		}

		// 2) Files: splice a synthetic assistant read(toolCall) + toolResult
		//    pair(s) immediately after the user message. To the model this looks
		//    exactly like it already called `read` on each file and got the
		//    contents back.
		if (fileInjects.length > 0) {
			const ts = Date.now();
			// Synthetic assistant message: `usage` is required and zeroed (see
			// ZERO_USAGE) so token/cost readers don't crash and the message isn't
			// counted as real usage. `provider`/`api`/`model` are intentionally
			// omitted — transformMessages then treats it as cross-model and runs
			// the id-normalization path, which is a no-op for our already-clean ids.
			const assistantMsg: any = {
				role: "assistant",
				content: fileInjects.map((f) => ({
					type: "toolCall",
					id: f.id,
					name: "read",
					arguments: { path: f.ref },
				})),
				stopReason: "toolUse",
				usage: ZERO_USAGE,
				timestamp: ts,
			};
			const resultMsgs: any[] = fileInjects.map((f) => ({
				role: "toolResult",
				toolCallId: f.id,
				toolName: "read",
				content: [
					{ type: "text", text: f.text.length === 0 ? "(empty file)" : f.text },
				],
				isError: false,
				timestamp: ts,
			}));
			messages.splice(lastUser + 1, 0, assistantMsg, ...resultMsgs);
			mutated = true;
		}

		if (mutated) return { messages };
	});
}
