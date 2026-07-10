/**
 * undo.ts — C-x u : undo the most recent turn.
 *
 * Wires two things:
 *   1. A `/undo` command that rewinds the session one user-turn back via the
 *      tree-navigation API (`ctx.navigateTree`). That API is only available on
 *      command contexts, so the real work must live in a command — it cannot
 *      be done from the leader editor's input handler directly.
 *   2. A leader-key binding for "u" that fires the command through pi's normal
 *      submit path. `ctx.submit("/undo")` routes through the interactive
 *      submit handler, which is what dispatches extension commands; calling
 *      `pi.sendUserMessage("/undo")` instead would SKIP command handling and
 *      send the literal string to the model.
 *
 * If the agent is busy when `/undo` runs, it is interrupted and the rewind
 * proceeds once idle (so `C-x u` always undoes, even mid-stream).
 *
 * "Undo to prior turn" is NON-DESTRUCTIVE: it moves the session leaf back to
 * the entry immediately before the most recent user message. The abandoned
 * turn stays in the session tree and can be revisited with `/tree`. This is
 * exactly pi's own branch-navigation primitive, just driven from a key.
 *
 * Depends on leader-key.ts (the leader host). The binding is registered through
 * the globalThis registry rather than an import because pi loads extensions
 * with `moduleCache` disabled. See leader-key.ts for the full rationale.
 *
 * Load: auto-discovered from pi/extensions/*.ts; `/reload` after edits.
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { getLeaderRegistry, type LeaderCtx } from "./leader-key";

const BINDING_KEY = "u";

/**
 * Best-effort text extraction from a user message's content blocks, so the
 * undone prompt can be restored to the editor (images are dropped — only
 * text can live in the prompt box).
 */
function messageToText(content: unknown): string {
	if (typeof content === "string") return content;
	if (!Array.isArray(content)) return "";
	const parts: string[] = [];
	for (const block of content) {
		if (
			block !== null &&
			typeof block === "object" &&
			(block as { type?: string }).type === "text" &&
			typeof (block as { text?: unknown }).text === "string"
		) {
			parts.push((block as { text: string }).text);
		}
	}
	return parts.join("\n");
}

export default function (pi: ExtensionAPI) {
	pi.registerCommand("undo", {
		description: "Undo the most recent turn, interrupting the agent first if busy",
		handler: async (_args, ctx) => {
			// If the agent is mid-run, interrupt it and wait for it to fully
			// settle before mutating session state — rewinding while a turn is
			// still active would race the agent loop.
			if (!ctx.isIdle()) {
				ctx.abort();
				await ctx.waitForIdle();
			}

			// getBranch() with no arg: active branch, root → leaf, real entries.
			const branch = ctx.sessionManager.getBranch();

			// Find the most recent USER message (the start of the current turn).
			let lastUserIdx = -1;
			for (let i = branch.length - 1; i >= 0; i--) {
				const entry = branch[i];
				if (entry.type === "message" && entry.message.role === "user") {
					lastUserIdx = i;
					break;
				}
			}

			if (lastUserIdx < 0) {
				ctx.ui.notify("Nothing to undo", "info");
				return;
			}

			// Re-fetch and re-narrow (the SessionEntry union doesn't carry across
			// the index lookup) so we can read both parentId and message content.
			const userEntry = branch[lastUserIdx];
			if (userEntry.type !== "message") {
				ctx.ui.notify("Nothing to undo", "info");
				return;
			}

			// Navigate to the entry immediately BEFORE that user message. In a
			// linear branch the message's parentId is that predecessor; it is
			// null only when the message is the root (first entry), in which
			// case there is no prior turn to return to.
			const target = userEntry.parentId;
			if (!target) {
				ctx.ui.notify("Nothing to undo", "info");
				return;
			}

			const result = await ctx.navigateTree(target);
			if (result?.cancelled) return;

			// Repopulate the prompt with the undone message so it can be tweaked
			// and resent. The submit path clears the editor on the way in; doing
			// this AFTER navigateTree means it is the final write to the box.
			ctx.ui.setEditorText(messageToText(userEntry.message.content));
			ctx.ui.notify("Undid last turn", "info");
		},
	});

	pi.on("session_start", () => {
		getLeaderRegistry().register(BINDING_KEY, {
			description: "Undo to prior turn",
			handler: (ctx: LeaderCtx) => {
				ctx.submit("/undo");
			},
		});
	});

	pi.on("session_shutdown", () => {
		getLeaderRegistry().unregister(BINDING_KEY);
	});
}
