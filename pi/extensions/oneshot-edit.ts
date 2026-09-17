/**
 * oneshot-edit.ts — loaded ONLY by nvim's pi.lua oneshots (via explicit -e;
 * discovery stays off there). Applies the `edit` tool itself and terminates
 * the turn: the edit is the whole job, so pi must not re-prompt the model
 * after the tool result (saves the wrap-up round trip).
 *
 * This directory is auto-discovered by every regular pi run (wrapper/TUI),
 * so the PI_NVIM_ONESHOT guard keeps those runs untouched — without it this
 * would intercept the first edit of any agentic session and end the turn.
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { readFileSync, writeFileSync } from "node:fs";
import { isAbsolute, resolve } from "node:path";

type EditPair = { oldText?: unknown; newText?: unknown };
type EditInput = { path?: unknown; edits?: unknown };

export default function (pi: ExtensionAPI) {
	if (!process.env.PI_NVIM_ONESHOT) return;
	pi.on("tool_call", async (event) => {
		if (event.toolName !== "edit") return;
		const raw = event.input as EditInput;
		if (typeof raw.path !== "string" || !Array.isArray(raw.edits)) return;

		const abs = isAbsolute(raw.path) ? raw.path : resolve(process.cwd(), raw.path);
		let text: string;
		try {
			text = readFileSync(abs, "utf8");
		} catch (e) {
			return { block: true, reason: `oneshot: cannot read ${abs}: ${String(e)}` };
		}
		for (const pair of raw.edits as EditPair[]) {
			if (typeof pair.oldText !== "string" || typeof pair.newText !== "string") continue;
			const i = text.indexOf(pair.oldText);
			if (i === -1) {
				return { block: true, reason: `oneshot: oldText not found in ${abs}` };
			}
			if (text.indexOf(pair.oldText, i + 1) !== -1) {
				return { block: true, reason: `oneshot: oldText not unique in ${abs}; make it unique` };
			}
			text = text.slice(0, i) + pair.newText + text.slice(i + pair.oldText.length);
		}
		try {
			writeFileSync(abs, text);
		} catch (e) {
			return { block: true, reason: `oneshot: cannot write ${abs}: ${String(e)}` };
		}
		return { block: true, reason: "edit applied", terminate: true };
	});
}
