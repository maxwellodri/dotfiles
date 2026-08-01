/**
 * turn-timestamps.ts — stamp the wall-clock time each settled run completes
 * into the chat transcript (display-only; never sent to the LLM).
 *
 * Always recorded, hidden by default. `/timestamps` toggles whether the stamp
 * *text* is shown — retroactively, for every recorded stamp in the session.
 *
 *   /timestamps          toggle stamp text visibility (show / hide), all stamps
 *
 * How it works (and why `/timestamps` reloads):
 *  • Every `agent_settled` appends a stamp entry to the session unconditionally
 *    (always recorded), so the data is always there even while hidden.
 *  • The entry renderer returns the stamp text when visible, or `undefined`
 *    when hidden. Returning `undefined` makes pi drop the entry from the chat
 *    at add-time (zero lines — no blank-line leak; pi's CustomEntryComponent
 *    otherwise reserves a Spacer(1) per entry that no render cycle collapses).
 *  • Toggling visibility therefore requires re-evaluating every entry's
 *    renderer, i.e. a full transcript rebuild. The only extension-reachable
 *    path to that is `ctx.reload()` (reload -> session_start -> transcript
 *    rebuild), so `/timestamps` flips the flag and reloads. Cost: a quick
 *    reload (same as typing /reload) on each toggle — fine for an occasional
 *    "let me see the times" flip.
 *  • The visibility flag is kept in `PI_TIMESTAMPS_VISIBLE` (process env),
 *    which survives that in-process reload but resets on a fresh pi start — so
 *    stamps are hidden by default every session until you toggle them on.
 *  • Stamps are `custom` entries → excluded from LLM context. They persist in
 *    the session file across `/reload` and `pi --resume`.
 *
 * Granularity: one stamp per settled run (agent_settled — the agent is truly
 * done with a prompt, after any retries / compaction / queued follow-ups).
 * For a denser per-turn timeline, switch the handler to `turn_end`.
 *
 * Load: auto-discovered from pi/extensions/*.ts (= ~/.pi/agent/extensions);
 * `/reload` after edits.
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Box, Text } from "@earendil-works/pi-tui";

const CUSTOM_TYPE = "turn-timestamp";
const VIS_FLAG = "PI_TIMESTAMPS_VISIBLE";

interface SettledStampData {
	ts: number;
}

/** Compact, locale-independent stamp: ISO 8601 date + HH:MM, e.g. "2025-08-01 00:00". */
function fmtStamp(ts: number): string {
	const d = new Date(ts);
	const p = (n: number) => String(n).padStart(2, "0");
	return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(
		d.getMinutes(),
	)}`;
}

export default function (pi: ExtensionAPI) {
	// Hidden by default each session; `/timestamps` toggles + reloads.
	let visible = process.env[VIS_FLAG] === "1";

	// Render the stamp when visible; return undefined when hidden so pi drops
	// the entry from the chat entirely (zero lines, no blank-line leak).
	pi.registerEntryRenderer<SettledStampData>(CUSTOM_TYPE, (entry, _opts, theme) => {
		if (!visible) return undefined;
		const data = entry.data ?? { ts: Date.now() };
		const stamp = theme.fg("dim", fmtStamp(data.ts));
		const box = new Box(2, 0); // paddingX=2, paddingY=0, no bgFn
		box.addChild(new Text(stamp));
		return box;
	});

	pi.on("agent_settled", (_event, ctx) => {
		// Always record (rendering is toggled separately). Skip scripted runs.
		if (ctx.mode !== "tui") return;
		pi.appendEntry<SettledStampData>(CUSTOM_TYPE, { ts: Date.now() });
	});

	pi.registerCommand("timestamps", {
		description: "Toggle settled-run timestamp text visibility in the transcript",
		handler: async (_args, ctx) => {
			visible = !visible;
			process.env[VIS_FLAG] = visible ? "1" : "0";
			ctx.ui.notify(`Turn timestamps: ${visible ? "shown" : "hidden"}`, "info");
			// Rebuild the transcript so every recorded stamp is re-evaluated
			// against the new visibility. Treat reload as terminal for this handler.
			await ctx.reload();
		},
	});
}
