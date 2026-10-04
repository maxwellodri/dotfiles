/**
 * leader-key.ts — tmux-style C-x prefix for pi's prompt. Shared HOST: other
 * extensions register bindings via getLeaderRegistry().register(key, {...}).
 *
 * Semantics: C-x arms with NO timeout; the next key dispatches a bound action
 * or cancels — unknown keys (incl. Escape) are swallowed, never fall through
 * to the editor.
 *
 * Registry lives on globalThis because pi loads extensions with jiti
 * `moduleCache: false`: a plain import of this module would give each
 * importer its own copy with separate state. globalThis is the one realm
 * shared by every module copy. Cleared on session_shutdown, re-populated by
 * binding extensions' session_start; dispatch reads the registry lazily, so
 * handler order never matters. State published as
 * pi.events.emit("leader-key:state", boolean) for indicator rendering.
 */
import { CustomEditor, type ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { matchesKey } from "@earendil-works/pi-tui";

const LEADER_KEY = "ctrl+x";
/** Event-bus channel carrying the armed/idle state. */
const STATE_CHANNEL = "leader-key:state";
/** globalThis slot under which the shared binding registry lives. */
const REGISTRY_KEY = "__piLeaderKey";
const TUI_KEY = "__piLeaderKeyTui";

/** Minimal slice of the TUI that leader bindings need (alt-screen handoff). */
export interface LeaderTui {
	stop(): unknown;
	start(): unknown;
	requestRender(full?: boolean): unknown;
}

/**
 * Context handed to a leader-key binding handler. Built fresh on each dispatch
 * from the editor instance, so bindings never touch the editor directly.
 */
export interface LeaderCtx {
	/** The TUI instance (stop/start/render, e.g. for an alt-screen handoff). */
	tui: LeaderTui;
	/** Current prompt text. */
	getText(): string;
	/** Prompt text with `[paste #N]` markers expanded to their contents. */
	getExpandedText(): string;
	/** Replace the prompt text. */
	setText(text: string): void;
	/**
	 * Submit `text` through pi's normal input path — exactly as if the user had
	 * typed it and pressed Enter. This is what dispatches extension `/commands`
	 * (`pi.sendUserMessage` deliberately skips command handling), so bindings
	 * that need a command — e.g. `/undo`, which uses tree navigation only
	 * available to command handlers — MUST go through here.
	 */
	submit(text: string): void;
	/** Request a re-render of the TUI; pass true for a full repaint. */
	requestRender(full?: boolean): void;
}

/** A binding registered against a single key pressed after the leader. */
export interface LeaderBinding {
	/** Invoked when the bound key is pressed right after C-x. */
	handler: (ctx: LeaderCtx) => void;
	/** Short human description (reserved for a future help/legend overlay). */
	description?: string;
}

/** Process-wide registry of leader-key bindings. */
export interface LeaderRegistry {
	/** Register (or replace) the binding for `key`. */
	register(key: string, binding: LeaderBinding): void;
	/** Remove the binding for `key`, if any. */
	unregister(key: string): void;
	/** Look up the binding for `key`. Used by the leader editor at dispatch. */
	resolve(key: string): LeaderBinding | undefined;
	/** Drop every binding. Used by the host on session_shutdown. */
	clear(): void;
	/**
	 * Publish the live TUI handle so other extensions can suspend the terminal
	 * (alt-screen handoff, e.g. opening $EDITOR from a tool call). Set by the
	 * host's setEditorComponent factory each session; other extensions read it
	 * lazily. stop/start/requestRender only — never draw with it.
	 */
	setTui(tui: LeaderTui): void;
	getTui(): LeaderTui | undefined;
}

/**
 * Get the process-wide leader-key registry.
 *
 * Consumers import this from "./leader-key". That import does load a second
 * copy of this module (pi disables `moduleCache`), but it doesn't matter:
 * the function only reads/writes a `globalThis` slot, so every copy reaches the
 * same registry object. See the file header for the full rationale.
 */
export function getLeaderRegistry(): LeaderRegistry {
	// eslint-disable-next-line @typescript-eslint/no-explicit-any
	const g = globalThis as { [key: string]: any };
	let reg = g[REGISTRY_KEY] as LeaderRegistry | undefined;
	if (!reg) {
		const map = new Map<string, LeaderBinding>();
		reg = {
			register: (key, binding) => {
				map.set(key, binding);
			},
			unregister: (key) => {
				map.delete(key);
			},
			resolve: (key) => map.get(key),
			clear: () => {
				map.clear();
			},
			// The TUI handle lives in its own globalThis slot, not on the
			// registry object: the registry may have been created by an older
			// module copy (pre-setTui) that survives /reload on globalThis, so
			// attaching methods to it can't be relied on. A dedicated slot is
			// version-proof.
			setTui: (tui) => {
				g[TUI_KEY] = tui;
			},
			getTui: () => g[TUI_KEY],
		};
		g[REGISTRY_KEY] = reg;
	}
	return reg;
}

class LeaderKeyEditor extends CustomEditor {
	/** Publishes armed/idle state to the shared event bus. Set by the factory. */
	emit: (armed: boolean) => void = () => {};
	private pending = false;

	handleInput(data: string): void {
		// --- prefix not armed: normal editing, but watch for the leader ---
		if (!this.pending) {
			if (matchesKey(data, LEADER_KEY)) {
				this.pending = true;
				this.emit(true);
				this.tui.requestRender(); // repaint in case a consumer renders the armed state
				return; // swallow C-x
			}
			super.handleInput(data);
			return;
		}

		// --- prefix armed: this key decides it ---
		this.pending = false;
		this.emit(false);
		this.tui.requestRender();

		const binding = getLeaderRegistry().resolve(data);
		if (binding) {
			binding.handler(this.makeCtx());
			return; // bound → swallow
		}
		// unmapped (incl. Escape) → cancel, swallow (tmux-style)
	}

	/** Build the per-dispatch context passed to binding handlers. */
	private makeCtx(): LeaderCtx {
		return {
			tui: this.tui,
			getText: () => this.getText(),
			getExpandedText: () => this.getExpandedText(),
			setText: (text) => this.setText(text),
			submit: (text) => {
				this.onSubmit?.(text);
			},
			requestRender: (full) => this.tui.requestRender(full),
		};
	}
}

export default function (pi: ExtensionAPI) {
	pi.on("session_start", (_event, ctx) => {
		// eslint-disable-next-line @typescript-eslint/no-explicit-any
		ctx.ui.setEditorComponent((tui: any, theme: any, keybindings: any) => {
			// Publish the live TUI handle so other extensions can suspend the
			// terminal (e.g. alt-screen handoff to nvim from a tool call).
			getLeaderRegistry().setTui(tui);
			const ed = new LeaderKeyEditor(tui, theme, keybindings);
			ed.emit = (armed: boolean) => pi.events.emit(STATE_CHANNEL, armed);
			return ed;
		});
	});

	// Drop bindings left over from a previous load/session so disabled
	// extensions don't keep firing. Binding extensions re-register in their own
	// session_start; dispatch reads the registry lazily, so order doesn't matter.
	pi.on("session_shutdown", () => {
		getLeaderRegistry().clear();
	});
}
