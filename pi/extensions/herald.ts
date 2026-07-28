import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { appendFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

// Port of the opencode herald-notifications plugin.
// Fires a `herald` notification when pi finishes a turn that ran longer than
// THRESHOLD since the user's last input — i.e. "the agent is done, come back".
//
// Event mapping from opencode:
//   session.status(busy)  ->  "input"          (user sent a prompt)
//   session.idle          ->  "agent_settled"  (turn fully settled — see below)
//   message.part.updated  ->  "tool_call"      (optional heavy-tool trigger)
//
// Why agent_settled and not agent_end: agent_end fires once per agent-core run,
// including before each automatic retry of a connection/API error, so notifying
// on it would ping on every transient connection error. agent_settled fires
// only after a run has fully settled (no retry, compaction, or queued
// continuation left), so it is the one "the turn is really over" signal. The
// last agent_end's assistant stopReason is captured to distinguish a clean
// finish ("stop" / "toolUse") from a terminal error ("error", retries
// exhausted) — the latter is reported as "I hit an error" instead of "done".
//
// The opencode plugin also notified on question.asked / permission.asked and on
// subagent/todowrite use. Pi has no built-in permission/question events (those
// happen via ctx.ui inline) and no built-in subagent, so those triggers are
// dropped here; add tool_call names to HEAVY_TOOLS to revive mid-turn alerts.

const THRESHOLD = 2 * 60 * 1000;
const HEAVY_TOOLS: string[] = [];
const LOG = join(process.env.XDG_STATE_HOME ?? `${homedir()}/.local/state`, "pi", "herald.log");

function log(msg: string): void {
	try {
		appendFileSync(LOG, `${new Date().toISOString()} ${msg}\n`);
	} catch {
		// best-effort
	}
}

function formatDuration(ms: number): string {
	const seconds = Math.floor(ms / 1000);
	if (seconds < 60) return `${seconds}s`;
	const minutes = Math.floor(seconds / 60);
	const secs = seconds % 60;
	if (minutes < 60) return `${minutes}m ${secs}s`;
	const hours = Math.floor(minutes / 60);
	const mins = minutes % 60;
	return `${hours}h ${mins}m`;
}

async function getTmuxInfo(pi: ExtensionAPI): Promise<string> {
	// Target our own pane explicitly. Without `-t`, display-message resolves
	// formats against the client's *active* pane (whatever the user is looking
	// at), so window/session would reflect the wrong window when the user has
	// switched away from this pi.
	const pane = process.env.TMUX_PANE;
	if (!process.env.TMUX || !pane) return ", pi";
	try {
		const session = (await pi.exec("tmux", ["display-message", "-t", pane, "-p", "#{session_name}"])).stdout.trim();
		const window = (await pi.exec("tmux", ["display-message", "-t", pane, "-p", "#{window_name}"])).stdout.trim();
		if (!session) return ", pi";
		let info = ` in tmux session \`${session}\``;
		if (window) info += `, at window \`${window}\``;
		return info;
	} catch {
		return ", pi";
	}
}

// --- "is the user looking at this pi?" -------------------------------------
// Notifications are suppressed when we're confident the user is already
// looking at this pi instance. Two independent layers must agree:
//   1. tmux layer (display-agnostic): the window containing this pi is the
//      active window of an attached session. (Skipped when not in tmux.)
//   2. display layer (X11 / Wayland backend): the OS-focused top-level window
//      is the terminal emulator hosting this process (or one of our session's
//      tmux clients).
// When anything can't be determined we return false (=> still notify), so we
// only ever suppress when confident. Manual aborts are also suppressed.

function displayKind(): "wl" | "x11" | "tty" {
	if (process.env.WAYLAND_DISPLAY) return "wl";
	if (process.env.DISPLAY) return "x11";
	return "tty";
}

/** PID owning the OS-focused top-level window, or null when unknown. */
async function focusedWindowPid(pi: ExtensionAPI): Promise<number | null> {
	switch (displayKind()) {
		case "tty":
			return null; // handled by isUserLooking() (treated as "looking")
		case "wl": {
			// TODO(wl): implement compositor-specific focus detection (e.g.
			// swaymsg -t get_tree, hyprctl activewindow -j, gdbus/qdbus). Until then
			// we can't tell what's focused, so default to "not looking" (notify) —
			// same as X11 when xdotool is missing, and unlike tty. See
			// wayland_migration.md.
			return null;
		}
		case "x11": {
			try {
				const win = (await pi.exec("xdotool", ["getactivewindow"])).stdout.trim();
				if (!win) return null;
				const pid = Number((await pi.exec("xdotool", ["getwindowpid", win])).stdout.trim());
				return Number.isInteger(pid) && pid > 0 ? pid : null;
			} catch {
				return null;
			}
		}
	}
}

/**
 * True if `ancestor` appears in the PPid chain of any of `pids`.
 * Runs a single bash subprocess walking /proc/<pid>/status.
 */
async function isAncestorOfAny(pi: ExtensionAPI, ancestor: number, pids: number[]): Promise<boolean> {
	const script = [
		`a=${ancestor}`,
		`for d in ${pids.join(" ")}; do`,
		`  p=$d`,
		`  while [ "$p" -gt 1 ] 2>/dev/null; do`,
		`    [ "$p" = "$a" ] && { echo 1; exit 0; }`,
		`    p=$(awk '/^PPid:/{print $2}' "/proc/$p/status" 2>/dev/null)`,
		`    [ -z "$p" ] && break`,
		`  done`,
		`done`,
		`echo 0`,
	].join("\n");
	try {
		return (await pi.exec("bash", ["-c", script])).stdout.trim() === "1";
	} catch {
		return false;
	}
}

/** Is the user currently looking at this pi instance? */
async function isUserLooking(pi: ExtensionAPI): Promise<boolean> {
	// No display server: the user is at a VT with nothing else to look at on
	// this seat, and herald has nowhere to render anyway -> suppress.
	if (displayKind() === "tty") return true;

	const focused = await focusedWindowPid(pi);
	if (focused == null) return false; // can't determine -> notify (conservative)

	const pane = process.env.TMUX_PANE;
	const descendants: number[] = [];
	if (pane) {
		// Layer 1: our window must be the active window of its session.
		let session: string;
		try {
			const out = (await pi.exec("tmux", [
				"display-message", "-t", pane, "-p", "#{window_active}#{session_name}",
			])).stdout.trim();
			if (!out.startsWith("1")) return false; // different window -> not looking
			session = out.slice(1);
		} catch {
			return false;
		}
		// PIDs of tmux clients attached to our session (children of their terminals).
		try {
			const out = (await pi.exec("tmux", [
				"list-clients", "-t", session, "-F", "#{client_pid}",
			])).stdout.trim();
			for (const n of out.split(/\s+/)) {
				const pid = Number(n);
				if (Number.isInteger(pid) && pid > 0) descendants.push(pid);
			}
		} catch {
			return false;
		}
		if (descendants.length === 0) return false;
	} else {
		// Not in tmux: pi itself is a child of the terminal.
		descendants.push(process.pid);
	}

	// Layer 2: is the focused window's owner an ancestor of one of our processes?
	return isAncestorOfAny(pi, focused, descendants);
}

// Shape of the agent_end event payload (cast locally to avoid importing the
// full internal message types).
type AgentEndEventLike = {
	messages?: Array<{ role?: string; stopReason?: string; errorMessage?: string }>;
};

export default function (pi: ExtensionAPI) {
	let lastInputTime: number | null = null;
	let usedHeavyTool = false;
	// Outcome of the most recent agent_end. agent_end fires once per agent-core
	// run — including before each automatic retry — so it can't by itself tell
	// us whether the turn is truly over. We defer the notification to
	// agent_settled (which fires only once no retry/compaction/continuation will
	// run) and use this captured state to report success vs. a terminal
	// connection error.
	let lastStopReason: string | null = null;
	let lastErrorMessage: string | null = null;

	function reset(): void {
		lastInputTime = null;
		usedHeavyTool = false;
		lastStopReason = null;
		lastErrorMessage = null;
	}

	function describeError(msg: string | null): string {
		if (!msg) return "unknown error";
		const s = String(msg).replace(/\s+/g, " ").trim();
		return s.length > 120 ? s.slice(0, 117) + "…" : s;
	}

	/** Herald send with focus suppression + state reset. */
	async function notify(title: string, label: string, detail?: string): Promise<void> {
		const looking = await isUserLooking(pi);
		log(`focus check: looking=${looking} display=${displayKind()}`);
		if (looking) {
			reset();
			return;
		}
		const elapsed = lastInputTime != null ? Date.now() - lastInputTime : 0;
		const duration = elapsed > 0 ? formatDuration(elapsed) : "";
		const tmuxInfo = await getTmuxInfo(pi);
		let body = `${label}${tmuxInfo}`;
		if (duration) body += ` (${duration})`;
		if (detail) body += ` — ${detail}`;
		try {
			await pi.exec("herald", ["message", "--title", title, "--sound", body]);
			log(`notified: ${body}`);
		} catch (e) {
			log(`herald failed: ${e instanceof Error ? e.message : String(e)}`);
		}
		reset();
	}

	pi.on("input", async () => {
		lastInputTime = Date.now();
		usedHeavyTool = false;
		lastStopReason = null;
		lastErrorMessage = null;
		log("input received");
	});

	pi.on("tool_call", async (event) => {
		const name = (event as { toolName?: string }).toolName;
		if (name && HEAVY_TOOLS.includes(name)) {
			usedHeavyTool = true;
			log(`heavy tool used: ${name}`);
		}
	});

	// Capture the outcome of each agent-core run. Fires before every automatic
	// retry too, so we only record state here — never notify.
	pi.on("agent_end", async (event) => {
		const messages = (event as unknown as AgentEndEventLike)?.messages ?? [];
		const lastAssistant = [...messages].reverse().find((m) => m?.role === "assistant");
		lastStopReason = (lastAssistant?.stopReason as string | undefined) ?? null;
		lastErrorMessage = (lastAssistant?.errorMessage as string | undefined) ?? null;
		log(`agent_end: stopReason=${lastStopReason}`);
	});

	// The turn has fully settled: no automatic retry, compaction, or queued
	// continuation will run. This is the one reliable "the user should come back
	// now" moment — agent_end fires mid-retry, agent_settled does not.
	pi.on("agent_settled", async () => {
		log(`agent_settled (lastStopReason=${lastStopReason}, lastInputTime=${lastInputTime}, usedHeavyTool=${usedHeavyTool})`);
		if (lastInputTime == null) {
			reset();
			return;
		}
		// Manual abort — don't bother the user.
		if (lastStopReason === "aborted") {
			log("suppressing notification: turn aborted");
			reset();
			return;
		}
		const elapsed = Date.now() - lastInputTime;
		if (elapsed <= THRESHOLD && !usedHeavyTool) {
			reset();
			return;
		}
		// Turn died on an error after exhausting all retries: report it honestly
		// instead of "done".
		if (lastStopReason === "error") {
			await notify("Human, I hit an error 🫠", "Failed", describeError(lastErrorMessage));
			return;
		}
		await notify("Human, I am done 🥹", "Done");
	});
}
