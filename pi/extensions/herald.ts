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
//   session.idle          ->  "agent_end"      (turn complete, back to user)
//   message.part.updated  ->  "tool_call"      (optional heavy-tool trigger)
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
	if (!process.env.TMUX) return ", pi";
	try {
		const session = (await pi.exec("tmux", ["display-message", "-p", "#S"])).stdout.trim();
		const window = (await pi.exec("tmux", ["display-message", "-p", "#W"])).stdout.trim();
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
	messages?: Array<{ role?: string; stopReason?: string }>;
};

export default function (pi: ExtensionAPI) {
	let lastInputTime: number | null = null;
	let usedHeavyTool = false;

	pi.on("input", async () => {
		lastInputTime = Date.now();
		usedHeavyTool = false;
		log("input received");
	});

	pi.on("tool_call", async (event) => {
		const name = (event as { toolName?: string }).toolName;
		if (name && HEAVY_TOOLS.includes(name)) {
			usedHeavyTool = true;
			log(`heavy tool used: ${name}`);
		}
	});

	pi.on("agent_end", async (event) => {
		log(`agent_end fired (lastInputTime=${lastInputTime}, usedHeavyTool=${usedHeavyTool})`);
		if (lastInputTime == null) return;
		const elapsed = Date.now() - lastInputTime;
		const timedOut = elapsed > THRESHOLD;
		if (!timedOut && !usedHeavyTool) {
			lastInputTime = null;
			usedHeavyTool = false;
			return;
		}
		// Suppress if the user manually aborted this turn (interrupted streams
		// leave the final assistant message with stopReason === "aborted").
		const messages = (event as unknown as AgentEndEventLike)?.messages ?? [];
		const lastAssistant = [...messages].reverse().find((m) => m?.role === "assistant");
		if (lastAssistant?.stopReason === "aborted") {
			log(`suppressing notification: turn aborted (stopReason="aborted")`);
			lastInputTime = null;
			usedHeavyTool = false;
			return;
		}
		// Suppress if the user is already looking at this pi.
		const looking = await isUserLooking(pi);
		log(`focus check: looking=${looking} display=${displayKind()}`);
		if (looking) {
			lastInputTime = null;
			usedHeavyTool = false;
			return;
		}
		const duration = formatDuration(elapsed);
		const tmuxInfo = await getTmuxInfo(pi);
		const body = `Done${tmuxInfo} (${duration})`;
		try {
			await pi.exec("herald", ["message", "--title", "Human, I am done 🥹", "--sound", body]);
			log(`notified: ${body}`);
		} catch (e) {
			log(`herald failed: ${e instanceof Error ? e.message : String(e)}`);
		}
		lastInputTime = null;
		usedHeavyTool = false;
	});
}
