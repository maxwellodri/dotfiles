/**
 * backlog — buffer a prompt that fires only when the agent has *fully*
 * settled, or (when_afk) once you've also been idle for N minutes.
 *
 *   /backlog <prompt>    append to the pending backlog (creates one)
 *   /backlog             cancel it and dump its text into the prompt editor
 *   /when_afk <m> <p>    append to the pending afk prompt and restart its timer
 *   /when_afk            cancel it and dump its text into the prompt editor
 *
 * One slot, one of two gates — the commands are interchangeable, so bare
 * /backlog and bare /when_afk each dump whichever queue is armed; adding
 * the OTHER kind while one is armed refuses the new text and dumps the
 * armed queue into the editor for re-issuing (see core.ts).
 *   backlog  gate = agent not mid-task: fires at invocation when idle (no
 *            task to await), else at the next full settle
 *   when_afk gate = idle ≥ N minutes via scripts/when_afk (see gates.ts)
 *
 * A backlog dispatches when its gate passes AND the agent has completely
 * finished (agent_settled — after retries, compaction and queued follow-ups
 * have drained; a turn boundary mid-tool-calls never fires it).
 *
 * Purge rules: any message you send cancels an afk-armed queue (an active
 * user is not AFK) but never a settled one — it's gated on the agent, not
 * you. Quitting or /reload disarms timers but the entries persist in the
 * session — reloading or resuming re-arms them. Tree moves (undo, /tree)
 * re-fold the branch the same way: an armed backlog whose entries left the
 * active branch is disarmed; navigating back onto a queued tail re-arms
 * it. Undoing the fired turn itself lands on the ✓ fired entry (the parent
 * of the dispatched message) and re-arms nothing.
 */
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { createBacklogs, renderEntry } from "./core.ts";

export default function (pi: ExtensionAPI) {
	const backlogs = createBacklogs(pi);

	pi.registerCommand("backlog", {
		description: "Buffer a follow-up prompt that fires once the agent finishes (immediately if idle); no args dumps the queued prompt into the editor",
		handler: async (args: string, ctx: ExtensionContext) => {
			const text = args.trim();
			if (!text) return backlogs.dumpToEditor(ctx);
			backlogs.add("settled", text, undefined, ctx);
		},
	});

	pi.registerCommand("when_afk", {
		description: "Queue a prompt to fire once idle ≥ N minutes; no args dumps the queued prompt into the editor",
		handler: async (args: string, ctx: ExtensionContext) => {
			const m = /^(\d+)\s+([\s\S]+)$/.exec(args.trim());
			if (!m) return backlogs.dumpToEditor(ctx);
			backlogs.add("afk", m[2], parseInt(m[1], 10), ctx);
		},
	});

	// An active user is not AFK: any real message cancels an afk-armed queue
	// (a settled one awaits the agent, not you). Extension commands don't
	// fire "input", so /when_afk appends survive.
	pi.on("input", (event, ctx) => {
		if (event.source === "extension") return; // our own dispatch
		backlogs.settle("afk", "cancelled", "user active", ctx);
	});

	pi.on("agent_settled", (_event, ctx) => backlogs.onAgentSettled(ctx));

	pi.on("session_start", (_event, ctx) => {
		pi.registerEntryRenderer("backlog", renderEntry);
		pi.registerEntryRenderer("when_afk", renderEntry); // legacy entries from the old extension
		backlogs.syncWithBranch(ctx); // re-arm backlogs orphaned by quit/crash//reload
	});

	pi.on("session_tree", (_event, ctx) => backlogs.syncWithBranch(ctx));

	pi.on("session_shutdown", () => backlogs.disarmAll()); // keep entries for re-arm
}
