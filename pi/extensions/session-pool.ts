/**
 * session-pool.ts — one session pool per git repository.
 *
 * Problem: pi scopes sessions to the session header's cwd. With a shared
 * session dir (PI_CODING_AGENT_SESSION_DIR) the /resume "local" list
 * filters to sessions whose recorded cwd is EXACTLY the current directory
 * (SessionManager.list → sessionCwdMatches, session-manager.js). Sessions
 * carried into a worktree by set-cwd.ts therefore vanish from /resume the
 * moment you are anywhere else: reopen pi in the main checkout and you
 * only see history up to the first worktree swap. (The picker's "All" tab
 * shows every session of every project — unfiltered noise, not a fix.
 * Neither @narumitw/pi-worktree nor pi-worktrunk addresses this; both stop
 * at fork-and-switch.)
 *
 * Fix: widen "local" to "same repository". While inside a git repo, the
 * local /resume list (and `pi --resume <id>` matching, and `pi -c`)
 * includes every session whose cwd shares this repo's git common dir —
 * main checkout, subdirs, linked worktrees — and, for cwds that no longer
 * exist (deleted worktrees), falls back to "sibling of .git", matching
 * how worktree.ts lays worktrees out as <root>/<name>.
 *
 * Worktree swaps fork a session chain (set-cwd.ts), and every hop leaves
 * a near-identical prefix file behind, all labeled with the same first
 * message. Two presentation fixes ride on the same patch:
 *   - superseded ancestors (untouched since a child forked from them, so
 *     their content is a strict prefix of that child) are hidden from
 *     the local list — a chain collapses to its tip. Resume-by-id still
 *     finds them via the global fallback.
 *   - surviving sessions whose cwd is a worktree (<root>/<name>) get a
 *     display-only `⎇ name` tag, synthesized into SessionInfo.name —
 *     never written to the session files. The picker already re-roots
 *     orphaned tree nodes, so hidden parents render fine.
 *
 * Mechanism: extensions import the SAME in-process module instance as
 * core (the loader's jiti alias resolves @earendil-works/pi-coding-agent
 * to dist/index.js, which native ESM caches once) — verified against the
 * installed package. Patching the static SessionManager.list /
 * .continueRecent here therefore reaches the TUI picker and the CLI.
 * The patch is idempotent via a globalThis guard, so /reload re-running
 * this module (jiti disables its module cache) keeps the original bound
 * reference from the first install.
 *
 * Outside a git repo, or when no session dir is given, behavior is
 * unchanged. Writes are untouched: with PI_CODING_AGENT_SESSION_DIR set,
 * every checkout already persists into the one shared dir.
 *
 * Load: auto-discovered from pi/extensions/*.ts; /reload after edits.
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { SessionManager } from "@earendil-works/pi-coding-agent";
import { execFileSync } from "node:child_process";
import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { dirname, join, resolve } from "node:path";

/** cwd → absolute .git common dir, or null when not a repo. Cached per process. */
const commonDirCache = new Map<string, string | null>();

function commonDirOf(cwd: string): string | null {
	const cached = commonDirCache.get(cwd);
	if (cached !== undefined) return cached;
	let result: string | null = null;
	try {
		const out = execFileSync("git", ["rev-parse", "--path-format=absolute", "--git-common-dir"], {
			cwd,
			timeout: 5000,
			stdio: ["ignore", "pipe", "ignore"],
		});
		const trimmed = out.toString().trim();
		if (trimmed) result = resolve(trimmed);
	} catch {
		// Not a repo (or git failed): null.
	}
	// Never cache answers for directories that do not exist — a worktree
	// recreated at the same path must be re-evaluated.
	if (result !== null || existsSync(cwd)) commonDirCache.set(cwd, result);
	return result;
}

export interface RepoScope {
	/** Absolute .git common dir — the repository identity. */
	common: string;
	/** Main checkout root (parent of the common dir). */
	root: string;
}

/** The repo `cwd` belongs to, or null outside a repository. */
export function repoScope(cwd: string): RepoScope | null {
	const common = commonDirOf(resolve(cwd));
	return common ? { common, root: dirname(common) } : null;
}

/** Does a session recorded at `sessionCwd` belong to `scope`? */
export function inScope(sessionCwd: string | undefined, scope: RepoScope): boolean {
	if (!sessionCwd) return false;
	const c = resolve(sessionCwd);
	const common = commonDirOf(c);
	if (common) return common === scope.common;
	// cwd is gone (deleted worktree): worktrees live as siblings of .git,
	// so a direct child of the repo root is assumed to have been ours.
	return dirname(c) === scope.root;
}

/** Worktree name for a session cwd, or null in the main checkout / subdirs. */
export function worktreeTag(sessionCwd: string | undefined, scope: RepoScope): string | null {
	if (!sessionCwd) return null;
	const c = resolve(sessionCwd);
	return c !== scope.root && dirname(c) === scope.root ? c.slice(scope.root.length + 1) : null;
}

/** Cap a label so the ⎇ tag survives the picker's own truncation. */
function tagLabel(base: string | undefined, tag: string): string {
	const text = (base ?? "").replace(/[\x00-\x1f\x7f]/g, " ").trim() || "(no messages)";
	const clipped = text.length > 60 ? `${text.slice(0, 59)}…` : text;
	return `${clipped} ⎇${tag}`;
}

/**
 * Drop sessions superseded by a fork: a session untouched since a child
 * was created from it (child.created >= parent.modified) is a strict
 * prefix of that child — its row in /resume is pure noise. The parent
 * stays visible whenever it was written to after the fork (unique turns).
 * Display-only; nothing is deleted.
 */
function hideSuperseded(sessions: SessionInfoLike[]): SessionInfoLike[] {
	const byPath = new Map(sessions.map((s) => [resolve(s.path), s]));
	const superseded = new Set<string>();
	for (const child of sessions) {
		if (!child.parentSessionPath) continue;
		const parent = byPath.get(resolve(child.parentSessionPath));
		if (!parent || !child.created || !parent.modified) continue;
		// 1s tolerance for mtime/created granularity.
		if (child.created.getTime() >= parent.modified.getTime() - 1000) {
			superseded.add(parent.path);
		}
	}
	return sessions.filter((s) => !superseded.has(s.path));
}

type Progress = (loaded: number, total: number) => void;
type SessionInfoLike = {
	path: string;
	cwd?: string;
	parentSessionPath?: string;
	created?: Date;
	modified?: Date;
	name?: string;
	firstMessage?: string;
};

type ListFn = (
	cwd: string,
	sessionDir?: string,
	onProgress?: Progress,
) => Promise<SessionInfoLike[]>;

/** globalThis slot marking the installed patch (see set-cwd.ts for the pattern). */
const PATCH_KEY = "__piSessionPool";

/**
 * Most recent session file in `sessionDir` whose header cwd is in `scope`,
 * skipping chain interiors (same supersede rule as hideSuperseded).
 * Sync (continueRecent is sync); mirrors findMostRecentSession's shape.
 */
function mostRecentInScope(sessionDir: string, scope: RepoScope): string | null {
	try {
		const candidates: { path: string; mtime: number; parent?: string; created?: number }[] = [];
		for (const file of readdirSync(sessionDir)) {
			if (!file.endsWith(".jsonl")) continue;
			const path = join(sessionDir, file);
			try {
				const header = JSON.parse(readFileSync(path, "utf8").split("\n", 1)[0] || "{}");
				if (header.type !== "session" || !inScope(header.cwd, scope)) continue;
				const created = header.timestamp ? Date.parse(header.timestamp) : undefined;
				candidates.push({
					path,
					mtime: statSync(path).mtimeMs,
					parent: header.parentSession ? resolve(header.parentSession) : undefined,
					created,
				});
			} catch {
				// Unreadable/oversized/corrupt: not a resume candidate.
			}
		}
		const byPath = new Map(candidates.map((c) => [resolve(c.path), c]));
		const superseded = new Set<string>();
		for (const child of candidates) {
			if (!child.parent) continue;
			const parent = byPath.get(child.parent);
			if (parent && child.created !== undefined && child.created >= parent.mtime - 1000) {
				superseded.add(parent.path);
			}
		}
		const tips = candidates.filter((c) => !superseded.has(c.path));
		tips.sort((a, b) => b.mtime - a.mtime);
		return tips[0]?.path ?? null;
	} catch {
		return null;
	}
}

/** Install the repo-scoped session pool patch (idempotent, /reload-safe). */
export function installSessionPool(): void {
	const g = globalThis as { [key: string]: unknown };
	if (g[PATCH_KEY] === true) return;
	g[PATCH_KEY] = true;

	const sm = SessionManager as unknown as {
		list: ListFn;
		listAll: (sessionDir?: string, onProgress?: Progress) => Promise<SessionInfoLike[]>;
		continueRecent: (cwd: string, sessionDir?: string) => SessionManager;
	};
	const SessionManagerCtor = SessionManager as unknown as new (
		cwd: string,
		sessionDir: string,
		sessionFile: string,
		persisted: boolean,
	) => SessionManager;
	const origList: ListFn = sm.list.bind(SessionManager);
	const origContinue = sm.continueRecent.bind(SessionManager);

	// /resume local tab + `pi --resume <id>`: "same cwd" → "same repo",
	// collapsed to chain tips, worktree sessions tagged `⎇ <name>`.
	sm.list = async (cwd, sessionDir, onProgress) => {
		if (!sessionDir) return origList(cwd, sessionDir, onProgress);
		const scope = repoScope(cwd);
		if (!scope) return origList(cwd, sessionDir, onProgress);
		const all = await sm.listAll(sessionDir, onProgress);
		const local = hideSuperseded(all.filter((s) => inScope(s.cwd, scope)));
		for (const s of local) {
			const tag = worktreeTag(s.cwd, scope);
			if (tag) s.name = tagLabel(s.name ?? s.firstMessage, tag);
		}
		return local;
	};

	// `pi -c`: continue the most recent session of this REPO, not merely
	// of this checkout. Falls back to stock behavior when nothing matches.
	sm.continueRecent = (cwd, sessionDir) => {
		const scope = repoScope(cwd);
		if (!scope || !sessionDir) return origContinue(cwd, sessionDir);
		const mostRecent = mostRecentInScope(sessionDir, scope);
		if (!mostRecent) return origContinue(cwd, sessionDir);
		return new SessionManagerCtor(cwd, sessionDir, mostRecent, true);
	};
}

export default function (_pi: ExtensionAPI) {
	installSessionPool();
}
