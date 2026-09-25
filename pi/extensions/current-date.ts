/**
 * current-date.ts — inject the current date into the LLM context on the first
 * prompt of a NEW session only; never on follow-ups, and never when resuming,
 * continuing (-c/--resume), or forking a session that already has history.
 *
 *  • `session_start` arms the injection only when the branch holds no user
 *    messages yet (a genuinely fresh session). A session carrying history
 *    already established its date in-context, so re-injecting after /resume
 *    would duplicate noise.
 *  • Uses `date "+%a %d %b %Y %H:%M %Z"` — HH:MM, no seconds.
 *  • Entry is a custom_message with display:false: persisted in the session
 *    file and sent to the LLM, but never rendered in the TUI.
 *
 * Load: auto-discovered from pi/extensions/*.ts (= ~/.pi/agent/extensions);
 * `/reload` after edits.
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { execSync } from "node:child_process";

const CUSTOM_TYPE = "current-date";

export default function (pi: ExtensionAPI) {
	let armed = false;

	pi.on("session_start", (_event, ctx) => {
		armed = !ctx.sessionManager
			.getBranch()
			.some((entry) => entry.type === "message" && entry.message.role === "user");
	});

	pi.on("before_agent_start", () => {
		if (!armed) return;
		armed = false;

		let now: string;
		try {
			now = execSync('date "+%a %d %b %Y %H:%M %Z"', { encoding: "utf8" }).trim();
		} catch {
			return; // date unspoolable — skip injection rather than fail the prompt
		}

		return {
			message: {
				customType: CUSTOM_TYPE,
				content: `Current date and time: ${now}`,
				display: false,
			},
		};
	});
}
