/**
 * current-date.ts — inject `date "+%a %d %b %Y %H:%M %Z"` as a
 * display:false custom_message on the first prompt of a fresh session only;
 * resume/-c/fork never re-injects (history already established the date).
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
