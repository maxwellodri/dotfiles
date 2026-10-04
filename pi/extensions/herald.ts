/**
 * herald.ts — attention notifications via the `herald` binary when a turn
 * outlasts a silence threshold ("agent done, come back"). Also a shared
 * library: other extensions call getHerald().requestAttention(pi, { key,
 * title, body }); the shared instance lives on globalThis (moduleCache is
 * disabled, so plain imports give each importer its own copy) — see
 * leader-key.ts for the rationale.
 *
 * Fires on agent_settled, not agent_end: agent_end also fires before each
 * automatic retry, so it would ping on transient connection errors.
 * Suppressed only when the tmux-window AND display focus layers agree the
 * user is looking; undetectable → notify.
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { appendFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

// ── Shared library ────────────────────────────────────────────────────────

const LIB_KEY = "__piHeraldLib";

const LOG = join(process.env.XDG_STATE_HOME ?? `${homedir()}/.local/state`, "pi", "herald.log");

/** Default minimum silence before an attention ping fires. */
export const DEFAULT_THRESHOLD_MS = 2 * 60 * 1000;

export interface HeraldNotifyOptions {
	/** Notification title, e.g. "Human, I am done 🥹". */
	title: string;
	/** Body text (status + context). tmux info is appended automatically. */
	body: string;
	/** Skip the focus suppression and send regardless. */
	force?: boolean;
}

export interface HeraldAttentionOptions {
	/**
	 * Category of this attention moment (e.g. "turn-settled", "override-trust").
	 * Each key fires at most once per human interaction: after you answer one
	 * trust prompt, a second pending trust prompt won't re-ping unless it's a
	 * different key. Keys clear when the human interacts (touch()).
	 */
	key: string;
	title: string;
	body: string;
	/** Minimum silence before this fires. Default: DEFAULT_THRESHOLD_MS. */
	thresholdMs?: number;
	/** Fire regardless of silence duration and focus. */
	force?: boolean;
}

export interface HeraldLib {
	/** Send a herald notification now (focus-suppressed unless `force`). Best-effort: never throws. */
	notify(pi: ExtensionAPI, opts: HeraldNotifyOptions): Promise<void>;
	/**
	 * Record that the human just interacted: resets the silence timer and
	 * clears announced attention keys. Extensions should call this from their
	 * own user-interaction signals (herald.ts calls it on the `input` event).
	 */
	touch(): void;
	/** Ms since the last touch(), or null if none this session. */
	msSinceTouch(): number | null;
	/**
	 * It's the human's turn: they need to come make a decision. Fires only if
	 * the silence timer has elapsed (or force) and this key hasn't already
	 * been announced since the last touch(). Returns true if a notification
	 * was sent. Best-effort: never throws.
	 */
	requestAttention(pi: ExtensionAPI, opts: HeraldAttentionOptions): Promise<boolean>;
	/** True if the user appears to be looking at this pi instance. */
	isUserLooking(pi: ExtensionAPI): Promise<boolean>;
	/** Append to the shared herald log. Best-effort. */
	log(msg: string): void;
}

function log(msg: string): void {
	try {
		appendFileSync(LOG, `${new Date().toISOString()} ${msg}\n`);
	} catch {
		// best-effort
	}
}

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

/** Target our own tmux pane explicitly, for accurate session/window info. */
async function getTmuxInfo(pi: ExtensionAPI): Promise<string> {
	// Without `-t`, display-message resolves formats against the client's
	// *active* pane (whatever the user is looking at), so window/session would
	// reflect the wrong window when the user has switched away from this pi.
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

async function notify(pi: ExtensionAPI, opts: HeraldNotifyOptions): Promise<void> {
	if (!opts.force) {
		const looking = await isUserLooking(pi);
		log(`focus check: looking=${looking} display=${displayKind()}`);
		if (looking) {
			log(`suppressed: ${opts.title}`);
			return;
		}
	}
	const tmuxInfo = await getTmuxInfo(pi);
	const body = `${opts.body}${tmuxInfo}`;
	try {
		await pi.exec("herald", [
			"message",
			"--title",
			opts.title,
			"--sound",
			"--tag",
			"pi",
			"--tag",
			"work_done",
			body,
		]);
		log(`notified: ${body}`);
	} catch (e) {
		log(`herald failed: ${e instanceof Error ? e.message : String(e)}`);
	}
}

// Human-turn state. Belongs to the single globalThis-shared instance, so
// every extension copy sees the same timer and announced-key set.
let lastTouch: number | null = null;
const announcedKeys = new Set<string>();

async function requestAttention(pi: ExtensionAPI, opts: HeraldAttentionOptions): Promise<boolean> {
	const threshold = opts.thresholdMs ?? DEFAULT_THRESHOLD_MS;
	const elapsed = lastTouch == null ? null : Date.now() - lastTouch;
	const silentLongEnough = opts.force || elapsed == null || elapsed > threshold;
	if (!silentLongEnough) {
		log(`attention suppressed (recent touch, ${elapsed}ms): ${opts.key}`);
		return false;
	}
	if (!opts.force && announcedKeys.has(opts.key)) {
		log(`attention suppressed (already announced): ${opts.key}`);
		return false;
	}
	if (!opts.force) announcedKeys.add(opts.key);
	await notify(pi, { title: opts.title, body: opts.body, force: opts.force });
	return true;
}

const lib: HeraldLib = {
	notify,
	touch: () => {
		lastTouch = Date.now();
		announcedKeys.clear();
	},
	msSinceTouch: () => (lastTouch == null ? null : Date.now() - lastTouch),
	requestAttention,
	isUserLooking,
	log,
};

/**
 * Get the shared herald lib. Consumers import this from "./herald"; that
 * loads a second copy of this module, but every copy reaches the same
 * instance via the `globalThis` slot. See the file header.
 */
export function getHerald(): HeraldLib {
	// eslint-disable-next-line @typescript-eslint/no-explicit-any
	const g = globalThis as { [key: string]: any };
	if (!g[LIB_KEY]) g[LIB_KEY] = lib;
	return g[LIB_KEY] as HeraldLib;
}

// ── Extension: turn-end notifications ─────────────────────────────────────

const HEAVY_TOOLS: string[] = [];

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

// Shape of the agent_end event payload (cast locally to avoid importing the
// full internal message types).
type AgentEndEventLike = {
	messages?: Array<{ role?: string; stopReason?: string; errorMessage?: string }>;
};

export default function (pi: ExtensionAPI) {
	const herald = getHerald();
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
		usedHeavyTool = false;
		lastStopReason = null;
		lastErrorMessage = null;
	}

	function describeError(msg: string | null): string {
		if (!msg) return "unknown error";
		const s = String(msg).replace(/\s+/g, " ").trim();
		return s.length > 120 ? s.slice(0, 117) + "…" : s;
	}

	pi.on("input", async () => {
		// The human just had their turn: reset the shared silence timer and
		// clear announced attention keys.
		herald.touch();
		usedHeavyTool = false;
		lastStopReason = null;
		lastErrorMessage = null;
		herald.log("input received");
	});

	pi.on("tool_call", async (event) => {
		const name = (event as { toolName?: string }).toolName;
		if (name && HEAVY_TOOLS.includes(name)) {
			usedHeavyTool = true;
			herald.log(`heavy tool used: ${name}`);
		}
	});

	// Capture the outcome of each agent-core run. Fires before every automatic
	// retry too, so we only record state here — never notify.
	pi.on("agent_end", async (event) => {
		const messages = (event as unknown as AgentEndEventLike)?.messages ?? [];
		const lastAssistant = [...messages].reverse().find((m) => m?.role === "assistant");
		lastStopReason = (lastAssistant?.stopReason as string | undefined) ?? null;
		lastErrorMessage = (lastAssistant?.errorMessage as string | undefined) ?? null;
		herald.log(`agent_end: stopReason=${lastStopReason}`);
	});

	// The turn has fully settled: no automatic retry, compaction, or queued
	// continuation will run. This is the one reliable "the user should come back
	// now" moment — agent_end fires mid-retry, agent_settled does not.
	pi.on("agent_settled", async () => {
		herald.log(`agent_settled (lastStopReason=${lastStopReason}, usedHeavyTool=${usedHeavyTool})`);
		// Manual abort — don't bother the user.
		if (lastStopReason === "aborted") {
			herald.log("suppressing notification: turn aborted");
			reset();
			return;
		}
		const durationMs = herald.msSinceTouch();
		const duration = durationMs != null && durationMs > 0 ? formatDuration(durationMs) : "";
		// Turn died on an error after exhausting all retries: report it honestly
		// instead of "done".
		const isError = lastStopReason === "error";
		await herald.requestAttention(pi, {
			key: "turn-settled",
			// A heavy tool made the turn loud enough to warrant a ping regardless
			// of how long it took.
			thresholdMs: usedHeavyTool ? 0 : undefined,
			title: isError ? "Human, I hit an error 🫠" : "Human, I am done 🥹",
			body: `${isError ? "Failed" : "Done"}${duration ? ` (${duration})` : ""}${
				isError ? ` — ${describeError(lastErrorMessage)}` : ""
			}`,
		});
		reset();
	});
}
