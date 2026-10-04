/**
 * turn-timestamps.ts — stamp wall-clock turn ends into the transcript
 * (display-only; timestamps taken from the branch's newest session entry).
 * /timestamps toggles; hidden by default. Hide is instant (components drop
 * to zero height); show needs ctx.reload() — dropped entries must be
 * re-added. Choice survives /reload via PI_TIMESTAMPS_VISIBLE.
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
