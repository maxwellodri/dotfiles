/**
 * tmux_registry.ts — keep ~/.local/state/tmux/pi_registry pointed at this
 * pane's live pi session, for dotfiles snapshot.sh/restore.sh: the registry
 * row (boot:server_pid, TMUX_PANE, session jsonl basename) is joined at
 * snapshot time and lets restore resume the exact conversation.
 *
 * Rows are written only when a session actually exists: pi creates the
 * session lazily on the first message, so launching with a preallocated
 * --session-id (the previous approach) warned on every fresh start. Fires
 * on session_start and before_agent_start (idempotent; the latter covers a
 * session created after startup). Stale rows need no cleanup here —
 * snapshot verifies each row against the pane's process tree.
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { mkdirSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { homedir } from "node:os";

function registryPath(): string {
	const state = process.env.XDG_STATE_HOME ?? join(homedir(), ".local/state");
	return join(state, "tmux", "pi_registry");
}

function serverIdent(): string | undefined {
	// $TMUX = "<socket>,<server_pid>,<session_id>"
	const tmux = process.env.TMUX;
	const pane = process.env.TMUX_PANE;
	if (!tmux || !pane) return undefined;
	const pid = tmux.split(",")[1];
	if (!pid) return undefined;
	try {
		const boot = readFileSync("/proc/sys/kernel/random/boot_id", "utf8").slice(0, 8);
		return `${boot}:${pid}`;
	} catch {
		return undefined;
	}
}

export default function (pi: ExtensionAPI) {
	let lastKey = "";

	const write = (ctx: { sessionManager: { getSessionFile(): string | undefined } }) => {
		const ident = serverIdent();
		const pane = process.env.TMUX_PANE;
		if (!ident || !pane) return;
		const file = ctx.sessionManager.getSessionFile();
		if (!file) return; // no session yet — a later event will fire

		// store the uuid, not the basename: pi --session resolves uuid or
		// path, not bare "<timestamp>_<uuid>.jsonl" filenames
		const uuid = file.split("/").pop()!.replace(/\.jsonl$/, "").split("_").pop()!;
		const key = `${ident}\t${pane}\t${uuid}`;
		if (key === lastKey) return;
		lastKey = key;

		const reg = registryPath();
		try {
			const keep = readFileSync(reg, "utf8")
				.split("\n")
				.filter((l) => l && l !== key && !(l.startsWith(`${ident}\t${pane}\t`)));
			writeFileSync(`${reg}.tmp-${process.pid}`, [...keep, key].join("\n") + "\n");
			renameSync(`${reg}.tmp-${process.pid}`, reg);
		} catch (err) {
			if ((err as NodeJS.ErrnoException).code === "ENOENT") {
				try {
					mkdirSync(dirname(reg), { recursive: true });
					writeFileSync(reg, key + "\n");
				} catch {
					/* best effort */
				}
				return;
			}
			/* best effort — snapshot degrades to a plain shell pane */
		}
	};

	pi.on("session_start", (_event, ctx) => write(ctx));
	pi.on("before_agent_start", (_event, ctx) => write(ctx));
}
