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

	pi.on("agent_end", async () => {
		log(`agent_end fired (lastInputTime=${lastInputTime}, usedHeavyTool=${usedHeavyTool})`);
		if (lastInputTime == null) return;
		const elapsed = Date.now() - lastInputTime;
		const timedOut = elapsed > THRESHOLD;
		if (!timedOut && !usedHeavyTool) {
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
