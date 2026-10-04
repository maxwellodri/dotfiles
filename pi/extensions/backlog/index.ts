/**
 * backlog — buffer a prompt that fires only when the agent has FULLY
 * settled (agent_settled: retries, compaction, queued continuations drained),
 * or with when_afk once you've also been idle ≥ N minutes.
 *   /backlog [m] <p>    queue; a leading minute count adds a wall-clock
 *                       countdown in front of the settle gate
 *   /when_afk <m> <p>   queue behind the idle gate
 *   bare either         cancel + dump the armed queue into the editor
 * One slot, one gate kind at a time. Any user message cancels an afk queue
 * (an active user is not AFK), never a settled one. Entries persist in the
 * session — reload/resume re-arms; tree moves disarm queues that left the
 * active branch, and navigating back re-arms them.
 */
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { createBacklogs, renderEntry } from "./core.ts";

export default function (pi: ExtensionAPI) {
	const backlogs = createBacklogs(pi);

	pi.registerCommand("backlog", {
		description: "Buffer a follow-up prompt that fires once the agent finishes (immediately if idle); an optional leading minute count delays dispatch by that long; no args dumps the queued prompt into the editor",
		handler: async (args: string, ctx: ExtensionContext) => {
			const text = args.trim();
			if (!text || /^\d+$/.test(text)) return backlogs.dumpToEditor(ctx);
			const m = /^(?:(\d+)\s+)?([\s\S]+)$/.exec(text)!;
			const minutes = m[1] ? parseInt(m[1], 10) : 0;
			backlogs.add("settled", m[2], minutes > 0 ? minutes : undefined, ctx);
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
