/**
 * when_afk — queue a prompt that fires once you've been idle for N minutes.
 *
 *   /when_afk <minutes> <prompt>    queue (replaces any pending prompt)
 *   /when_afk                       cancel the pending prompt (noop if none)
 *
 * Idle *measurement* stays in the shell script (scripts/when_afk, on PATH):
 * each poll spawns `bash -c 'source when_afk && afk_idle'` and reads idle ms
 * from stdout. The poll loop itself lives here in TypeScript. Wayland
 * migration = change afk_idle()'s body in the script; this file is untouched.
 * (Override the script path with $WHEN_AFK_SCRIPT.)
 *
 * Fire semantics mirror the script's main(): poll every 60s; once idle
 * crosses the threshold, re-check after 5s (came-back guard), then dispatch
 * via pi.sendUserMessage() verbatim.
 *
 * The queue renders in the chat transcript like a tool invocation (see
 * ask-user-questions): a `when_afk <minutes>m` row with the prompt when
 * queued, a `✓ fired` / `✗ cancelled` row when it resolves. Rows are custom
 * entries — visible to you, not sent to the model.
 *
 * Purge rules: any message you send while a prompt is queued cancels it (an
 * active user is not AFK); queueing again cancels the old one; bare
 * /when_afk cancels. Quitting or /reload disarms the timer but the queued
 * entry persists in the session — reloading or resuming re-arms it. Tree
 * moves (undo, /tree) sync the same way: an armed queue whose entry left
 * the active branch is disarmed; navigating back onto a queued tail re-arms
 * it. Undoing the fired turn itself lands on the ✓ fired entry (the parent
 * of the dispatched message) and does not re-arm anything.
 */
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { Text } from "@earendil-works/pi-tui";
import { spawn } from "node:child_process";

const SCRIPT = process.env.WHEN_AFK_SCRIPT ?? "when_afk"; // sourced for afk_idle()
const POLL_MS = 60_000; // parity with the script's POLL_INTERVAL (seconds)
const CONFIRM_MS = 5_000; // the script's came-back double-check window

interface AfkData {
	qid: string;
	state: "queued" | "fired" | "cancelled";
	minutes?: number; // queued
	prompt?: string;
	reason?: string; // cancelled
	at: number;
}

function preview(s: string): string {
	return s.length > 48 ? s.slice(0, 45) + "…" : s;
}

function hhmm(at: number): string {
	return new Date(at).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
}

/** Current idle ms via the script's afk_idle(); null on any failure. */
function afkIdle(): Promise<number | null> {
	return new Promise((resolve) => {
		// no slash in "$1" → bash's source searches PATH
		const child = spawn("bash", ["-c", 'source "$1" && afk_idle', "when_afk", SCRIPT], {
			stdio: ["ignore", "pipe", "ignore"],
		});
		let out = "";
		child.stdout.on("data", (chunk) => (out += chunk));
		const kill = setTimeout(() => child.kill("SIGKILL"), 5_000);
		child.on("error", () => {
			clearTimeout(kill);
			resolve(null);
		});
		child.on("close", (code) => {
			clearTimeout(kill);
			const idle = parseInt(out.trim(), 10);
			resolve(code === 0 && Number.isFinite(idle) ? idle : null);
		});
	});
}

/** Transcript row(s) for a when_afk entry: call-style when queued, result-style once resolved. */
function renderEntry(entry: any, _opts: { expanded: boolean }, theme: any) {
	const d = entry.data as AfkData;
	if (d.state === "queued") {
		const title = theme.fg("toolTitle", theme.bold("when_afk ")) + theme.fg("muted", `${d.minutes}m`);
		const body = (d.prompt ?? "").split("\n").map((line) => theme.fg("text", line));
		return new Text([title, ...body].join("\n"), 0, 0);
	}
	if (d.state === "fired") {
		return new Text(theme.fg("success", "✓ ") + theme.fg("muted", `fired ${hhmm(d.at)} — ${preview(d.prompt ?? "")}`), 0, 0);
	}
	return new Text(theme.fg("warning", "✗ ") + theme.fg("muted", `cancelled — ${d.reason ?? ""}`), 0, 0);
}

let qCounter = 0;

export default function (pi: ExtensionAPI) {
	let queued: {
		qid: string;
		minutes: number;
		prompt: string;
		timer: NodeJS.Timeout | undefined;
	} | null = null;

	const disarm = () => {
		if (queued) clearTimeout(queued.timer);
		queued = null;
	};

	/** Resolve the pending prompt: stop its timer, append the result row. Noop if none. */
	const settle = (state: "fired" | "cancelled", reason?: string) => {
		if (!queued) return;
		const { qid, prompt } = queued;
		disarm();
		pi.appendEntry("when_afk", { qid, state, reason, prompt, at: Date.now() } as AfkData);
	};

	/** Poll loop for one queue item; guards every await with a qid check. */
	const arm = (qid: string, minutes: number, prompt: string, ctx: ExtensionContext) => {
		disarm();
		const q = { qid, minutes, prompt, timer: undefined as NodeJS.Timeout | undefined };
		queued = q;
		const thresholdMs = minutes * 60_000;

		const fire = () => {
			settle("fired");
			if (ctx.isIdle()) pi.sendUserMessage(prompt);
			else pi.sendUserMessage(prompt, { deliverAs: "followUp" });
		};

		const confirm = async () => {
			if (queued !== q) return;
			const idle = await afkIdle();
			if (queued !== q) return;
			if (idle === null) settle("cancelled", "afk_idle() failed — is when_afk on PATH? xprintidle installed?");
			else if (idle > thresholdMs) fire();
			else settle("cancelled", "activity during confirm window");
		};

		const tick = async () => {
			if (queued !== q) return;
			const idle = await afkIdle();
			if (queued !== q) return;
			if (idle === null) settle("cancelled", "afk_idle() failed — is when_afk on PATH? xprintidle installed?");
			else if (idle > thresholdMs) q.timer = setTimeout(confirm, CONFIRM_MS);
			else q.timer = setTimeout(tick, POLL_MS);
		};

		q.timer = setTimeout(tick, 1_000);
	};

	pi.registerCommand("when_afk", {
		description: "Queue a prompt to fire once idle ≥ N minutes; no args cancels the pending one",
		handler: async (args: string, ctx: ExtensionContext) => {
			const m = /^(\d+)\s+([\s\S]+)$/.exec(args.trim());
			if (!m) {
				settle("cancelled", "via /when_afk"); // noop when nothing queued
				return;
			}
			settle("cancelled", "replaced");
			const minutes = parseInt(m[1], 10);
			const qid = `afk-${(++qCounter).toString(36)}-${Date.now().toString(36)}`;
			pi.appendEntry("when_afk", { qid, state: "queued", minutes, prompt: m[2], at: Date.now() } as AfkData);
			arm(qid, minutes, m[2], ctx);
		},
	});

	// An active user is not AFK: any real message cancels the pending prompt.
	pi.on("input", (event) => {
		if (event.source === "extension") return; // our own dispatch
		settle("cancelled", "user active");
	});

	/**
	 * Sync the armed timer with the active branch: last entry per qid decides
	 * its state. An armed queue whose entry left the branch (undo, /tree)
	 * loses its timer; a queued tail with nothing armed (navigated back onto
	 * the pending moment) re-arms.
	 */
	const syncWithBranch = (ctx: ExtensionContext) => {
		const last = new Map<string, AfkData>();
		for (const entry of ctx.sessionManager.getBranch()) {
			if (entry.type === "custom" && entry.customType === "when_afk") {
				const d = entry.data as AfkData;
				last.set(d.qid, d);
			}
		}
		if (queued && last.get(queued.qid)?.state !== "queued") disarm();
		if (!queued) {
			for (const d of last.values()) {
				if (d.state === "queued") {
					arm(d.qid, d.minutes!, d.prompt!, ctx);
					break;
				}
			}
		}
	};

	pi.on("session_start", (_event, ctx) => {
		pi.registerEntryRenderer("when_afk", renderEntry);
		syncWithBranch(ctx); // re-arm queues orphaned by quit/crash//reload
	});

	pi.on("session_tree", (_event, ctx) => syncWithBranch(ctx));

	pi.on("session_shutdown", () => disarm()); // keep the queued entry for re-arm
}
