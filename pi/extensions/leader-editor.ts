/**
 * leader-editor.ts — tmux-style C-x prefix (leader key) for pi's prompt.
 *
 * Behaviour mirrors a tmux prefix:
 *   - C-x arms the prefix. There is NO timeout — it stays armed until the next
 *     key is pressed (pressing nothing does not unset it, just like tmux).
 *   - The next key dispatches a bound action, OR cancels the prefix. Unknown
 *     keys (including Escape) are swallowed — they do NOT fall through to the
 *     editor. Escape while armed only clears the prefix; it does not abort the
 *     agent (plain Escape still aborts when the prefix is not armed).
 *
 * This extension owns the prompt ONLY. Its armed/idle state is published on
 * pi's shared event bus (`pi.events.emit("leader-editor:state", boolean)`) so
 * a separate footer extension can render an indicator without any direct
 * coupling — see footer.ts. The two are independent: disable either one and
 * the other still works (no indicator, or an indicator that stays "N").
 *
 * Bindings (extend handleInput to add more):
 *   C-x e   open the current prompt in $EDITOR via /tmp/pi/<file>.md, then
 *           copy the contents back when the editor exits ($EDITOR, fallback vim).
 *
 * Load: auto-discovered from pi/extensions/*.ts (= ~/.pi/agent/extensions);
 * `/reload` after edits. Only ONE custom editor may own the prompt at a time
 * (conflicts with e.g. pi-vim-keys).
 */
import { CustomEditor, type ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { matchesKey } from "@earendil-works/pi-tui";
import { spawn } from "node:child_process";
import * as fs from "node:fs";

const LEADER_KEY = "ctrl+x";
/** Event-bus channel carrying the armed/idle state to footer.ts. */
const STATE_CHANNEL = "leader-editor:state";

class LeaderEditor extends CustomEditor {
	/** Publishes armed/idle state to the shared event bus. Set by the factory. */
	emit: (armed: boolean) => void = () => {};
	private pending = false;

	handleInput(data: string): void {
		// --- prefix not armed: normal editing, but watch for the leader ---
		if (!this.pending) {
			if (matchesKey(data, LEADER_KEY)) {
				this.pending = true;
				this.emit(true);
				this.tui.requestRender(); // refresh the footer indicator
				return; // swallow C-x
			}
			super.handleInput(data);
			return;
		}

		// --- prefix armed: this key decides it ---
		this.pending = false;
		this.emit(false);
		this.tui.requestRender();

		switch (data) {
			case "e":
				void this.openExternalEditor();
				return; // bound → swallow
			default:
				return; // unmapped (incl. Escape) → cancel, swallow (tmux-style)
		}
	}

	/** Open the prompt in $EDITOR via /tmp/pi/<file>.md; copy back on exit.
	 *  Mirrors pi's built-in external-editor handoff (see extension-editor.js). */
	private async openExternalEditor(): Promise<void> {
		const editorCmd = process.env.EDITOR || "vim";
		const text = this.getText();
		const dir = "/tmp/pi";
		const tmpFile = `${dir}/prompt-${Date.now()}.md`;

		try {
			fs.mkdirSync(dir, { recursive: true });
			fs.writeFileSync(tmpFile, text, "utf-8");

			// Release the terminal for the editor. tui.stop() is synchronous, so
			// by the time this (sync) handleInput returns the TUI is already
			// paused and the child can take over stdin/stdout.
			this.tui.stop();

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
				this.setText(content);
			}
		} catch {
			// best-effort; the finally block resumes the TUI regardless
		} finally {
			try {
				fs.unlinkSync(tmpFile);
			} catch {
				// ignore cleanup errors
			}
			this.tui.start();
			this.tui.requestRender(true); // full re-render: editor used the alt screen
		}
	}
}

export default function (pi: ExtensionAPI) {
	pi.on("session_start", (_event, ctx) => {
		ctx.ui.setEditorComponent((tui: any, theme: any, keybindings: any) => {
			const ed = new LeaderEditor(tui, theme, keybindings);
			ed.emit = (armed: boolean) => pi.events.emit(STATE_CHANNEL, armed);
			return ed;
		});
	});
}
