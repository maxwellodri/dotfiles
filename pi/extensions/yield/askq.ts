/**
 * askq.ts — the async half of ask_user_question. Pending questions live
 * here, event-sourced as "askq" entries (queued → draft → resolved) and
 * folded from the active branch on session_start + session_tree (the
 * backlog pattern; tree moves disarm questions that left the branch).
 *
 * Flow: the tool (questions.ts) calls askAsync() → one entry per spec
 * (additional_questions fan out to independent entries), board rows, herald
 * arrival ping, immediate "accepted" result. The user answers on their
 * schedule: C-x q (leader registry) or /questions summon the session, which
 * becomes the current input under the shared UI lock — one question per
 * popup (prefilled with the saved draft), each submit expanded
 * ($snippets/@path, same as sync) and delivered via board.ts yieldPrompt;
 * the resolved entry is appended only AFTER successful delivery. Esc closes
 * the session keeping drafts (close-keep: async questions are independent
 * entries, there is no batch to abort) — nothing is ever injected on close.
 *
 * agent_settled with questions still pending pings via herald (threshold
 * gate: the user was away through a whole turn). Arrival pings bypass the
 * silence gate (thresholdMs 0) with a per-question key so they always land.
 */
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { Text } from "@earendil-works/pi-tui";
import { getLeaderRegistry } from "../leader-key.ts";
import { getHerald } from "../herald.ts";
import { createBoard, safeNotify, withUILock, yieldPrompt, type Board } from "./board.ts";
import {
	askMultiChoice,
	expandAnswerText,
	type AskAnswer,
	type AskOption,
	type QuestionSpec,
} from "./questions.ts";

interface Pending {
	qid: string;
	spec: QuestionSpec;
	draft: string;
}

/** "askq" entry data; queued carries the full spec, draft the Custom text, resolved the answers. */
export interface AskqEntryData {
	qid: string;
	state: "queued" | "draft" | "resolved";
	kind?: "answered";
	question?: string;
	context?: string;
	options?: AskOption[];
	draft?: string;
	answers?: string[];
	at: number;
}

const textPart = (text: string) => ({ type: "text" as const, text });
/** Fold the active branch into the pending set: queued upserts, draft updates, resolved removes. */
export function foldAskq(branch: readonly any[]): Map<string, Pending> {
	const pending = new Map<string, Pending>();
	for (const entry of branch) {
		if (entry.type !== "custom" || entry.customType !== "askq") continue;
		const d = entry.data as AskqEntryData;
		if (d.state === "queued") {
			pending.set(d.qid, {
				qid: d.qid,
				spec: { question: d.question ?? "", context: d.context, options: d.options ?? [] },
				draft: "",
			});
		} else if (d.state === "draft") {
			const p = pending.get(d.qid);
			if (p) p.draft = d.draft ?? "";
		} else if (d.state === "resolved") {
			pending.delete(d.qid);
		}
	}
	return pending;
}

/** Transcript row for terminal askq states (queued/draft are shown on the board instead). */
function renderAskqEntry(entry: any, _opts: { expanded: boolean }, theme: any) {
	const d = entry.data as AskqEntryData;
	if (d.state === "resolved" && d.kind === "answered") {
		const answer = (d.answers ?? [])[0] ?? "";
		const first = answer.split("\n")[0].slice(0, 80);
		return new Text(
			theme.fg("success", "✓ ") + theme.fg("muted", `answered: ${first}${answer.length > first.length ? "…" : ""}`),
			0,
			0,
		);
	}
	return undefined;
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));


export function createAskq(pi: ExtensionAPI, board: Board) {
	const pending = new Map<string, Pending>();
	/** Qids with a delivery in flight (dedupes overlapping summons). */
	const delivering = new Set<string>();
	let ctxRef: ExtensionContext | undefined;
	let qCounter = 0;

	/** Board rows: style B (settled) — one line per pending question, no hint suffix. */
	const boardRows = () => (theme: any) =>
		[...pending.values()].map((p) => `${theme.fg("accent", "?")} ${theme.fg("text", p.spec.question)}`);

	const syncBoard = (ctx: ExtensionContext) => board.setRows("askq", pending.size ? boardRows() : undefined, ctx);

	/** The tool's async branch (AskqToolDeps.askAsync). */
	function askAsync(
		specs: QuestionSpec[],
		ctx: ExtensionContext,
	): { content: { type: "text"; text: string }[]; details: { status: "accepted"; pending: string[] } } {
		const questions: string[] = [];
		for (const spec of specs) {
			const qid = `askq-${(++qCounter).toString(36)}-${Date.now().toString(36)}`;
			pending.set(qid, { qid, spec, draft: "" });
			pi.appendEntry("askq", {
				qid,
				state: "queued",
				question: spec.question,
				context: spec.context,
				options: spec.options,
				at: Date.now(),
			} satisfies AskqEntryData);
			questions.push(spec.question);
			ctx.ui.notify(`question pending: ${spec.question.slice(0, 40)}`, "info");
			// thresholdMs 0 + per-question key: arrival always lands, focus
			// suppression stays on (no toast while the user is looking at pi).
			void getHerald().requestAttention(pi, {
				key: qid,
				title: "Question pending",
				body: spec.question,
				thresholdMs: 0,
			});
		}
		syncBoard(ctx);
		return {
			content: [
				textPart(
					"Questions delivered. Do not wait: continue the current task; replies arrive asynchronously as user messages, possibly mid-turn, possibly never.",
				),
			],
			details: { status: "accepted", pending: specs.map((s) => s.question) },
		};
	}

	/** The answer session: current-input popup per pending question, close-keep
	 *  on Esc. The UI lock is held per POPUP only — delivery (compaction waits,
	 *  echo polls) must not stall a sync ask_user_question that fires meanwhile;
	 *  the two serialize per popup instead. Questions mid-delivery are skipped
	 *  so a second summon during a delivery wait can't re-send the same answer. */
	async function runSession(ctx: ExtensionContext): Promise<void> {
		for (;;) {
			const p = [...pending.values()].find((q) => !delivering.has(q.qid));
			if (!p) break;
			const answers = await withUILock(() =>
				askMultiChoice(ctx, p.spec.question, p.spec.context, p.spec.options, {
					initialText: p.draft,
					onCancel: (text) => {
						p.draft = text;
					},
				}),
			).catch(() => null); // popup could not open (stale ctx / lock refusal)
			if (!answers) {
				// Esc: close the whole session, keep this draft, rest stays pending.
				if (p.draft.trim()) {
					pi.appendEntry("askq", { qid: p.qid, state: "draft", draft: p.draft, at: Date.now() } satisfies AskqEntryData);
				}
				break;
			}
			await deliverAnswer(ctx, p, answers);
		}
		syncBoard(ctx);
	}

	/** Expand, build the envelope, deliver (under an in-flight dedupe guard),
	 *  THEN resolve. */
	async function deliverAnswer(ctx: ExtensionContext, p: Pending, answers: AskAnswer[]): Promise<void> {
		// Gate at delivery entry, not just selection: an overlapping summon's
		// popup for the same question answers strictly after the first delivery
		// begins (single-threaded loop), so this check deterministically drops
		// the superseded answer instead of double-sending it.
		if (delivering.has(p.qid)) {
			safeNotify(ctx, `"${p.spec.question.slice(0, 40)}" is already being delivered`, "info");
			return;
		}
		delivering.add(p.qid);
		try {
			await deliverAnswerInner(ctx, p, answers);
		} finally {
			delivering.delete(p.qid);
		}
	}

	async function deliverAnswerInner(ctx: ExtensionContext, p: Pending, answers: AskAnswer[]): Promise<void> {
		const blocks: string[] = [];
		const custom = answers.find((a) => a.type === "custom");
		if (custom?.label) {
			const expansion = await expandAnswerText(custom.label, ctx);
			custom.label = expansion.text;
			blocks.push(...expansion.blocks);
		}
		if (!pending.has(p.qid)) {
			// Left the pending set meanwhile (answered elsewhere, or a tree move
		// took it off the branch) — don't double-deliver.
			safeNotify(ctx, `"${p.spec.question.slice(0, 40)}" is no longer pending`, "info");
			return;
		}
		const parts = answers.map((a) => a.label);
		let envelope = `> ${p.spec.question}\n\n${parts.join("; ")}`;
		if (blocks.length > 0) envelope += `\n\n${blocks.join("\n\n")}`;
		// The resolved entry must land on the branch the answer entered. Tip
		// IDENTITY is the wrong predicate — the delivered user message itself
		// appends and moves the tip. Lineage: the pre-send tip must remain
		// CONTAINED in the branch (appends keep it; a tree move to a sibling
		// branch sharing the queued entry drops it — the zombie case).
		const branch = ctx.sessionManager.getBranch();
		const tipBefore = branch.length ? (branch[branch.length - 1] as any)?.id : undefined;
		const branchContains = (id: unknown): boolean => ctx.sessionManager.getBranch().some((e: any) => e?.id === id);
		const delivered = await yieldPrompt(pi, ctx, envelope).catch(() => false);
		if (!delivered) {
			safeNotify(ctx, `failed to deliver answer for "${p.spec.question.slice(0, 40)}" — still pending`, "warning");
			return;
		}
		if (!pending.has(p.qid) || (tipBefore !== undefined && !branchContains(tipBefore))) return; // tree moved between send and resolve
		pending.delete(p.qid);
		pi.appendEntry("askq", { qid: p.qid, state: "resolved", kind: "answered", question: p.spec.question, answers: parts, at: Date.now() } satisfies AskqEntryData);
		syncBoard(ctx);
	}

	function summon(ctx: ExtensionContext): void {
		if (pending.size === 0) {
			safeNotify(ctx, "no questions pending");
			return;
		}
		// Per-popup locking (see runSession): no lock held across delivery.
		void runSession(ctx).catch(() => {
			safeNotify(ctx, "answer session could not open (another dialog is active)");
		});
	}

	/** Re-fold from the active branch: disarm leavers, re-arm newcomers, refresh drafts. */
	function syncWithBranch(ctx: ExtensionContext): void {
		const folded = foldAskq(ctx.sessionManager.getBranch());
		for (const qid of [...pending.keys()]) if (!folded.has(qid)) pending.delete(qid);
		for (const [qid, p] of folded) {
			const existing = pending.get(qid);
			if (!existing) pending.set(qid, p);
			else if (existing.draft !== p.draft) existing.draft = p.draft;
		}
		syncBoard(ctx);
	}

	return {
		askAsync,
		summon,
		syncWithBranch,
		onSessionStart(ctx: ExtensionContext) {
			ctxRef = ctx;
			pi.registerEntryRenderer("askq", renderAskqEntry);
			syncWithBranch(ctx);
			getLeaderRegistry().register("q", {
				description: "answer pending async questions",
				handler: () => {
					if (ctxRef) summon(ctxRef);
				},
			});
		},
		onSessionTree(ctx: ExtensionContext) {
			ctxRef = ctx;
			syncWithBranch(ctx);
		},
		/** Settle with unanswered questions: one gated ping (the user was away a whole turn). */
		onAgentSettled(ctx: ExtensionContext) {
			if (pending.size === 0) return;
			void getHerald().requestAttention(pi, {
				key: "askq-settled",
				title: `Agent done — ${pending.size} question${pending.size === 1 ? "" : "s"} unanswered`,
				body: [...pending.values()][0]?.spec.question ?? "",
			});
		},
		onSessionShutdown() {
			getLeaderRegistry().unregister("q");
		},
	};
}
