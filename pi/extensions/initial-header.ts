/**
 * initial-header.ts — replace pi's startup header with the version line
 * only. setHeader swaps the whole built-in component (logo + hints + help
 * lines); the [Skills]/[Extensions]/[Themes] listing is a separate container
 * and survives — keep `quietStartup` false or it hides too.
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
