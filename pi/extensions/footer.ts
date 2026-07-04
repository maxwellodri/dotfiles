/**
 * footer.ts — custom footer for pi that reproduces the built-in one and pins
 * a dim leader-key indicator (N / ?) to the bottom-right corner.
 *
 * This extension owns the footer ONLY. The indicator state arrives over pi's
 * shared event bus: leader-editor.ts emits `leader-editor:state` (boolean)
 * when its C-x prefix arms/disarms. The two extensions are fully decoupled —
 * no imports, no shared module (pi loads extensions with jiti
 * `moduleCache:false`, so a plain cross-import would not share state anyway).
 *
 * ── THINKING LEVEL IS INTENTIONALLY OMITTED ───────────────────────────────
 * The current thinking level lives in `session.state.thinkingLevel`, which is
 * NOT exposed on the extension context. Only `ExtensionCommandContext`
 * (slash-command handlers) has `getThinkingLevel()`, unreachable from a
 * render-time closure. The `thinking_level_select` event carries the level
 * but fires only on *change*, so caching it yields a wrong cold-start value,
 * which we refuse to show. The model name is therefore shown alone, with no
 * "• thinking off/low/…" suffix. If a read API ever ships (see pi issues
 * #509, #3831, #4792), add a `thinkingLevel` source and render it next to
 * `modelName` exactly like pi's own footer does.
 *
 * ── OTHER FAITHFULNESS GAPS (also unexposed to extensions) ─────────────────
 *  • "(auto)" auto-compaction marker — needs `session.autoCompactionEnabled`
 *    (pi #3831). Left as `""`; add back if exposed.
 *  Everything else (pwd, git, session name, token/cache/cost stats, context %,
 *  model name, provider prefix, experimental "xp", extension statuses) reads
 *  the same live sources pi's own footer uses, via ctx + footerData.
 *
 * Load: auto-discovered from pi/extensions/*.ts (= ~/.pi/agent/extensions);
 * `/reload` after edits. Only ONE custom footer may render.
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import type { AssistantMessage } from "@earendil-works/pi-ai";
import { truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";
import { isAbsolute, relative, resolve, sep } from "node:path";

/** Event-bus channel published by leader-editor.ts. */
const STATE_CHANNEL = "leader-editor:state";

/** Indicator state, cached from the event bus. Defaults to idle ("N"). */
let leaderArmed = false;
/** Unsubscribe handle for the current session's state listener (re-subscribed on reload). */
let unsubState: (() => void) | undefined;

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
// Reproduces pi's FooterComponent.render() line-for-line, swapping `session.*`
// for the live `ctx`/`footerData` equivalents, omitting the thinking-level
// widget (see header), and appending a 3rd line whose bottom-right cell is the
// dim N/? leader indicator.

function makeFooter(ctx: any) {
	return (tui: any, theme: any, footerData: any) => {
		const unsub = footerData.onBranchChange(() => tui.requestRender());

		const render = (width: number): string[] => {
			// ----- cumulative usage from ALL session entries -----
			let totalInput = 0,
				totalOutput = 0,
				totalCacheRead = 0,
				totalCacheWrite = 0,
				totalCost = 0;
			let latestCacheHitRate: number | undefined;
			for (const entry of ctx.sessionManager.getEntries()) {
				if (entry.type !== "message") continue;
				const msg = (entry as { message: AssistantMessage }).message;
				if (msg.role !== "assistant") continue;
				const u = msg.usage;
				totalInput += u.input;
				totalOutput += u.output;
				totalCacheRead += u.cacheRead;
				totalCacheWrite += u.cacheWrite;
				totalCost += u.cost.total;
				const promptTokens = u.input + u.cacheRead + u.cacheWrite;
				latestCacheHitRate =
					promptTokens > 0 ? (u.cacheRead / promptTokens) * 100 : undefined;
			}

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

			// ----- line 2: stats (left) • model/provider (right) -----
			const statsParts: string[] = [];
			if (totalInput) statsParts.push(`↑${formatTokens(totalInput)}`);
			if (totalOutput) statsParts.push(`↓${formatTokens(totalOutput)}`);
			if (totalCacheRead) statsParts.push(`R${formatTokens(totalCacheRead)}`);
			if (totalCacheWrite) statsParts.push(`W${formatTokens(totalCacheWrite)}`);
			if ((totalCacheRead > 0 || totalCacheWrite > 0) && latestCacheHitRate !== undefined) {
				statsParts.push(`CH${latestCacheHitRate.toFixed(1)}%`);
			}
			const usingSubscription = model ? ctx.modelRegistry.isUsingOAuth(model) : false;
			if (totalCost || usingSubscription) {
				statsParts.push(`$${totalCost.toFixed(3)}${usingSubscription ? " (sub)" : ""}`);
			}

			// "(auto)" omitted: session.autoCompactionEnabled is not exposed (pi #3831).
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

			// Right side: model name. Thinking level OMITTED here (see header).
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

			// ----- line 3: extension statuses (left) • leader indicator (right) -----
			const statuses = footerData.getExtensionStatuses();
			let statusLeft = "";
			if (statuses.size > 0) {
				statusLeft = Array.from(statuses.entries())
					.sort(([a], [b]) => a.localeCompare(b))
					.map(([, text]: [string, string]) => sanitizeStatusText(text))
					.join(" ");
			}
			const indicator = theme.fg("dim", leaderArmed ? "?" : "N");
			const indicatorW = visibleWidth(indicator); // 1
			const leftW = visibleWidth(statusLeft);
			let statusLine: string;
			if (leftW + indicatorW <= width) {
				statusLine = statusLeft + " ".repeat(Math.max(0, width - leftW - indicatorW)) + indicator;
			} else {
				statusLine = truncateToWidth(statusLeft, Math.max(0, width - indicatorW), "") + indicator;
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
		// Re-subscribe each session/reload to avoid stacking listeners.
		unsubState?.();
		unsubState = pi.events.on(STATE_CHANNEL, (armed) => {
			leaderArmed = armed === true;
		});

		ctx.ui.setFooter(makeFooter(ctx));
	});
}
