/**
 * zai-plan-limit.ts — wait out GLM coding-plan quota resets instead of
 * burning exponential-backoff retries against a wall. Z.ai plan-limit 429s
 * ("code":"1308", "Usage limit reached for 5 hour. Your limit will reset at
 * 2026-10-04 20:07:14") carry the reset wall-clock; the server renders it in
 * UTC+8 (MYT/CST — confirmed against session transcripts: retries kept
 * failing until 52s before the UTC+8 reading, and never after). The wrapper
 * sleeps until the reset (abortable, status-line countdown), then re-issues
 * the request inside the provider stream so the agent never sees the error.
 * A 429 precedes any content events ("start" is only emitted after the
 * request is admitted), so a retried attempt is indistinguishable from the
 * first. Registered as a streamSimple override on provider "zai" with
 * api "openai-completions"; built-in models and ZAI_API_KEY env auth are
 * preserved. Unparseable/implausible reset times fall through to the error
 * (and thus normal agent retry).
 */
import {
	createAssistantMessageEventStream,
	openAICompletionsApi,
	type Api,
	type AssistantMessage,
	type AssistantMessageEvent,
	type AssistantMessageEventStream,
	type Model,
	type SimpleStreamOptions,
	type TranscriptContext,
} from "@earendil-works/pi-ai";
import type { ExtensionAPI, ExtensionUIContext } from "@earendil-works/pi-coding-agent";

const RESET_PATTERN = /usage limit reached[^\n"]*?reset at (\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})/i;
const RESET_TZ_SUFFIX = "+08:00";
/** Window is 5h; anything past this means the parse (tz/format) is wrong — don't wait. */
const MAX_WAIT_MS = 5 * 3_600_000 + 10 * 60_000;
const MIN_WAIT_MS = 2_000;
const PAD_MS = 2_000;
const MAX_ATTEMPTS = 12;
const STATUS_KEY = "zai-plan-limit";
const TICK_MS = 30_000;

let ui: ExtensionUIContext | undefined;

function zeroCost() {
	return { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 };
}

function zeroUsage() {
	return { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, totalTokens: 0, cost: zeroCost() };
}

function abortedMessage(model: Model<Api>): AssistantMessage {
	return {
		role: "assistant",
		content: [],
		api: model.api,
		provider: model.provider,
		model: model.id,
		usage: zeroUsage(),
		stopReason: "aborted",
		errorMessage: "Request was aborted",
		timestamp: Date.now(),
	};
}

/** Ms to sleep until the plan limit resets, or undefined when untrustworthy. */
function planLimitWaitMs(errorMessage: string | undefined): number | undefined {
	if (!errorMessage) return undefined;
	const match = RESET_PATTERN.exec(errorMessage);
	if (!match) return undefined;
	const resetMs = Date.parse(`${match[1]}${RESET_TZ_SUFFIX}`);
	if (!Number.isFinite(resetMs)) return undefined;
	const waitMs = resetMs + PAD_MS - Date.now();
	if (waitMs > MAX_WAIT_MS) return undefined;
	return Math.max(waitMs, MIN_WAIT_MS);
}

function formatDuration(ms: number): string {
	const totalSec = Math.max(0, Math.round(ms / 1000));
	const h = Math.floor(totalSec / 3600);
	const m = Math.floor((totalSec % 3600) / 60);
	if (h > 0) return `${h}h ${m}m`;
	if (m > 0) return `${m}m`;
	return `${totalSec}s`;
}

function formatLocalTime(ms: number): string {
	return new Date(ms).toLocaleTimeString(undefined, { hour: "2-digit", minute: "2-digit" });
}

/** Resolves false when the signal aborts before the deadline. */
async function sleepAbortably(ms: number, signal: AbortSignal | undefined): Promise<boolean> {
	if (signal?.aborted) return false;
	return new Promise((resolve) => {
		const timer = setTimeout(() => {
			signal?.removeEventListener("abort", onAbort);
			resolve(true);
		}, ms);
		const onAbort = () => {
			clearTimeout(timer);
			resolve(false);
		};
		signal?.addEventListener("abort", onAbort, { once: true });
	});
}

async function waitOutReset(waitMs: number, signal: AbortSignal | undefined): Promise<boolean> {
	const deadline = Date.now() + waitMs;
	const setStatus = (text: string | undefined) => {
		try {
			ui?.setStatus(STATUS_KEY, text);
		} catch {
			// status surface may be gone (mode switch); waiting continues regardless
		}
	};
	try {
		for (;;) {
			const remaining = deadline - Date.now();
			if (remaining <= 0) return true;
			setStatus(`GLM plan limit — waiting ${formatDuration(remaining)} (resets ~${formatLocalTime(deadline)})`);
			if (!(await sleepAbortably(Math.min(TICK_MS, remaining), signal))) return false;
		}
	} finally {
		setStatus(undefined);
	}
}

function streamZaiWithPlanWait(
	model: Model<Api>,
	context: TranscriptContext,
	options?: SimpleStreamOptions,
): AssistantMessageEventStream {
	const outer = createAssistantMessageEventStream();
	(async () => {
		for (let attempt = 1; ; attempt++) {
			let forwardedAny = false;
			let terminal = false;
			try {
				// May throw synchronously (e.g. missing auth), hence inside the try.
				const inner = openAICompletionsApi().streamSimple(
					model as Model<"openai-completions">,
					context,
					options,
				);
				for await (const event of inner) {
					if (!forwardedAny && !terminal && event.type === "error" && attempt < MAX_ATTEMPTS) {
						const waitMs = planLimitWaitMs(event.error.errorMessage);
						if (waitMs !== undefined) {
							if (!(await waitOutReset(waitMs, options?.signal))) {
								outer.push({ type: "error", reason: "aborted", error: abortedMessage(model) });
								outer.end();
								return;
							}
							break; // fresh attempt
						}
					}
					outer.push(event);
					forwardedAny = true;
					if (event.type === "done" || event.type === "error") {
						terminal = true;
						outer.end();
						return;
					}
				}
				if (forwardedAny && !terminal) {
					// Stream contract violation upstream; surface it (retryable text).
					outer.push({
						type: "error",
						reason: "error",
						error: {
							...abortedMessage(model),
							stopReason: "error",
							errorMessage: "zai stream ended without a terminal event",
						},
					});
					outer.end();
					return;
				}
			} catch (error) {
				outer.push({
					type: "error",
					reason: "error",
					error: {
						...abortedMessage(model),
						stopReason: "error",
						errorMessage: error instanceof Error ? error.message : String(error),
					},
				});
				outer.end();
				return;
			}
		}
	})();
	return outer;
}

export default function (pi: ExtensionAPI) {
	// ctx (not the event) carries the UI surface; captured for status updates
	// during long waits, refreshed on /reload.
	pi.on("session_start", (_event, ctx) => {
		ui = ctx.hasUI ? ctx.ui : undefined;
	});

	pi.registerProvider("zai", {
		api: "openai-completions",
		streamSimple: (model, context, options) => streamZaiWithPlanWait(model, context, options),
	});
}
