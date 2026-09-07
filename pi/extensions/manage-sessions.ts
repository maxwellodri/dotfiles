/**
 * manage-sessions.ts — /manage_sessions: bulk session management in $EDITOR.
 *
 * Opens a scratch file in $EDITOR (fallback vim) listing every session of
 * the current git repository's pool (session-pool.ts scope), one per line,
 * most recent first, oil.nvim-style:
 *
 *   /001   2h  hi ⎇papa
 *   /002   3d  any pi plugins that add git worktree support?…
 *
 * The /NNN prefix is the line's identity — oil.nvim does exactly this
 * (cache.format_id + mutator/parser.lua `^/(%d+) (.+)$`), rendered dim so
 * it reads as decoration while surviving every edit. Deleting a line
 * deletes the session file (after ctx.ui.confirm); editing a line's label
 * renames the session (appendSessionInfo; clearing it un-names). Lines
 * starting with # and blank lines are ignored. The CURRENT session's line
 * is marked "·current" and can never be deleted — its live SessionManager
 * would just re-append the file back into existence (this exact incident
 * birthed the guard); it may still be renamed.
 *
 * Editor handoff mirrors prompt_in_editor.ts: tui.stop() → spawn $EDITOR
 * with stdio inherited → tui.start(). The TUI handle comes from
 * leader-key's globalThis slot; this extension is inert without it.
 *
 * Files are unlinked only — session-pool needs no cache invalidation
 * because it re-lists from disk on every /resume.
 *
 * Load: auto-discovered from pi/extensions/*.ts; /reload after edits.
 */
import type { ExtensionAPI, ExtensionCommandContext } from "@earendil-works/pi-coding-agent";
import { SessionManager } from "@earendil-works/pi-coding-agent";
import { spawn } from "node:child_process";
import { mkdirSync, readFileSync, realpathSync, unlinkSync, writeFileSync } from "node:fs";
import { getLeaderRegistry } from "./leader-key";
import { resolve } from "node:path";
import { inScope, repoScope, worktreeTag, type RepoScope } from "./session-pool";

type SessionInfoLike = {
	path: string;
	cwd?: string;
	name?: string;
	firstMessage?: string;
	modified?: Date;
};

/** Compact "since last use" age: 35m, 4h, 2d, 6w, 3mo, 1y. */
function ageLabel(date: Date): string {
	const minutes = Math.max(0, Math.floor((Date.now() - date.getTime()) / 60_000));
	if (minutes < 60) return `${minutes}m`;
	const hours = Math.floor(minutes / 60);
	if (hours < 24) return `${hours}h`;
	const days = Math.floor(hours / 24);
	if (days < 7) return `${days}d`;
	if (days < 30) return `${Math.floor(days / 7)}w`;
	const months = Math.floor(days / 30);
	if (months < 12) return `${months}mo`;
	return `${Math.floor(months / 12)}y`;
}

function displayLabel(s: SessionInfoLike, scope: RepoScope): string {
	const text = (s.name ?? s.firstMessage ?? "").replace(/[\x00-\x1f\x7f]/g, " ").trim();
	const clipped = text.length > 100 ? `${text.slice(0, 99)}…` : text;
	const tag = worktreeTag(s.cwd, scope);
	return tag ? `${clipped || "(no messages)"} ⎇${tag}` : clipped || "(no messages)";
}

interface ManagedSession {
	path: string;
	label: string;
	/** Age column as emitted (stripped from the label on parse-back). */
	age: string;
	/** True for the session this pi is running right now (undeletable). */
	isCurrent: boolean;
}

/** Marker placed after the age column on the current session's line. */
const CURRENT_MARKER = "·current";

/** Canonical path compare (realpath where the file exists, else resolve). */
function sameSessionPath(a: string | undefined, b: string | undefined): boolean {
	if (!a || !b) return false;
	const canon = (p: string): string => {
		try {
			return realpathSync(p);
		} catch {
			return resolve(p);
		}
	};
	return canon(a) === canon(b);
}

/** Build the buffer text; returns it plus the id → session map. */
export function buildBuffer(
	sessions: SessionInfoLike[],
	scope: RepoScope,
	currentFile?: string,
): { text: string; byId: Map<number, ManagedSession> } {
	const byId = new Map<number, ManagedSession>();
	const lines: string[] = [
		`# /manage_sessions — repo ${scope.root} (${sessions.length} sessions)`,
		"# delete a line = delete the session · edit a label = rename · clear a label = un-name",
		`# keep the /NNN id prefix; ${CURRENT_MARKER} sessions are protected from deletion; # lines are ignored`,
		"",
	];
	sessions.forEach((s, i) => {
		const id = i + 1;
		const label = displayLabel(s, scope);
		const age = ageLabel(s.modified ?? new Date(0));
		const isCurrent = sameSessionPath(s.path, currentFile);
		const marker = isCurrent ? ` ${CURRENT_MARKER}` : "";
		lines.push(`/${String(id).padStart(3, "0")}  ${age.padStart(4)}${marker}  ${label}`);
		byId.set(id, { path: s.path, label, age, isCurrent });
	});
	return { text: `${lines.join("\n")}\n`, byId };
}

interface ParseResult {
	kept: Map<number, string>;
	unknownIds: string[];
	malformed: number;
}

/** Parse the edited buffer back into id → label (oil's parser, simplified).
 * The line's original age prefix and ·current marker are stripped, so
 * "clearing a label" (leaving `/003   3d`) reads as empty. */
export function parseBuffer(text: string, byId?: Map<number, ManagedSession>): ParseResult {
	const kept = new Map<number, string>();
	const unknownIds: string[] = [];
	let malformed = 0;
	for (const raw of text.split("\n")) {
		const line = raw.trim();
		if (!line || line.startsWith("#")) continue;
		const m = line.match(/^\/(\d+)\s+(.*)$/);
		if (!m) {
			malformed++;
			continue;
		}
		const id = Number(m[1]);
		let label = m[2].trim();
		const age = byId?.get(id)?.age;
		if (age && (label === age || label.startsWith(`${age} `))) {
			label = label === age ? "" : label.slice(age.length + 1).trim();
		}
		if (label.startsWith(`${CURRENT_MARKER} `)) label = label.slice(CURRENT_MARKER.length + 1).trim();
		else if (label === CURRENT_MARKER) label = "";
		kept.set(id, label);
	}
	return { kept, unknownIds, malformed };
}

async function runManageSessions(args: string, ctx: ExtensionCommandContext): Promise<void> {
	const sessionDir = process.env.PI_CODING_AGENT_SESSION_DIR || ctx.sessionManager.getSessionDir();
	const scope = repoScope(ctx.cwd);
	if (!scope) {
		await ctx.ui.notify(`/manage_sessions needs a git repository (cwd: ${ctx.cwd})`, "error");
		return;
	}

	const all = await SessionManager.listAll(sessionDir);
	const scoped = all
		.filter((s) => inScope(s.cwd, scope))
		.sort((a, b) => (b.modified?.getTime() ?? 0) - (a.modified?.getTime() ?? 0));
	if (scoped.length === 0) {
		await ctx.ui.notify(`no sessions in the ${scope.root} pool`, "info");
		return;
	}

	const tui = getLeaderRegistry().getTui();
	if (!tui) {
		await ctx.ui.notify("/manage_sessions requires leader-key.ts to provide the TUI handle", "error");
		return;
	}

	const dir = "/tmp/pi";
	const tmpFile = `${dir}/manage-sessions-${Date.now()}.txt`;
	const { text, byId } = buildBuffer(scoped, scope, ctx.sessionManager.getSessionFile());
	mkdirSync(dir, { recursive: true });
	writeFileSync(tmpFile, text, "utf8");

	// --- $EDITOR handoff (prompt_in_editor.ts pattern) ---
	tui.stop();
	const editorCmd = args.trim() || process.env.EDITOR || "vim";
	const [editor, ...editorArgs] = editorCmd.split(/\s+/);
	process.stdout.write(`Opening ${editorCmd} ${tmpFile}\nPi resumes when the editor exits.\n`);
	let exitCode: number | null = null;
	try {
		exitCode = await new Promise<number | null>((resolveP) => {
			const child = spawn(editor, [...editorArgs, tmpFile], {
				stdio: "inherit",
				shell: process.platform === "win32",
			});
			child.on("error", () => resolveP(null));
			child.on("close", (code) => resolveP(code));
		});
	} finally {
		tui.start();
		tui.requestRender(true);
	}
	if (exitCode !== 0) {
		await ctx.ui.notify(`editor exited with ${exitCode ?? "error"} — no changes applied`, "warning");
		try {
			unlinkSync(tmpFile);
		} catch { /* ignore */ }
		return;
	}

	// --- apply ---
	const { kept, malformed } = parseBuffer(readFileSync(tmpFile, "utf8"), byId);
	try {
		unlinkSync(tmpFile);
	} catch { /* ignore */ }

	const currentFile = ctx.sessionManager.getSessionFile();
	const toDelete: ManagedSession[] = [];
	const toRename: { s: ManagedSession; label: string }[] = [];
	let skippedCurrent = 0;
	for (const [id, s] of byId) {
		if (!kept.has(id)) {
			// Belt and braces: the buffer marks it ·current AND the delete
			// loop re-checks by canonical path — deleting the live session
			// would strand this pi and regrow a headerless file.
			if (s.isCurrent || sameSessionPath(s.path, currentFile)) {
				skippedCurrent++;
			} else {
				toDelete.push(s);
			}
			continue;
		}
		const label = kept.get(id) ?? "";
		if (label !== s.label) toRename.push({ s, label });
	}

	const parts: string[] = [];
	if (toDelete.length > 0) {
		const preview = toDelete
			.slice(0, 3)
			.map((s) => s.label.slice(0, 40))
			.join(" · ");
		const more = toDelete.length > 3 ? ` (+${toDelete.length - 3} more)` : "";
		const ok = await ctx.ui.confirm(
			"Delete sessions?",
			`${toDelete.length} session file(s) will be permanently deleted:\n${preview}${more}`,
		);
		if (!ok) {
			await ctx.ui.notify("aborted — nothing deleted or renamed", "info");
			return;
		}
		let deleted = 0;
		for (const s of toDelete) {
			try {
				unlinkSync(s.path);
				deleted++;
			} catch {
				// already gone / unreadable: report via count delta
			}
		}
		parts.push(`deleted ${deleted}`);
	}

	let renamed = 0;
	for (const { s, label } of toRename) {
		try {
			// Out-of-band append, same as the picker's rename: the live
			// manager re-reads the name on its next full listing.
			SessionManager.open(s.path, sessionDir).appendSessionInfo(label);
			renamed++;
		} catch {
			// rename failures are non-fatal; count delta reports them
		}
	}
	if (renamed > 0) parts.push(`renamed ${renamed}`);
	if (skippedCurrent > 0) parts.push(`kept current session (undeletable)`);
	if (malformed > 0) parts.push(`${malformed} unparseable line(s) ignored`);

	await ctx.ui.notify(parts.length > 0 ? parts.join(" · ") : "no changes", "info");
}

export default function (pi: ExtensionAPI) {
	pi.registerCommand("manage_sessions", {
		description: "Bulk delete/rename sessions of this repo in $EDITOR (oil.nvim style)",
		handler: (args, ctx) => runManageSessions(args, ctx),
	});
}
