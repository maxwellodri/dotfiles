/**
 * yield — one extension for everything that eventually becomes a prompt:
 *   ask_user_question (sync blocking + async board-parked)   questions.ts
 *   async question store, summon (C-x q / /questions)        askq.ts
 *   backlog / when_afk (moved from the backlog extension)    backlog/
 *   board + shared UI lock + delivery dispatcher             board.ts
 *
 * WHY ONE DIR: pi loads extensions with the module cache disabled, so a
 * plain import from another extension dir would give each importer its own
 * copy of every module — separate lock, board, and stores. Everything
 * stateful lives in this directory, one module instance. backlog's legacy
 * "when_afk" entries still fold (kind afk), so old sessions re-arm.
 *
 * HARD RULE (see board.ts): every ctx.ui.custom()/editor() caller must hold
 * withUILock — the standard prompt and sync questions share one input slot
 * (mutually exclusive, swapped and restored by pi); the async answer
 * session is opt-in and, when summoned, takes input precedence over
 * whatever occupies that slot, queueing behind any popup already open.
 */
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { createBacklogs, renderEntry } from "./backlog/core.ts";
import { createAskq } from "./askq.ts";
import { createBoard, noteExtensionInput, setCompacting } from "./board.ts";
import { registerAskUserQuestionTool } from "./questions.ts";

export default function (pi: ExtensionAPI) {
	const board = createBoard();
	const askq = createAskq(pi, board);
	const backlogs = createBacklogs(pi, board);

	registerAskUserQuestionTool(pi, { askAsync: askq.askAsync });

	// ── commands ────────────────────────────────────────────────────────
	pi.registerCommand("backlog", {
		description:
			"Buffer a follow-up prompt that fires once the agent finishes (immediately if idle); an optional leading minute count delays dispatch by that long; no args dumps the queued prompt into the editor",
		handler: async (args: string, ctx: ExtensionContext) => {
			const text = args.trim();
			if (!text || /^\d+$/.test(text)) return backlogs.dumpToEditor(ctx);
			const m = /^(?:(\d+)\s+)?([\s\S]+)$/.exec(text)!;
			const minutes = m[1] ? parseInt(m[1], 10) : 0;
			backlogs.add("settled", m[2], minutes > 0 ? minutes : undefined, ctx);
		},
	});

	pi.registerCommand("when_afk", {
		description: "Queue a prompt to fire once idle ≥ N minutes (default 30); no args dumps the queued prompt into the editor",
		handler: async (args: string, ctx: ExtensionContext) => {
			const text = args.trim();
			if (!text) return backlogs.dumpToEditor(ctx);
			const m = /^(?:(\d+)\s+)?([\s\S]+)$/.exec(text)!;
			backlogs.add("afk", m[2], m[1] ? parseInt(m[1], 10) : 30, ctx);
		},
	});

	pi.registerCommand("questions", {
		description: "Answer pending async questions (the session becomes the current input)",
		handler: async (_args: string, ctx: ExtensionContext) => askq.summon(ctx),
	});

	// ── events ──────────────────────────────────────────────────────────

	// An active user is not AFK: any real message cancels an afk-armed queue
	// (a settled one awaits the agent, not you). Extension commands don't
	// fire "input", so /when_afk appends survive. Extension-sourced input is
	// also the delivery echo yieldPrompt waits on (see board.ts).
	pi.on("input", (event, ctx) => {
		if (event.source === "extension") {
			noteExtensionInput(event.text);
			return;
		}
		backlogs.settle("afk", "cancelled", "user active", ctx);
	});

	pi.on("agent_settled", (event, ctx) => {
		backlogs.onAgentSettled(ctx);
		askq.onAgentSettled(ctx);
	});

	pi.on("session_start", (_event, ctx) => {
		pi.registerEntryRenderer("backlog", renderEntry);
		pi.registerEntryRenderer("when_afk", renderEntry); // legacy entries from the old extension
		backlogs.syncWithBranch(ctx); // re-arm backlogs orphaned by quit/crash/reload
		askq.onSessionStart(ctx);
	});

	pi.on("session_tree", (_event, ctx) => {
		backlogs.syncWithBranch(ctx);
		askq.onSessionTree(ctx);
	});

	// Delivery gate: submitting during compaction loses the message inside
	// pi, so yieldPrompt holds while a compaction runs.
	pi.on("session_before_compact", () => setCompacting(true));
	pi.on("session_compact", () => setCompacting(false));
	pi.on("session_compact_failed", () => setCompacting(false));

	pi.on("session_shutdown", () => {
		askq.onSessionShutdown();
		backlogs.disarmAll(); // keep entries for re-arm
	});
}
