/**
 * afk gate — the timer half of a backlogged message (see core.ts).
 *
 * Idle *measurement* stays in the shell script (scripts/when_afk, on PATH):
 * each poll spawns `bash -c 'source when_afk && afk_idle'` and reads idle ms
 * from stdout. Wayland migration = change afk_idle()'s body in the script;
 * this file is untouched. (Override the script path with $WHEN_AFK_SCRIPT.)
 *
 * Fire semantics mirror the script's main(): poll every 60s; once idle
 * crosses the threshold, re-check after 5s (came-back guard). The gate only
 * decides *when the user is away* — the backlog core still waits for the
 * agent to settle before dispatching.
 */
import { spawn } from "node:child_process";

const SCRIPT = process.env.WHEN_AFK_SCRIPT ?? "when_afk"; // sourced for afk_idle()
const POLL_MS = 60_000; // parity with the script's POLL_INTERVAL (seconds)
const CONFIRM_MS = 5_000; // the script's came-back double-check window
const IDLE_FAIL = "afk_idle() failed — is when_afk on PATH? xidle installed?";

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

/**
 * Arm the gate: onPass() once idle ≥ minutes is confirmed (came-back guard
 * included), onFail(reason) if idle can't be read or activity lands inside
 * the confirm window. Returns the disarm function.
 */
export function armAfkGate(minutes: number, onPass: () => void, onFail: (reason: string) => void): () => void {
	let timer: NodeJS.Timeout | undefined;
	let alive = true;
	const thresholdMs = minutes * 60_000;

	const stop = () => {
		alive = false;
		clearTimeout(timer);
	};

	const confirm = async () => {
		if (!alive) return;
		const idle = await afkIdle();
		if (!alive) return;
		if (idle === null) onFail(IDLE_FAIL);
		else if (idle > thresholdMs) onPass();
		else onFail("activity during confirm window");
	};

	const tick = async () => {
		if (!alive) return;
		const idle = await afkIdle();
		if (!alive) return;
		if (idle === null) onFail(IDLE_FAIL);
		else timer = idle > thresholdMs ? setTimeout(confirm, CONFIRM_MS) : setTimeout(tick, POLL_MS);
	};

	timer = setTimeout(tick, 1_000);
	return stop;
}
