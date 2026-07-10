/**
 * prompt_in_editor.ts — C-x e : open the prompt in $EDITOR.
 *
 * Hands the current prompt text to $EDITOR (fallback vim) via
 * /tmp/pi/<file>.md and copies the contents back when the editor exits.
 * Mirrors pi's built-in external-editor handoff (see extension-editor.js).
 *
 * Depends on leader-key.ts (the leader host). The `e` binding is registered
 * through the globalThis registry rather than an import because pi loads
 * extensions with `moduleCache` disabled — a shared import would give each
 * extension its own copy of the registry. See leader-key.ts for the full
 * rationale.
 *
 * Load: auto-discovered from pi/extensions/*.ts; `/reload` after edits.
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { spawn } from "node:child_process";
import * as fs from "node:fs";
import { getLeaderRegistry, type LeaderCtx } from "./leader-key";

const BINDING_KEY = "e";

export default function (pi: ExtensionAPI) {
	pi.on("session_start", () => {
		getLeaderRegistry().register(BINDING_KEY, {
			description: "Open the prompt in $EDITOR",
			handler: (ctx: LeaderCtx) => {
				void openExternalEditor(ctx);
			},
		});
	});

	pi.on("session_shutdown", () => {
		getLeaderRegistry().unregister(BINDING_KEY);
	});
}

/**
 * Open the prompt in $EDITOR via /tmp/pi/<file>.md; copy back on exit.
 * The caller (leader-key) passes the editor-level context.
 */
async function openExternalEditor(ctx: LeaderCtx): Promise<void> {
	const editorCmd = process.env.EDITOR || "vim";
	const text = ctx.getText();
	const dir = "/tmp/pi";
	const tmpFile = `${dir}/prompt-${Date.now()}.md`;

	try {
		fs.mkdirSync(dir, { recursive: true });
		fs.writeFileSync(tmpFile, text, "utf-8");

		// Release the terminal for the editor. tui.stop() is synchronous, so
		// by the time this (sync) handler returns the TUI is already paused
		// and the child can take over stdin/stdout.
		ctx.tui.stop();

		const [editor, ...editorArgs] = editorCmd.split(" ");
		process.stdout.write(
			`Opening ${editorCmd} ${tmpFile}\nPi resumes when the editor exits.\n`,
		);

		// Not spawnSync: on some platforms a synchronous child_process call
		// keeps libuv's console-input read alive after tui.stop(), racing the
		// editor for the input buffer (same rationale as pi's own code).
		const status = await new Promise<number | null>((resolveP) => {
			const child = spawn(editor, [...editorArgs, tmpFile], {
				stdio: "inherit",
				shell: process.platform === "win32",
			});
			child.on("error", () => resolveP(null));
			child.on("close", (code) => resolveP(code));
		});

		if (status === 0) {
			const content = fs.readFileSync(tmpFile, "utf-8").replace(/\n$/, "");
			ctx.setText(content);
		}
	} catch {
		// best-effort; the finally block resumes the TUI regardless
	} finally {
		try {
			fs.unlinkSync(tmpFile);
		} catch {
			// ignore cleanup errors
		}
		ctx.tui.start();
		ctx.requestRender(true); // full re-render: editor used the alt screen
	}
}
