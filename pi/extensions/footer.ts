/**
 * footer.ts — slim footer: pwd/git line, context-window meter, model name,
 * dim right-pinned thinking level. Owns the footer ONLY. No token counts or
 * cost (subscription plan — $ would be fictional; usage is one /glm_rates
 * away); "(auto)" marker unexposed to extensions, left blank.
 */
import type { ExtensionAPI, ReadonlyFooterDataProvider } from "@earendil-works/pi-coding-agent";
import { truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";
import { isAbsolute, relative, resolve, sep } from "node:path";

// ───────────────────────── formatting helpers (mirror pi internals) ─────────

function formatTokens(n: number): string {
	if (n < 1000) return String(n);
	if (n < 10000) return `${(n / 1000).toFixed(1)}k`;
	if (n < 1_000_000) return `${Math.round(n / 1000)}k`;
	if (n < 10_000_000) return `${(n / 1_000_000).toFixed(1)}M`;
	return `${Math.round(n / 1_000_000)}M`;
}

/** Collapse $HOME → ~. Faithful copy of pi's formatCwdForFooter(). */
function formatCwd(cwd: string, home: string | undefined): string {
	if (!home) return cwd;
	const resolvedCwd = resolve(cwd);
	const resolvedHome = resolve(home);
	const rel = relative(resolvedHome, resolvedCwd);
	const inside =
		rel === "" || (rel !== ".." && !rel.startsWith(`..${sep}`) && !isAbsolute(rel));
	if (!inside) return cwd;
	return rel === "" ? "~" : `~${sep}${rel}`;
}

function sanitizeStatusText(text: string): string {
	return text.replace(/[\r\n\t]/g, " ").replace(/ +/g, " ").trim();
}

// ──────────────────────────── the custom footer ────────────────────────────
// Three lines:
//   1. pwd • git branch • session name
//   2. context meter (left) • model [+provider] (right)
//   3. extension statuses (left) • dim thinking level (right)
// Layout/truncation logic mirrors pi's FooterComponent; all state is read
// live from ctx + footerData on each render.

function makeFooter(ctx: any) {
	return (tui: any, theme: any, footerData: ReadonlyFooterDataProvider) => {
		const unsub = footerData.onBranchChange(() => tui.requestRender());

		const render = (width: number): string[] => {
			const model = ctx.model;
			const contextUsage = ctx.getContextUsage();
			const contextWindow = contextUsage?.contextWindow ?? model?.contextWindow ?? 0;
			const contextPercentValue = contextUsage?.percent ?? 0;
			const contextPercent =
				contextUsage?.percent !== null ? contextPercentValue.toFixed(1) : "?";

			// ----- line 1: pwd • git branch • session name -----
			let pwd = formatCwd(
				ctx.sessionManager.getCwd(),
				process.env.HOME || process.env.USERPROFILE,
			);
			const branch = footerData.getGitBranch();
			if (branch) pwd = `${pwd} (${branch})`;
			const sessionName = ctx.sessionManager.getSessionName();
			if (sessionName) pwd = `${pwd} • ${sessionName}`;

			// ----- line 2: context meter (left) • model/provider (right) -----
			const statsParts: string[] = [];

			// "(auto)" omitted: session.autoCompactionEnabled is not exposed to extensions.
			const autoIndicator = "";
			const contextPercentDisplay =
				contextPercent === "?"
					? `?/${formatTokens(contextWindow)}${autoIndicator}`
					: `${contextPercent}%/${formatTokens(contextWindow)}${autoIndicator}`;
			let contextPercentStr: string;
			if (contextPercentValue > 90) contextPercentStr = theme.fg("error", contextPercentDisplay);
			else if (contextPercentValue > 70)
				contextPercentStr = theme.fg("warning", contextPercentDisplay);
			else contextPercentStr = contextPercentDisplay;
			statsParts.push(contextPercentStr);

			if (process.env.PI_EXPERIMENTAL === "1") {
				statsParts.push(`${theme.fg("dim", "•")} ${theme.bold(theme.fg("warning", "xp"))}`);
			}
			let statsLeft = statsParts.join(" ");

			// Right side: model name.
			const modelName = model?.id || "no-model";
			let rightSide = modelName;
			if (footerData.getAvailableProviderCount() > 1 && model) {
				const withProvider = `(${model.provider}) ${modelName}`;
				// keep the provider prefix only if it still fits
				if (visibleWidth(statsLeft) + 2 + visibleWidth(withProvider) <= width) {
					rightSide = withProvider;
				}
			}

			// left/right join with truncation (mirrors pi exactly)
			let statsLeftWidth = visibleWidth(statsLeft);
			if (statsLeftWidth > width) {
				statsLeft = truncateToWidth(statsLeft, width, "...");
				statsLeftWidth = visibleWidth(statsLeft);
			}
			const minPadding = 2;
			const rightSideWidth = visibleWidth(rightSide);
			let statsLine: string;
			if (statsLeftWidth + minPadding + rightSideWidth <= width) {
				const padding = " ".repeat(width - statsLeftWidth - rightSideWidth);
				statsLine = statsLeft + padding + rightSide;
			} else {
				const availableForRight = width - statsLeftWidth - minPadding;
				if (availableForRight > 0) {
					const truncatedRight = truncateToWidth(rightSide, availableForRight, "");
					const padding = " ".repeat(
						Math.max(0, width - statsLeftWidth - visibleWidth(truncatedRight)),
					);
					statsLine = statsLeft + padding + truncatedRight;
				} else {
					statsLine = statsLeft;
				}
			}
			// Dim each half independently: statsLeft may contain coloured spans
			// (context %) whose resets would clear an outer dim wrapper.
			const dimStatsLeft = theme.fg("dim", statsLeft);
			const dimRemainder = theme.fg("dim", statsLine.slice(statsLeft.length));
			const pwdLine = truncateToWidth(theme.fg("dim", pwd), width, theme.fg("dim", "..."));

			// ----- line 3: extension statuses (left) • thinking level (right) -----
			const statuses = footerData.getExtensionStatuses();
			let statusLeft = "";
			if (statuses.size > 0) {
				statusLeft = Array.from(statuses.entries())
					.sort(([a], [b]) => a.localeCompare(b))
					.map(([, text]) => sanitizeStatusText(text))
					.join(" ");
			}
			const thinking = ctx.thinkingLevel
				? theme.fg("dim", String(ctx.thinkingLevel))
				: "";
			const indicatorW = visibleWidth(thinking);
			const leftW = visibleWidth(statusLeft);
			const dimStatusLeft = statusLeft ? theme.fg("dim", statusLeft) : "";
			let statusLine: string;
			if (leftW + indicatorW <= width) {
				statusLine = dimStatusLeft + " ".repeat(Math.max(0, width - leftW - indicatorW)) + thinking;
			} else {
				statusLine = truncateToWidth(dimStatusLeft, Math.max(0, width - indicatorW), "") + thinking;
			}

			return [pwdLine, dimStatsLeft + dimRemainder, statusLine];
		};

		return {
			dispose: () => unsub(),
			invalidate() {
				/* stats/context/model are read live each render */
			},
			render,
		};
	};
}

export default function (pi: ExtensionAPI) {
	pi.on("session_start", (_event, ctx) => {
		ctx.ui.setFooter(makeFooter(ctx));
	});
}
