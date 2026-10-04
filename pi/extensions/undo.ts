/**
 * undo.ts — C-x u / /undo: rewind one user-turn via navigateTree.
 * Non-destructive (the abandoned turn stays in the tree for /tree); a busy
 * agent is interrupted first so C-x u always undoes. Refuses to land on a
 * compaction entry — that leaf breaks /compact. Binding registered through
 * leader-key's globalThis registry (see leader-key.ts).
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

			// A compaction is a hard boundary. The branch is root→leaf and linear,
			// so the entry immediately before this user message
			// (branch[lastUserIdx - 1]) is its parent. If that parent is a
			// compaction, rewinding to it would land ON the compaction entry — a
			// degenerate leaf where the session is already compacted (a manual
			// /compact then fails with "Already compacted") and the just-sent
			// message is dropped from the active path. We can't instead land on
			// the user message itself: navigateTree() always rewinds a user
			// message to its parent, and the session is append-only, so there is
			// no way from here to "remove only the response". Treat the
			// compaction as a wall and leave the turn in place; /tree can still
			// branch from it.
			const parentEntry = lastUserIdx > 0 ? branch[lastUserIdx - 1] : undefined;
			if (parentEntry?.type === "compaction") {
				ctx.ui.notify("Can't undo: previous turn starts at a compaction boundary", "info");
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
			ctx.ui.setEditorText(messageToText((userEntry.message as { content: unknown }).content));
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
