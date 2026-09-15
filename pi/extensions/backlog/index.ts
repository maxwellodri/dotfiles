/**
 * backlog — buffer a prompt that fires only when the agent has *fully*
 * settled, or (when_afk) once you've also been idle for N minutes.
 *
 *   /backlog <prompt>    append to the pending backlog (creates one)
 *   /backlog             cancel it and dump its text into the prompt editor
 *   /when_afk <m> <p>    append to the pending afk prompt and restart its timer
 *   /when_afk            cancel the pending afk prompt (noop if none)
 *
 * A backlog dispatches when its gate passes AND the agent has completely
 * finished (agent_settled — after retries, compaction and queued follow-ups
 * have drained; a turn boundary mid-tool-calls never fires it):
 *   backlog  gate = agent not mid-task: fires at invocation when idle (no
 *            task to await), else at the next full settle
 *   when_afk gate = idle ≥ N minutes via scripts/when_afk (see gates.ts)
 *
 * Backlogs render in the transcript like tool invocations (see
 * ask-user-questions): a `backlog` / `when_afk Nm` row when queued, `+`
 * rows per append, `✓ fired` / `✗ cancelled` when resolved. Rows are custom
 * entries — visible to you, not sent to the model.
 *
 * Purge rules: any message you send cancels the afk backlog (an active user
 * is not AFK) but never a plain backlog — it's gated on the agent, not you.
 * Quitting or /reload disarms timers but the entries persist in the session
 * — reloading or resuming re-arms them. Tree moves (undo, /tree) re-fold the
 * branch the same way: an armed backlog whose entries left the active branch
 * is disarmed; navigating back onto a queued tail re-arms it. Undoing the
 * fired turn itself lands on the ✓ fired entry (the parent of the dispatched
 * message) and re-arms nothing.
 */
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { createBacklogs, renderEntry } from "./core.ts";

export default function (pi: ExtensionAPI) {
	const backlogs = createBacklogs(pi);

	pi.registerCommand("backlog", {
		description: "Buffer a follow-up prompt that fires once the agent finishes (immediately if idle); no args dumps it into the editor",
		handler: async (args: string, ctx: ExtensionContext) => {
			const text = args.trim();
			if (!text) {
				const dumped = backlogs.dump("settled");
				if (dumped !== undefined) ctx.ui.setEditorText(dumped);
				return;
			}
			backlogs.add("settled", text, undefined, ctx);
		},
	});

	pi.registerCommand("when_afk", {
		description: "Queue a prompt to fire once idle ≥ N minutes; no args cancels the pending one",
		handler: async (args: string, ctx: ExtensionContext) => {
			const m = /^(\d+)\s+([\s\S]+)$/.exec(args.trim());
			if (!m) {
				backlogs.settle("afk", "cancelled", "via /when_afk"); // noop when nothing queued
				return;
			}
			backlogs.add("afk", m[2], parseInt(m[1], 10), ctx);
		},
	});

	// An active user is not AFK: any real message cancels the afk backlog.
	// (Extension commands don't fire "input", so /when_afk appends survive.)
	pi.on("input", (event) => {
		if (event.source === "extension") return; // our own dispatch
		backlogs.settle("afk", "cancelled", "user active");
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
