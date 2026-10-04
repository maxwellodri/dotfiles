/**
 * session-pool.ts — widen /resume "local" from exact-cwd match to same git
 * repo (main checkout, subdirs, linked worktrees; deleted-cwd fallback to
 * "sibling of .git", matching worktree.ts layout). Chain forks from set-cwd
 * swaps hide superseded ancestors (chain collapses to its tip; resume-by-id
 * still finds them) and surviving worktree sessions get a display-only
 * `⎇ name` tag. Patches SessionManager.list/.continueRecent idempotently via
 * a globalThis guard (extensions share core's module instance). Outside a
 * repo, behavior unchanged.
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
