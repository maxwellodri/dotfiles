/**
 * backlog core — shared state machine for backlogged messages: a prompt
 * buffered in the session that dispatches once its gate passes AND the
 * agent has fully settled (agent_settled: retries, compaction and queued
 * follow-ups all drained — never at a mid-run turn boundary).
 *
 * Two kinds, two slots, max one armed each:
 *   settled (/backlog) — gate is "agent not mid-task": fires at invocation
 *     when already idle (waiting would stall — there is no task to await),
 *     else at the next agent_settled.
 *   afk (/when_afk) — gate is armAfkGate() (gates.ts); if the agent is
 *     mid-run when idle is confirmed, hold for the next settle.
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

/** Per-kind view of the active branch: the newest queue and its folded state. */
export interface Folded {
	qid: string;
	kind: Kind;
	armed: boolean; // last entry was queued/appended
	prompt: string;
	minutes?: number;
}

const join = (a: string, b: string): string => (a ? `${a}\n\n${b}` : b);

/** Fold the active branch into per-kind state: last queue per kind wins, appended entries accumulate. */
export function foldBranch(branch: readonly any[]): Map<Kind, Folded> {
	const folded = new Map<Kind, Folded>();
	for (const entry of branch) {
		if (entry.type !== "custom") continue;
		const d = entry.data as BacklogData;
		if (entry.customType === "when_afk") d.kind = "afk"; // legacy extension's entries
		else if (entry.customType !== "backlog") continue;
		const kind = d.kind;
		if (!kind) continue;
		if (d.state === "queued") {
			folded.set(kind, { qid: d.qid, kind, armed: true, prompt: d.prompt ?? "", minutes: d.minutes });
			continue;
		}
		const cur = folded.get(kind);
		if (!cur || cur.qid !== d.qid || !cur.armed) continue;
		if (d.state === "appended") {
			cur.prompt = join(cur.prompt, d.text ?? "");
			if (d.minutes !== undefined) cur.minutes = d.minutes;
		} else cur.armed = false; // fired / cancelled
	}
	return folded;
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

/** Transcript row(s): call-style when queued/appended, result-style once resolved. */
export function renderEntry(entry: any, _opts: { expanded: boolean }, theme: any) {
	const d = entry.data as BacklogData;
	const afk = (d.kind ?? "afk") === "afk";
	if (d.state === "queued" || d.state === "appended") {
		const plus = d.state === "appended";
		const title = afk
			? theme.fg(plus ? "muted" : "toolTitle", `${plus ? "+ " : ""}${theme.bold("when_afk ")}`) + theme.fg("muted", `${d.minutes}m`)
			: theme.fg(plus ? "muted" : "toolTitle", `${plus ? "+ " : ""}${theme.bold("backlog")}`);
		const body = (plus ? d.text : d.prompt) ?? "";
		return new Text([title, ...body.split("\n").map((line) => theme.fg("text", line))].join("\n"), 0, 0);
	}
	if (d.state === "fired") {
		// no prompt echo — the dispatched message lands directly below
		const lead = afk && d.minutes !== undefined ? `AFK for ${dur(d.minutes)}, ` : "";
		const msg = afk ? `${lead}backlog message fired at ${hhmm(d.at)}` : `Backlog message fired at ${hhmm(d.at)}`;
		return new Text(theme.fg("success", "✓ ") + theme.fg("muted", msg), 0, 0);
	}
	return new Text(theme.fg("warning", "✗ ") + theme.fg("muted", `cancelled — ${d.reason ?? ""}`), 0, 0);
}

let qCounter = 0;

interface Slot {
	qid: string;
	prompt: string;
	minutes?: number; // afk
	gatePassed?: boolean; // afk: idle confirmed, waiting for agent settle
	stopGate?: () => void; // afk
}

export function createBacklogs(pi: ExtensionAPI) {
	const slots: Partial<Record<Kind, Slot>> = {};

	const disarm = (kind: Kind) => {
		slots[kind]?.stopGate?.();
		delete slots[kind];
	};

	/** Resolve the slot: stop its gate, append the result row. Noop if none. */
	const settle = (kind: Kind, state: "fired" | "cancelled", reason?: string) => {
		const s = slots[kind];
		if (!s) return;
		disarm(kind);
		pi.appendEntry("backlog", { qid: s.qid, kind, state, reason, minutes: s.minutes, at: Date.now() } as BacklogData);
	};

	const fire = (kind: Kind, ctx: ExtensionContext) => {
		const s = slots[kind];
		if (!s) return;
		settle(kind, "fired");
		if (ctx.isIdle()) pi.sendUserMessage(s.prompt);
		else pi.sendUserMessage(s.prompt, { deliverAs: "followUp" }); // lost a race with another run
	};

	const startGate = (s: Slot, ctx: ExtensionContext) => {
		s.stopGate?.(); // a restart must kill the previous poller: same slot survives appends, so the qid-style guard can't
		s.gatePassed = false;
		s.stopGate = armAfkGate(
			s.minutes!,
			() => {
				if (slots.afk !== s) return;
				s.gatePassed = true;
				if (ctx.isIdle()) fire("afk", ctx); // else hold for agent_settled
			},
			(reason) => {
				if (slots.afk === s) settle("afk", "cancelled", reason);
			},
		);
	};

	const arm = (qid: string, kind: Kind, prompt: string, minutes: number | undefined, ctx: ExtensionContext) => {
		const s: Slot = { qid, prompt, minutes };
		slots[kind] = s;
		if (kind === "afk") startGate(s, ctx);
		else if (ctx.isIdle()) fire("settled", ctx); // idle agent — nothing to await
	};

	return {
		/** Queue fresh, or append to the armed slot (every /when_afk restarts its timer). */
		add(kind: Kind, text: string, minutes: number | undefined, ctx: ExtensionContext) {
			const s = slots[kind];
			if (!s) {
				const qid = `${kind}-${(++qCounter).toString(36)}-${Date.now().toString(36)}`;
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
		},

		/** Bare /backlog: cancel and hand the text back for the editor. */
		dump(kind: Kind): string | undefined {
			const s = slots[kind];
			if (!s) return undefined;
			settle(kind, "cancelled", "dumped to editor");
			return s.prompt;
		},

		settle,

		/** agent_settled: the settled gate itself; afk only fires if its gate already passed. */
		onAgentSettled(ctx: ExtensionContext) {
			if (slots.settled) fire("settled", ctx);
			if (slots.afk?.gatePassed) fire("afk", ctx);
		},

		/**
		 * Sync armed slots with the active branch (foldBranch decides): a slot
		 * whose queue left the branch (undo, /tree) is disarmed; a queued tail
		 * with nothing armed re-arms; undo of an append rewinds prompt (and
		 * afk timer) in place.
		 */
		syncWithBranch(ctx: ExtensionContext) {
			const folded = foldBranch(ctx.sessionManager.getBranch());
			for (const kind of ["settled", "afk"] as const) {
				const f = folded.get(kind);
				const s = slots[kind];
				if (s && (!f || f.qid !== s.qid || !f.armed)) disarm(kind);
				else if (s) {
					if (s.prompt !== f!.prompt) s.prompt = f!.prompt;
					if (kind === "afk" && f!.minutes !== s.minutes) {
						s.minutes = f!.minutes!;
						startGate(s, ctx);
					}
				}
				if (!slots[kind] && f?.armed) arm(f.qid, kind, f.prompt, f.minutes, ctx);
			}
			// undo//tree can re-land on a queued tail with the slot still armed and
			// the agent idle — same rule: nothing to await, fire now
			if (slots.settled && ctx.isIdle()) fire("settled", ctx);
		},

		disarmAll() {
			disarm("settled");
			disarm("afk"); // keep entries for re-arm
		},
	};
}
