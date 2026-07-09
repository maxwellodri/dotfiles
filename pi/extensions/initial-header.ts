/**
 * initial-header.ts — replace pi's built-in startup header with a minimal,
 * version-only line.
 *
 * pi's built-in header bundles four things into ONE ExpandableText component:
 *   1. the logo/version line   "pi v0.80.3"              <- KEEP
 *   2. keybinding hints        "escape interrupt · …"    <- drop
 *   3. "Press ctrl+o to show full startup help …"        <- drop
 *   4. "Pi can explain its own features …"               <- drop
 *
 * ctx.ui.setHeader() swaps that whole header component for a custom one, so we
 * render only line 1. The [Skills]/[Extensions]/[Themes] listing lives in a
 * SEPARATE container (loadedResourcesContainer) and is NOT touched by this, so
 * it keeps showing — provided `quietStartup` stays false. That flag gates BOTH
 * the header and the loaded-resources listing; flipping it would hide
 * skills/extensions/themes too. Only ONE custom header may render; this
 * extension claims it (no other extension here calls setHeader).
 *
 * The version line is reproduced byte-for-byte from pi's own header:
 *   theme.bold(theme.fg("accent", APP_NAME)) + theme.fg("dim", ` v${VERSION}`)
 * plus the single leading space the built-in Text applies via paddingX=1.
 *
 * Load: auto-discovered from pi/extensions/*.ts (= ~/.pi/agent/extensions);
 * `/reload` after edits.
 */
import type { ExtensionAPI, Theme } from "@earendil-works/pi-coding-agent";
import { VERSION } from "@earendil-works/pi-coding-agent";

export default function (pi: ExtensionAPI) {
	pi.on("session_start", (_event, ctx) => {
		if (ctx.mode !== "tui") return;

		ctx.ui.setHeader((_tui: unknown, theme: Theme) => {
			const render = (_width: number): string[] => {
				// Leading space mirrors the built-in header's paddingX=1 left margin.
				const logo =
					" " +
					theme.bold(theme.fg("accent", "pi")) +
					theme.fg("dim", ` v${VERSION}`);
				return [logo];
			};

			return {
				render,
				invalidate() {
					/* version is static — nothing to invalidate */
				},
			};
		});
	});
}
