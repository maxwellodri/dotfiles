/**
 * leader-key.ts — tmux-style C-x prefix (leader key) for pi's prompt.
 *
 * This is the shared leader-key HOST. It owns the prompt (it is the one
 * CustomEditor that may replace pi's input) and dispatches the key pressed
 * right after C-x to whatever binding is registered for it.
 *
 * Bindings are NOT hard-coded here — other extensions register them:
 *
 *   import { getLeaderRegistry, type LeaderCtx } from "./leader-key";
 *   getLeaderRegistry().register("u", {
 *     description: "Undo to prior turn",
 *     handler: (ctx: LeaderCtx) => ctx.submit("/undo"),
 *   });
 *
 *   e  open the prompt in $EDITOR      → prompt_in_editor.ts
 *   u  undo to prior turn              → undo.ts
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
 * pi's shared event bus (`pi.events.emit("leader-key:state", boolean)`) so a
 * separate footer extension can render an indicator without any direct
 * coupling — see footer.ts. The two are independent: disable either one and
 * the other still works.
 *
 * ── Why globalThis instead of a normal import? ──────────────────────────
 * pi loads every extension with jiti `{ moduleCache: false }`, so each
 * extension module is evaluated in its own module graph. A plain
 * `import { registry } from "./leader-key"` from undo.ts would load a SECOND
 * copy of this file with its own, separate state — the two copies would never
 * share the same map. `globalThis`, by contrast, is the single realm-global
 * shared by every module in the process, so stashing the registry there is the
 * simplest ordering-independent way to share it. (pi's `pi.events` bus is the
 * other supported cross-extension channel; we use that for the armed/idle
 * indicator so footer.ts can render it.)
 *
 * Lifecycle: the registry is cleared on `session_shutdown` (ordering-safe:
 * shutdown handlers all run before any session_start) and re-populated by
 * binding extensions in their own `session_start`. Dispatch reads the registry
 * lazily at keypress, so it does not matter which extension's session_start
 * runs first.
 *
 * Load: auto-discovered from pi/extensions/*.ts (= ~/.pi/agent/extensions);
 * `/reload` after edits. Only ONE custom editor may own the prompt at a time
 * (conflicts with e.g. pi-vim-keys).
 */
import { CustomEditor, type ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { matchesKey } from "@earendil-works/pi-tui";

const LEADER_KEY = "ctrl+x";
/** Event-bus channel carrying the armed/idle state to footer.ts. */
const STATE_CHANNEL = "leader-key:state";
/** globalThis slot under which the shared binding registry lives. */
const REGISTRY_KEY = "__piLeaderKey";

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
