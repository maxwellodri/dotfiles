/**
 * nvim-edit.ts — route the built-in `edit`/`write` tools through Neovim when
 * the agent was spawned by the nvim integration (lua/user/pi.lua in the
 * dotfiles repo).
 *
 * How it works:
 *   - lua/user/pi.lua runs `pi --mode rpc` as a child process with
 *     PI_NVIM_SOCKET pointing at a unix socket it listens on.
 *   - This extension forwards every `edit`/`write` tool call to nvim, which
 *     applies it to the matching buffer via the buffer API (real undo
 *     history, marks preserved, instant visibility) and writes the file.
 *   - When nvim applies the change we BLOCK the tool call with an
 *     "[nvim] applied" reason so pi's dispatcher never double-writes.
 *
 * Fallbacks (the session stays usable anywhere):
 *   - socket unreachable / nvim gone     -> native disk edit (TUI resume,
 *                                            detached runs)
 *   - file not open in nvim (no buffer)  -> native disk edit
 *   - nvim has the buffer but the edit fails (e.g. oldText not unique) ->
 *     block with the error so the model can retry, mirroring pi's own edit
 *     failure semantics.
 *
 * Blocked tool results come back with isError=true; a message_end handler
 * flips that back for applied calls so the model doesn't treat accepted
 * edits as failures.
 *
 * Also registered (unconditionally, socket or not):
 *   - /nvim-accept <json> — appends an nvim.acceptedEdit CustomMessageEntry
 *     (instruction + unified diff) to the session with NO agent turn. Invoked
 *     by lua/user/pi.lua when you accept an inline edit; the per-nvim-process
 *     persistent session accumulates one block per accepted edit, so opening
 *     it in the TUI gives the agent full context of everything accepted.
 *   - a message renderer so those blocks show as one compact line (ctrl+o
 *     expands the diff) in the TUI.
 *
 * Inert by design: without PI_NVIM_SOCKET the edit/write routing registers
 * nothing and every normal terminal pi run is untouched.
 *
 * Load: auto-discovered from pi/extensions/*.ts; `/reload` after edits.
 */
import type { ExtensionAPI, SessionManager } from "@earendil-works/pi-coding-agent";
import { Box, Text, type Component } from "@earendil-works/pi-tui";
import { createConnection, type Socket } from "node:net";
import { isAbsolute, resolve } from "node:path";

const SOCKET_ENV = "PI_NVIM_SOCKET";
const TIMEOUT_MS = 3000;

type NvimReply = {
	id: string;
	applied: boolean;
	reason?: string;
	error?: string;
};

/** Send one JSONL request to nvim, resolve one JSONL reply, then hang up. */
function askNvim(socketPath: string, payload: Record<string, unknown>): Promise<NvimReply | null> {
	return new Promise((done) => {
		let settled = false;
		const finish = (reply: NvimReply | null) => {
			if (settled) return;
			settled = true;
			clearTimeout(timer);
			try {
				sock.destroy();
			} catch {
				/* already gone */
			}
			done(reply);
		};
		const timer = setTimeout(() => finish(null), TIMEOUT_MS);

		let buf = "";
		const sock: Socket = createConnection(socketPath);
		sock.on("connect", () => {
			sock.write(JSON.stringify(payload) + "\n");
		});
		sock.on("data", (chunk: Buffer) => {
			buf += chunk.toString("utf8");
			const nl = buf.indexOf("\n");
			if (nl === -1) return;
			let line = buf.slice(0, nl);
			if (line.endsWith("\r")) line = line.slice(0, -1);
			try {
				finish(JSON.parse(line) as NvimReply);
			} catch {
				finish(null);
			}
		});
		sock.on("error", () => finish(null));
		sock.on("close", () => finish(null));
	});
}

/** Payload sent by lua/user/pi.lua with /nvim-accept (stored as details). */
type AcceptedEdit = {
	file?: string;
	a?: number;
	b?: number;
	instruction?: string;
	diff?: string;
};

function renderAccepted(message: any, opts: { expanded?: boolean }, theme: any): Component {
	const d = (message?.details ?? {}) as AcceptedEdit;
	const box = new Box(1, 1, (t: string) => theme.bg("toolSuccessBg", t));
	const loc = `${d.file ?? "?"}${d.a !== undefined ? `:${d.a}-${d.b ?? d.a}` : ""}`;
	box.addChild(
		new Text(
			" " +
				theme.fg("toolTitle", theme.bold("nvim-accepted")) +
				" " +
				theme.fg("accent", loc) +
				theme.fg("dim", ` — ${d.instruction ?? ""}`) +
				theme.fg("dim", " (ctrl+o for diff)"),
			0,
			0,
		),
	);
	if (opts.expanded && typeof d.diff === "string") {
		for (const line of d.diff.split("\n")) {
			if (line === "") continue;
			const fg = line.startsWith("+") ? "toolOutput" : "dim";
			box.addChild(new Text(" " + theme.fg(fg, line), 0, 0));
		}
	}
	return box;
}

export default function (pi: ExtensionAPI) {
	// Session bookkeeping — registered unconditionally: the command runs in
	// the persistent nvim child; the renderer runs in any TUI that opens a
	// session containing accepted-edit blocks.
	pi.on("session_start", () => {
		pi.registerMessageRenderer("nvim.acceptedEdit", renderAccepted);
	});

	pi.registerCommand("nvim-accept", {
		description: "Record an accepted nvim inline edit into this session (used by lua/user/pi.lua)",
		handler: async (args: string, ctx) => {
			await ctx.waitForIdle();
			let p: AcceptedEdit;
			try {
				p = JSON.parse(args) as AcceptedEdit;
			} catch {
				return; // malformed payload — drop rather than corrupt the session
			}
			const loc = p.a !== undefined ? ` lines ${p.a}-${p.b ?? p.a}` : "";
			const content =
				`Accepted inline edit in nvim — ${p.file ?? "?"}${loc}\n` +
				`Instruction: ${p.instruction ?? "(none)"}\n\n${p.diff ?? ""}`;
			// ctx.sessionManager is TYPED read-only, but the runtime object is the
			// full SessionManager, and command handlers are the sanctioned place
			// to mutate the session (waitForIdle docs: "safe to modify session").
			// appendCustomMessageEntry participates in LLM context until
			// compaction, unlike plain custom entries.
			(ctx.sessionManager as unknown as SessionManager).appendCustomMessageEntry(
				"nvim.acceptedEdit",
				content,
				true,
				p,
			);
		},
	});

	const socketPath = process.env[SOCKET_ENV];
	if (!socketPath) return; // not spawned from nvim — routing stays inert

	const appliedCalls = new Set<string>();

	pi.on("tool_call", async (event, ctx) => {
		if (event.toolName !== "edit" && event.toolName !== "write") return;

		const raw = event.input as {
			path?: unknown;
			oldText?: unknown;
			newText?: unknown;
			content?: unknown;
		};
		if (typeof raw.path !== "string" || raw.path.length === 0) return;

		// Models sometimes prefix paths with @; built-in tools strip it too.
		const cleaned = raw.path.replace(/^@/, "");
		const abs = isAbsolute(cleaned) ? cleaned : resolve(ctx.cwd, cleaned);

		const payload: Record<string, unknown> = {
			id: String(event.toolCallId),
			op: event.toolName,
			path: abs,
			pid: process.pid, // lua maps pid -> child for edit attribution
		};
		if (typeof raw.oldText === "string") payload.oldText = raw.oldText;
		if (typeof raw.newText === "string") payload.newText = raw.newText;
		if (typeof raw.content === "string") payload.content = raw.content;

		const reply = await askNvim(socketPath, payload);

		// nvim unreachable — detached run, fall back to native execution.
		if (!reply) return undefined;

		if (reply.applied) {
			appliedCalls.add(String(event.toolCallId));
			return {
				block: true,
				reason: `[nvim] ${event.toolName} applied to ${cleaned} via the Neovim buffer. File saved.`,
			};
		}

		// Not open in nvim — native execution on disk.
		if (reply.reason === "no-buffer") return undefined;

		// nvim has the buffer but failed (oldText not found / not unique,
		// write error). Block with the error so the model can fix its edit.
		return {
			block: true,
			reason: `[nvim] ${event.toolName} failed: ${reply.error ?? "unknown nvim error"}`,
		};
	});

	// Blocked tool results are isError=true; flip applied ones back so the
	// model sees them as successes. Returned via { message } — the documented
	// message_end replacement contract; in-place mutation is not guaranteed to
	// survive the event boundary.
	pi.on("message_end", async (event) => {
		const msg = event.message;
		if (!("toolCallId" in msg) || typeof msg.toolCallId !== "string") return;
		if (appliedCalls.delete(msg.toolCallId)) {
			msg.isError = false;
			return { message: msg };
		}
	});

	// A batch aborted mid-flight can orphan IDs (no message_end ever comes);
	// turn_end is the last safe point to drop them.
	pi.on("turn_end", () => {
		appliedCalls.clear();
	});
}
