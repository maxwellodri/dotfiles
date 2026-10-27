/**
 * board.ts — the yield framework's shared core, one module instance for the
 * whole extension (pi disables the module cache per extension, so this file
 * is why askq/backlog/questions must live in ONE extension dir).
 *
 * Three concerns:
 *  - withUILock: the process-wide popup mutex (globalThis __piSharedUiLock,
 *    same slot the former ask-user-questions extension used). HARD RULE:
 *    every ctx.ui.custom()/editor() caller must hold it — pi supports one
 *    active custom component and this is the only cross-extension
 *    serialization point.
 *  - yieldPrompt: the single delivery path for every "eventually a prompt"
 *    source (backlog fires, async answers): sendUserMessage with followUp
 *    while a run is active, a fresh turn when idle. sendUserMessage never
 *    throws at the call site (pi funnels failures into error events), so
 *    delivery correctness is a pre-condition gate: hold while a compaction
 *    is in progress (submitting during compaction throws inside pi and the
 *    message is lost) and only resolve the caller once sent.
 *  - createBoard: one setWidget ("yield", aboveEditor) rendering one row
 *    block per registered source — backlog's slot, askq's pending questions.
 *    Sources call setRows(key, factory|undefined, ctx) exactly as they used
 *    to call ctx.ui.setWidget.
 */
import type { ExtensionContext } from "@earendil-works/pi-coding-agent";
import { Text } from "@earendil-works/pi-tui";

// ─────────────────────── shared UI lock ───────────────────────

const SHARED_UI_LOCK_KEY = "__piSharedUiLock";

function getSharedUiLock() {
	const g = globalThis as any;
	if (!g[SHARED_UI_LOCK_KEY]) {
		let chain: Promise<void> = Promise.resolve();
		g[SHARED_UI_LOCK_KEY] = {
			withLock<T>(fn: () => T | Promise<T>): Promise<T> {
				const prev = chain;
				let release: () => void;
				chain = new Promise<void>((r) => {
					release = r;
				});
				return prev.then(fn).finally(() => release!());
			},
		};
	}
	return g[SHARED_UI_LOCK_KEY] as { withLock<T>(fn: () => T | Promise<T>): Promise<T> };
}

export function withUILock<T>(fn: () => Promise<T>): Promise<T> {
	return getSharedUiLock().withLock(fn);
}

// ─────────────────────── yield dispatcher ───────────────────────

/** True while a compaction is running; index.ts tracks the events. */
let compacting = false;

export function setCompacting(state: boolean): void {
	compacting = state;
}

/** Last extension-sourced input pi dispatched (set by index.ts's persistent
 *  input handler). Registering per-send pi.on("input") listeners from the
 *  delivery path wedges pi's input dispatch — one persistent listener only.
 *  Sequence-numbered: the handler runs INSIDE the sendUserMessage call stack,
 *  so wall-clock stamps can't order send vs echo — a monotonic counter can,
 *  and it also rejects stale echoes (same text sent earlier, identical text
 *  from another extension — the latter stays a theoretical false positive). */
let inputSeq = 0;
let lastExtensionInput: { text: string; seq: number } | null = null;

export function noteExtensionInput(text: string): void {
	lastExtensionInput = { text, seq: ++inputSeq };
}

function currentInputSeq(): number {
	return inputSeq;
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

/** notify() on a stale (post-/reload) context throws — never let a notice kill the process. */
export function safeNotify(ctx: ExtensionContext, message: string, type: "info" | "warning" = "info"): void {
	try {
		ctx.ui.notify?.(message, type);
	} catch {
		// stale runtime after reload/session switch
	}
}

/**
 * Deliver a prompt into the conversation: followUp when a run is active, a
 * fresh turn when idle. sendUserMessage is fire-and-forget at the extension
 * boundary (pi funnels failures into error events, never into a rejection
 * here), so delivery correctness is a pre-condition gate plus an echo check:
 * hold while a compaction runs (a submit during compaction is lost inside
 * pi), and correlate the "input" event (source "extension", matching text)
 * as the only observable confirmation the message entered the session.
 * Capped waits: an orphaned loop (stale runtime after /reload never clears
 * the compaction flag) must not spin forever. Resolves false when the send
 * was refused — callers keep their armed/pending state and retry later.
 */
export async function yieldPrompt(pi: any, ctx: ExtensionContext, text: string): Promise<boolean> {
	for (let waited = 0; compacting && waited < 60; waited++) {
		if (waited === 15) safeNotify(ctx, "answer delivery is waiting on compaction…");
		await sleep(1000);
	}
	const before = currentInputSeq();
	try {
		if (ctx.isIdle()) pi.sendUserMessage(text);
		else pi.sendUserMessage(text, { deliverAs: "followUp" });
	} catch {
		return false;
	}
	// Honest result: without a fresh echo the send may have been swallowed
	// (e.g. the cap expired mid-compaction) — report failure so callers keep
	// their armed/pending state and retry rather than resolve on a loss.
	const echoed = () => lastExtensionInput?.text === text && lastExtensionInput.seq > before;
	for (let i = 0; !echoed() && i < 3; i++) await sleep(1000);
	return echoed();
}

// ─────────────────────── status board ───────────────────────

/** One styled row block per source; undefined = nothing to show. */
export type BoardRows = (theme: any) => string[];

export interface Board {
	/** Register/replace/clear a source's rows and repaint the widget. */
	setRows(key: string, rows: BoardRows | undefined, ctx: ExtensionContext): void;
}

export function createBoard(): Board {
	const sources = new Map<string, BoardRows>();

	const repaint = (ctx: ExtensionContext) => {
		if (!ctx.hasUI) return;
		const active = [...sources.entries()].filter(([, rows]) => rows);
		ctx.ui.setWidget(
			"yield",
			active.length
				? (_tui: unknown, theme: any) =>
						// try/catch INSIDE the component: a throwing factory would
						// crash pi-tui's render pass outside any extension frame.
						new Text(
							active
								.map(([key, rows]) => {
									try {
										return rows(theme).join("\n");
									} catch {
										return key;
									}
								})
								.filter(Boolean)
								.join("\n"),
							0,
							0,
						)
				: undefined,
		);
	};

	return {
		setRows(key, rows, ctx) {
			if (rows) sources.set(key, rows);
			else sources.delete(key);
			repaint(ctx);
		},
	};
}
