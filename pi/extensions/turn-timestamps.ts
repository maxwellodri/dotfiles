/**
 * turn-timestamps.ts — stamp the wall-clock time each turn ends into the chat
 * transcript (display-only; never sent to the LLM).
 *
 * Always recorded, hidden by default.
 *
 *   /timestamps          toggle stamp text visibility (show / hide), all stamps
 *
 * How it works:
 *  • Every `turn_end` (one LLM response plus its tool calls) appends a stamp
 *    entry carrying the timestamp of the branch's newest session entry (from
 *    `ctx.sessionManager.getBranch()`), so the displayed time is exactly the
 *    time recorded in the session jsonl — the closing assistant message or
 *    toolResult of that round. A reason → toolcall → reason run therefore gets
 *    a stamp after every round, right below the round's tool results. Stamps
 *    recorded before this used the extension's own clock (epoch ms) and are
 *    still rendered correctly.
 *  • Hidden stamps: the renderer returns `undefined`, and pi drops the entry
 *    from the chat AT ADD TIME — `addCustomEntryToChat` discards components
 *    with no content, so hidden stamps have no component in the chat tree at
 *    all (zero lines). A rendered-but-blank component can't be zero-height
 *    either: CustomEntryComponent reserves a Spacer(1) for any non-undefined
 *    renderer result.
 *  • Consequence, by direction:
 *      hide  → no rebuild needed. Shown stamps have live components; bouncing
 *              the global tools-expanded state (`setToolsExpanded(!x)` twice)
 *              walks the chat container re-running every expandable renderer,
 *              and a `undefined` return clears the component to zero height.
 *              Instant; net expansion state unchanged (a transient "Tool
 *              output: …" status line flashes — cosmetic, unavoidable).
 *      show  → needs a transcript rebuild, because dropped entries must be
 *              re-added. `ctx.reload()` is the only extension-reachable one
 *              (session.reload → rebuildChatFromMessages). Same cost as the
 *              pre-rework extension, now only paid in one direction.
 *  • `visible` is mirrored into `PI_TIMESTAMPS_VISIBLE` so the choice survives
 *    `/reload` (the show-path reload re-imports the extension); fresh pi
 *    starts still default to hidden.
 *
 * Granularity: one stamp per turn. For one stamp per settled run instead
 * (retries, compaction, queued follow-ups all collapsed), switch the handler
 * to `agent_settled`.
 *
 * Load: auto-discovered from pi/extensions/*.ts (= ~/.pi/agent/extensions);
 * `/reload` after edits.
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Box, Text } from "@earendil-works/pi-tui";

const CUSTOM_TYPE = "turn-timestamp";
const VIS_FLAG = "PI_TIMESTAMPS_VISIBLE";

interface TurnStampData {
	/** ISO timestamp of the turn's closing entry (session-file time). */
	ts: string;
}

/** Compact, locale-independent stamp: ISO 8601 date + HH:MM, e.g. "2025-08-01 00:00". */
function fmtStamp(ts: string | number): string {
	const d = new Date(ts);
	if (Number.isNaN(d.getTime())) return "";
	const p = (n: number) => String(n).padStart(2, "0");
	return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}`;
}

export default function (pi: ExtensionAPI) {
	// Hidden by default each session; `/timestamps` toggles + rebuilds stamps.
	let visible = process.env[VIS_FLAG] === "1";

	// Render the stamp when visible; return undefined when hidden so pi drops
	// the entry from the chat entirely (zero lines, no blank-line leak).
	pi.registerEntryRenderer<TurnStampData>(CUSTOM_TYPE, (entry, _opts, theme) => {
		if (!visible) return undefined;
		// Pre-rework stamps stored epoch ms; both shapes render.
		const stamp = theme.fg("dim", fmtStamp(entry.data?.ts ?? Date.now()));
		const box = new Box(2, 0); // paddingX=2, paddingY=0, no bgFn
		box.addChild(new Text(stamp));
		return box;
	});

	pi.on("turn_end", (_event, ctx) => {
		// Skip scripted runs. A session replacement (resume/-c, /new, fork) can
		// leave this instance stale but still bound for events — touching ctx
		// throws. Skip; the rebound instance's own handler records the stamp.
		try {
			if (ctx.mode !== "tui") return;
		} catch {
			return;
		}
		const branch = ctx.sessionManager.getBranch();
		const ts = branch.length > 0 ? branch[branch.length - 1].timestamp : new Date().toISOString();
		pi.appendEntry<TurnStampData>(CUSTOM_TYPE, { ts });
	});

	pi.registerCommand("timestamps", {
		description: "Toggle per-turn timestamp text visibility in the transcript",
		handler: async (_args, ctx) => {
			visible = !visible;
			process.env[VIS_FLAG] = visible ? "1" : "0";
			if (visible) {
				// Dropped entries must be re-added — only a transcript rebuild can.
				// Reload re-imports this extension (env flag carries the choice);
				// treat reload as terminal for this handler.
				ctx.ui.notify("Turn timestamps: shown (reloading transcript)", "info");
				await ctx.reload();
				return;
			}
			// Hide: shown stamps have live components — rebuild them in place by
			// bouncing the global tools-expanded state through both values.
			if (typeof ctx.ui.setToolsExpanded === "function" && typeof ctx.ui.getToolsExpanded === "function") {
				const toolsExpanded = ctx.ui.getToolsExpanded();
				ctx.ui.setToolsExpanded(!toolsExpanded);
				ctx.ui.setToolsExpanded(toolsExpanded);
			}
			ctx.ui.notify("Turn timestamps: hidden", "info");
		},
	});
}
