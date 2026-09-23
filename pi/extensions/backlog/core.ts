/**
 * backlog core — the state machine behind a backlogged prompt: ONE armed
 * slot, one queue, gated on either the agent or the user (see index.ts):
 *   settled (/backlog) — gate is "agent not mid-task": fires at invocation
 *     when already idle (waiting would stall — there is no task to await),
 *     else at the next agent_settled.
 *   afk (/when_afk) — gate is armAfkGate() (gates.ts); if the agent is
 *     mid-run when idle is confirmed, hold for the next settle.
 * Both commands face the same slot: bare /backlog or bare /when_afk cancels
 * the armed queue and dumps its text into the editor; adding the OTHER kind
 * while one is armed does the same (the new text is dropped — merge and
 * re-issue from the editor).
 *
 * Event-sourced: every transition appends a custom "backlog" entry (queued
 * / appended / fired / cancelled); foldBranch() derives current state from
 * the active branch — that's what reload, resume and tree moves (undo,
 * /tree) re-arm from. Legacy "when_afk" entries fold as kind afk, so old
 * sessions' pending queues re-arm too.
 */
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { Text } from "@earendil-works/pi-tui";
import { armAfkGate } from "./gates.ts";

export type Kind = "settled" | "afk";

export interface BacklogData {
	qid: string;
	kind?: Kind; // absent on legacy "when_afk" entries
	state: "queued" | "appended" | "fired" | "cancelled";
	minutes?: number; // afk: queued (re-set on append), echoed when resolved
	prompt?: string; // queued snapshot
	text?: string; // appended: just the new text
	reason?: string; // cancelled
	at: number;
}

/** View of the active branch: the newest queue and its folded state. */
export interface Folded {
	qid: string;
	kind: Kind;
	armed: boolean; // last entry was queued/appended
	prompt: string;
	minutes?: number;
}

const join = (a: string, b: string): string => (a ? `${a}\n\n${b}` : b);

/** Fold the active branch into slot state: the last queue wins, appended entries accumulate. */
export function foldBranch(branch: readonly any[]): Folded | undefined {
	let cur: Folded | undefined;
	for (const entry of branch) {
		if (entry.type !== "custom") continue;
		const d = entry.data as BacklogData;
		if (entry.customType === "when_afk") d.kind = "afk"; // legacy extension's entries
		else if (entry.customType !== "backlog") continue;
		const kind = d.kind;
		if (!kind) continue;
		if (d.state === "queued") {
			cur = { qid: d.qid, kind, armed: true, prompt: d.prompt ?? "", minutes: d.minutes };
			continue;
		}
		if (!cur || cur.qid !== d.qid || !cur.armed) continue;
		if (d.state === "appended") {
			cur.prompt = join(cur.prompt, d.text ?? "");
			if (d.minutes !== undefined) cur.minutes = d.minutes;
		} else cur.armed = false; // fired / cancelled
	}
	return cur;
}

/** minutes → "30 mins" / "1 hour" / "1 hour 30 mins" */
function dur(m: number): string {
	const h = Math.floor(m / 60),
		mins = m % 60;
	return h ? `${h} hour${h > 1 ? "s" : ""}${mins ? ` ${mins} mins` : ""}` : `${mins} mins`;
}

function hhmm(at: number): string {
	return new Date(at).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
}

export function renderEntry(entry: any, _opts: { expanded: boolean }, theme: any) {
	const d = entry.data as BacklogData;
	if (d.state === "queued" || d.state === "appended") return undefined;
	const afk = (d.kind ?? "afk") === "afk";
	if (d.state === "fired") {
	const lead = afk && d.minutes !== undefined ? `AFK for ${dur(d.minutes)}, ` : "";
		const msg = afk ? `${lead}backlog message fired at ${hhmm(d.at)}` : `Backlog message fired at ${hhmm(d.at)}`;
		return new Text(theme.fg("success", "✓ ") + theme.fg("muted", msg), 0, 0);
	}
	return new Text(theme.fg("warning", "✗ ") + theme.fg("muted", `cancelled — ${d.reason ?? ""}`), 0, 0);
}

function preview(prompt: string): string {
	const lines = prompt.split("\n");
	let p = lines[0] ?? "";
	if (lines.length > 1) p += ` (+${lines.length - 1} lines)`;
	return p.length > 80 ? `${p.slice(0, 80)}…` : p;
}

function widgetRow(s: Slot, theme: any): Text {
	const label = s.kind === "afk" ? `when_afk ${s.minutes}m` : "backlog";
	return new Text(`${theme.fg("accent", "⧗")} ${theme.bold(label)} ${theme.fg("muted", preview(s.prompt))}`, 0, 0);
}

let qCounter = 0;

interface Slot {
	qid: string;
	kind: Kind;
	prompt: string;
	minutes?: number; // afk
	gatePassed?: boolean; // afk: idle confirmed, waiting for agent settle
	stopGate?: () => void; // afk
}

export function createBacklogs(pi: ExtensionAPI) {
	let slot: Slot | undefined;

	const nextQid = (kind: Kind) => `${kind}-${(++qCounter).toString(36)}-${Date.now().toString(36)}`;

	const disarm = () => {
		slot?.stopGate?.();
		slot = undefined;
	};

	const syncWidget = (ctx: ExtensionContext) => {
		if (!ctx.hasUI) return;
		const s = slot;
		ctx.ui.setWidget("backlog", s ? (_tui: unknown, theme: any) => widgetRow(s, theme) : undefined);
	};

	/** Resolve the slot: stop its gate, append the result row. Noop if none / kind mismatch. */
	const settle = (kind: Kind, state: "fired" | "cancelled", reason: string | undefined, ctx: ExtensionContext) => {
		const s = slot;
		if (!s || s.kind !== kind) return;
		disarm();
		pi.appendEntry("backlog", { qid: s.qid, kind, state, reason, minutes: s.minutes, at: Date.now() } as BacklogData);
		syncWidget(ctx);
	};

	const fire = (ctx: ExtensionContext) => {
		const s = slot;
		if (!s) return;
		settle(s.kind, "fired", undefined, ctx);
		if (ctx.isIdle()) pi.sendUserMessage(s.prompt);
		else pi.sendUserMessage(s.prompt, { deliverAs: "followUp" }); // lost a race with another run
	};

	const startGate = (s: Slot, ctx: ExtensionContext) => {
		s.stopGate?.(); // a restart must kill the previous poller: same slot survives appends, so the qid-style guard can't
		s.gatePassed = false;
		s.stopGate = armAfkGate(
			s.minutes!,
			() => {
				if (slot !== s) return;
				s.gatePassed = true;
				if (ctx.isIdle()) fire(ctx); // else hold for agent_settled
			},
			(reason) => {
				if (slot === s) settle("afk", "cancelled", reason, ctx);
			},
		);
	};

	const arm = (qid: string, kind: Kind, prompt: string, minutes: number | undefined, ctx: ExtensionContext) => {
		const s: Slot = { qid, kind, prompt, minutes };
		slot = s;
		if (kind === "afk") startGate(s, ctx);
		else if (ctx.isIdle()) fire(ctx); // idle agent — nothing to await
		syncWidget(ctx);
	};

	/** Cancel the armed queue and hand its text to the editor. */
	const dumpToEditor = (ctx: ExtensionContext) => {
		const s = slot;
		if (!s) return;
		settle(s.kind, "cancelled", "dumped to editor", ctx);
		if (ctx.hasUI) ctx.ui.setEditorText(s.prompt);
	};

	return {
		/** Queue fresh, or append to the armed slot (every /when_afk restarts its timer). */
		add(kind: Kind, text: string, minutes: number | undefined, ctx: ExtensionContext) {
			const s = slot;
			if (s && s.kind !== kind) return dumpToEditor(ctx); // one slot, one gate: refuse the swap
			if (!s) {
				const qid = nextQid(kind);
				pi.appendEntry("backlog", { qid, kind, state: "queued", prompt: text, minutes, at: Date.now() } as BacklogData);
				arm(qid, kind, text, minutes, ctx);
				return;
			}
			pi.appendEntry("backlog", { qid: s.qid, kind, state: "appended", text, minutes, at: Date.now() } as BacklogData);
			s.prompt = join(s.prompt, text);
			if (kind === "afk") {
				s.minutes = minutes!;
				startGate(s, ctx);
			}
			syncWidget(ctx);
		},

		dumpToEditor,

		settle,

		/** agent_settled: the settled gate itself; afk only fires if its gate already passed. */
		onAgentSettled(ctx: ExtensionContext) {
			if (slot?.kind === "settled") fire(ctx);
			else if (slot?.gatePassed) fire(ctx);
		},

		/**
		 * Sync the armed slot with the active branch (foldBranch decides): a
		 * queue that left the branch (undo, /tree) is disarmed; a queued tail
		 * with nothing armed re-arms; undo of an append rewinds prompt (and
		 * afk timer) in place.
		 */
		syncWithBranch(ctx: ExtensionContext) {
			const f = foldBranch(ctx.sessionManager.getBranch());
			const s = slot;
			if (s && (!f || f.qid !== s.qid || f.kind !== s.kind || !f.armed)) disarm();
			else if (s) {
				if (s.prompt !== f!.prompt) s.prompt = f!.prompt;
				if (s.kind === "afk" && f!.minutes !== s.minutes) {
					s.minutes = f!.minutes!;
					startGate(s, ctx);
				}
			}
			if (!slot && f?.armed) arm(f.qid, f.kind, f.prompt, f.minutes, ctx);
			// undo//tree can re-land on a queued tail with the slot still armed and
			// the agent idle — same rule: nothing to await, fire now
			if (slot?.kind === "settled" && ctx.isIdle()) fire(ctx);
			syncWidget(ctx);
		},

		disarmAll() {
			disarm(); // keep entries for re-arm
		},
	};
}
