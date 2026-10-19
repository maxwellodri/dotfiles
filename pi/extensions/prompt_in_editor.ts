/**
 * prompt_in_editor.ts — C-x e: open the prompt in pi's native external
 * editor (the Ctrl+G feature). Registered through leader-key's globalThis
 * registry (moduleCache disabled — see leader-key.ts).
 */
import type { AppKeybinding, ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { getLeaderRegistry } from "./leader-key";

const BINDING_KEY = "e";
const EXTERNAL_EDITOR_ACTION: AppKeybinding = "app.editor.external";

export default function (pi: ExtensionAPI) {
	pi.on("session_start", () => {
		getLeaderRegistry().register(BINDING_KEY, {
			description: "Open the prompt in an external editor",
			handler: (ctx) => ctx.invokeAppAction(EXTERNAL_EDITOR_ACTION),
		});
	});

	pi.on("session_shutdown", () => {
		getLeaderRegistry().unregister(BINDING_KEY);
	});
}
