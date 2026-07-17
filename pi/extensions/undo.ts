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
 * Compaction boundary: a compaction entry is treated as a wall. If the most
 * recent user message sits directly on a compaction, undo refuses rather than
 * land on the compaction (a degenerate "already compacted" leaf where
 * `/compact` fails and the last message vanishes from the active path).
 * navigateTree() always rewinds a user message to its parent, so landing on
 * the message itself isn't possible from an extension — use `/tree` to branch.
 *
 * Depends on leader-key.ts (the leader host). The binding is registered through
 * the globalThis registry rather than an import because pi loads extensions
 * with `moduleCache` disabled. See leader-key.ts for the full rationale.
 *
 * Load: auto-discovered from pi/extensions/*.ts; `/reload` after edits.
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { writeFileSync } from "node:fs";
import { getLeaderRegistry, type LeaderCtx } from "./leader-key";

// TEMP DIAGNOSTIC — remove once compaction-undo is confirmed.
const DEBUG_LOG = "/tmp/pi-undo-debug.log";

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

			// TEMP DIAGNOSTIC
			try {
				const dbg =
					`undo handler FIRED ${new Date().toISOString()}\n` +
					`branch len=${branch.length}\n` +
					branch.map((e, i) => `  [${i}] ${e.type} ${(e as { id?: string }).id?.slice(0, 8)} parent=${(e as { parentId?: string }).parentId?.slice(0, 8)}${e.type === "message" ? " role=" + (e as { message: { role: string } }).message.role : ""}`).join("\n") +
					"\n";
				writeFileSync(DEBUG_LOG, dbg, { flag: "a" });
			} catch (e) {
				writeFileSync(DEBUG_LOG, `diag failed: ${String(e)}\n`, { flag: "a" });
			}

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
			// TEMP DIAGNOSTIC: log the guard decision
			try { writeFileSync(DEBUG_LOG, `lastUserIdx=${lastUserIdx} parentEntry.type=${parentEntry?.type}\n`, { flag: "a" }); } catch {}
			if (parentEntry?.type === "compaction") {
				try { writeFileSync(DEBUG_LOG, `GUARD FIRED -> refusing\n`, { flag: "a" }); } catch {}
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

			// TEMP DIAGNOSTIC: log the navigation target
			try { writeFileSync(DEBUG_LOG, `navigating target=${target}\n`, { flag: "a" }); } catch {}
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
