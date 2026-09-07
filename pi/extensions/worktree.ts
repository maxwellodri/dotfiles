/**
 * worktree.ts — /worktree <subcommand> for pi, on top of set-cwd.ts.
 *
 * Flow:
 *   /worktree [ls]      list worktrees (default when no subcommand given)
 *   /worktree go <n>    go to worktree <git-root>/<n> on branch <n> (created
 *                       if missing), carrying the session there via
 *                       getCwdApi().setCwd().
 *   /worktree merge     ONLY valid inside a worktree: merge the worktree
 *                       branch into the main checkout's branch, then carry
 *                       the session back to the main root. On conflicts,
 *                       report "N merge conflicts: file:line, …" and carry
 *                       the session back anyway so the agent resolves them.
 *   /worktree delete [n] delete worktree <n> (branch kept) from anywhere —
 *                       or the current worktree when unnamed, carrying the
 *                       session back to the main root, preflighted BEFORE
 *                       `git worktree remove` (a failed carry after removal
 *                       strands the session in a dead cwd).
 *
 * Conventions:
 *   - main root = parent of the git common dir (<root>/.git), i.e. the
 *     primary checkout; worktrees are siblings of .git: <root>/<name>.
 *   - branch name == worktree name.
 *   - merge target = whatever branch the main checkout has checked out
 *     (usually main/master); reported in the notify.
 *   - branches are never deleted by this extension; /worktree delete keeps
 *     the branch (drop it manually with git branch -d <name>).
 *
 * Guards:
 *   - merge refuses outside a linked worktree, on a detached HEAD, with
 *     uncommitted changes in the worktree, or when the main checkout is dirty.
 *   - delete refuses on uncommitted changes in the target worktree, and
 *     requires a name when run outside any worktree.
 *
 * Git helpers are pure functions over an exec fn so they can be tested
 * against a real repo without a live pi (see /tmp/worktree-smoke.mjs).
 * The setCwd import loads a second module copy of set-cwd.ts (pi disables
 * jiti's moduleCache); getCwdApi() still returns the one shared api object
 * because it lives on globalThis — see set-cwd.ts.
 *
 * Load: auto-discovered from pi/extensions/*.ts; /reload after edits.
 */
import type { ExtensionAPI, ExtensionCommandContext } from "@earendil-works/pi-coding-agent";
import { Text } from "@earendil-works/pi-tui";
import { getCwdApi } from "./set-cwd";
import type { ReplacementCtx } from "./set-cwd";
import { appendFileSync, existsSync, mkdirSync, readFileSync, realpathSync } from "node:fs";
import { dirname, join, resolve } from "node:path";

/** Minimal exec surface (pi.exec shaped) so helpers stay testable. */
export type ExecFn = (
	command: string,
	args: string[],
	options?: { cwd?: string; timeout?: number },
) => Promise<{ stdout: string; stderr: string; code: number }>;

async function run(exec: ExecFn, cwd: string, args: string[]): Promise<{ code: number; stdout: string; stderr: string }> {
	return exec("git", args, { cwd, timeout: 30_000 });
}

/** Absolute .git common dir (<main-root>/.git), or null outside a repo. */
export async function commonDir(exec: ExecFn, cwd: string): Promise<string | null> {
	const r = await run(exec, cwd, ["rev-parse", "--path-format=absolute", "--git-common-dir"]);
	if (r.code !== 0) return null;
	return resolve(r.stdout.trim());
}

/** Absolute git dir; differs from commonDir() inside a linked worktree. */
export async function gitDir(exec: ExecFn, cwd: string): Promise<string | null> {
	const r = await run(exec, cwd, ["rev-parse", "--path-format=absolute", "--git-dir"]);
	if (r.code !== 0) return null;
	return resolve(r.stdout.trim());
}

/** Main checkout root (parent of the common dir). */
export function mainRoot(common: string): string {
	return dirname(common);
}

export async function currentBranch(exec: ExecFn, cwd: string): Promise<string> {
	const r = await run(exec, cwd, ["branch", "--show-current"]);
	return r.code === 0 ? r.stdout.trim() : "";
}

export async function isDirty(exec: ExecFn, cwd: string): Promise<string[]> {
	const r = await run(exec, cwd, ["status", "--porcelain"]);
	if (r.code !== 0) return [];
	return r.stdout.split("\n").filter(Boolean);
}

export interface WorktreeInfo {
	/** Main checkout root. */
	root: string;
	/** This worktree's absolute path (== cwd). */
	path: string;
	/** Worktree name (basename of path). */
	name: string;
	/** Branch checked out here ("" if detached). */
	branch: string;
}

/** Describe the worktree containing `cwd`; null in the main checkout. */
export async function detectWorktree(exec: ExecFn, cwd: string): Promise<WorktreeInfo | null> {
	const [common, dir] = await Promise.all([commonDir(exec, cwd), gitDir(exec, cwd)]);
	if (!common || !dir || common === dir) return null;
	return {
		root: mainRoot(common),
		path: resolve(cwd),
		name: resolve(cwd).split("/").pop() ?? "",
		branch: await currentBranch(exec, cwd),
	};
}

/** Absolute paths of every worktree of the repo containing `cwd`. */
export async function worktreePaths(exec: ExecFn, cwd: string): Promise<string[]> {
	const r = await run(exec, cwd, ["worktree", "list", "--porcelain"]);
	if (r.code !== 0) return [];
	return r.stdout
		.split("\n")
		.filter((l) => l.startsWith("worktree "))
		.map((l) => resolve(l.slice("worktree ".length)));
}

/**
 * Ensure worktree <root>/<name> exists with branch <name> checked out.
 * Creates `git worktree add -b <name>` (or checks out an existing branch);
 * skips creation entirely when the directory already exists — but errors if
 * that directory is not a worktree of the same repository.
 * Also anchors `<name>/` in <root>/.git/info/exclude so the main checkout's
 * git status never shows sibling worktrees as untracked.
 * Returns the worktree path.
 */
export async function ensureWorktree(exec: ExecFn, root: string, name: string): Promise<string> {
	const target = join(root, name);
	if (existsSync(target)) {
		const [targetCommon, rootCommon] = await Promise.all([commonDir(exec, target), commonDir(exec, root)]);
		if (!targetCommon || targetCommon !== rootCommon) {
			throw new Error(`${target} exists but is not a worktree of this repository`);
		}
		await excludeWorktree(exec, root, name);
		return target;
	}
	const branchExists = await run(exec, root, ["show-ref", "verify", "--quiet", `refs/heads/${name}`]);
	const args = branchExists.code === 0
		? ["worktree", "add", target, name]
		: ["worktree", "add", "-b", name, target];
	const r = await run(exec, root, args);
	if (r.code !== 0) throw new Error(`git worktree add failed: ${r.stderr.trim()}`);
	await excludeWorktree(exec, root, name);
	return target;
}

/** Anchor `/<name>/` in <root>/.git/info/exclude (idempotent). */
async function excludeWorktree(exec: ExecFn, root: string, name: string): Promise<void> {
	const common = await commonDir(exec, root);
	if (!common) return;
	const exclude = join(common, "info", "exclude");
	const entry = `/${name}/`;
	mkdirSync(dirname(exclude), { recursive: true });
	if (!existsSync(exclude) || !readFileSync(exclude, "utf8").split("\n").includes(entry)) {
		appendFileSync(exclude, `${entry}\n`, "utf8");
	}
}

export interface MergeOutcome {
	status: "clean" | "conflicts" | "failed";
	/** Merge target branch in the main checkout. */
	targetBranch: string;
	/** For conflicts: file:line entries at each conflict marker. */
	conflicts: string[];
	stderr: string;
}

/**
 * Merge the worktree branch into the main checkout's current branch.
 * Runs in <root>; the caller is expected to already hold the worktree guard.
 */
export async function mergeWorktree(exec: ExecFn, root: string, branch: string): Promise<MergeOutcome> {
	const targetBranch = await currentBranch(exec, root);
	if (!targetBranch) throw new Error(`main checkout (${root}) is on a detached HEAD`);

	const r = await run(exec, root, ["merge", "--no-edit", branch]);
	if (r.code === 0) {
		return { status: "clean", targetBranch, conflicts: [], stderr: "" };
	}

	const unmerged = await run(exec, root, ["diff", "--name-only", "--diff-filter=U"]);
	if (r.code !== 0 && unmerged.code === 0 && unmerged.stdout.trim() === "") {
		return { status: "failed", targetBranch, conflicts: [], stderr: r.stderr.trim() };
	}

	const conflicts: string[] = [];
	for (const file of unmerged.stdout.split("\n").filter(Boolean)) {
		let text: string;
		try {
			text = readFileSync(join(root, file), "utf8");
		} catch {
			conflicts.push(`${file}:?`);
			continue;
		}
		for (const [i, line] of text.split("\n").entries()) {
			if (line.startsWith("<<<<<<<")) conflicts.push(`${file}:${i + 1}`);
		}
	}
	return { status: "conflicts", targetBranch, conflicts, stderr: r.stderr.trim() };
}

/** Compact `git worktree list` for the no-argument /worktree listing. */
export async function listWorktrees(exec: ExecFn, cwd: string): Promise<string> {
	const r = await run(exec, cwd, ["worktree", "list"]);
	return r.code === 0 ? r.stdout.trim() : "";
}

/** Remove the worktree at `path` (must be clean). Branch survives. */
export async function deleteWorktree(exec: ExecFn, root: string, path: string): Promise<void> {
	const r = await run(exec, root, ["worktree", "remove", path]);
	if (r.code !== 0) throw new Error(`git worktree remove failed: ${r.stderr.trim()}`);
}

const NAME_RE = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;

/** Where announcements land in the TUI/model. */
const MESSAGE_TYPE = "worktree";

interface Announcement {
	/** Short TUI line. */
	tui: string;
	/** Fuller sentence for model context. */
	model: string;
}

/** Minimal surface needed to send an announcement: the extension api (pi,
 * before any switch) or the replacement ctx inside afterSwitch. */
type Sender = {
	sendMessage(
		message: { customType: string; content: string; display: boolean; details?: unknown },
		options?: { triggerTurn?: boolean },
	): Promise<void> | void;
};

/**
 * Announce through the LIVE session's sendMessage with triggerTurn:false.
 * While idle this persists a custom_message entry, pushes it into agent
 * state, and emits message_start/message_end — so the card renders in the
 * TUI immediately and the model sees it on the NEXT turn, while NO agent
 * turn is started (the user keeps their prompt for follow-up work).
 * Raw sessionManager.appendCustomMessageEntry persists but emits nothing
 * and skips agent state: no card now, and the entry only reaches the model
 * if a later resync (e.g. compaction) picks it up. (pi.sendMessage called
 * BEFORE the switch is equally dead: nextTurn queues do not survive the
 * session rebind, and steer/followUp with triggerTurn hijacks the turn —
 * announceAfter instead uses rctx.sendMessage, bound to the replacement
 * session.)
 */
async function announce(sender: Sender, a: Announcement): Promise<void> {
	await sender.sendMessage(
		{ customType: MESSAGE_TYPE, content: a.model, display: true, details: { tui: a.tui } },
		{ triggerTurn: false },
	);
}

/** afterSwitch wrapper: announce from the replacement session. */
function announceAfter(a: Announcement): (rctx: ReplacementCtx) => Promise<void> {
	return async (rctx) => {
		await announce(rctx, a);
	};
}

export default function (pi: ExtensionAPI) {
	/** exec bound to pi for use inside command handlers. */
	const exec: ExecFn = (command, args, options) => pi.exec(command, args, options);

	// Tell the model where it is: pi's system prompt carries only
	// "Current working directory: <cwd>" — nothing about the worktree or
	// the main root. Static metadata only; dirty state goes
	// stale instantly and the model can run git status itself.
	pi.on("before_agent_start", async (event) => {
		const wt = await detectWorktree(exec, event.systemPromptOptions.cwd);
		if (!wt) return;
		const mainBranch = await currentBranch(exec, wt.root);
		return {
			systemPrompt:
				event.systemPrompt +
				`\nGit worktree: "${wt.name}" on branch "${wt.branch}" of the repo rooted at ${wt.root} (main checkout, branch ${mainBranch || "?"}).`,
		};
	});

	// TUI rendering for the announcement cards ("Swapped to worktree X").
	pi.registerMessageRenderer(MESSAGE_TYPE, (message, _options, theme) => {
		const detail = (message.details as { tui?: string } | undefined)?.tui;
		const fallback = typeof message.content === "string"
			? message.content
			: message.content.map((c) => (c.type === "text" ? c.text : "")).join("");
		return new Text(`${theme.fg("accent", "⎇ worktree")} ${theme.fg("text", detail ?? fallback)}`, 0, 0);
	});

	/** /worktree go <name> — ensure worktree exists, carry session into it. */
	const cmdNew = async (ctx: ExtensionCommandContext, name: string): Promise<void> => {
		if (!name) {
			await ctx.ui.notify("usage: /worktree go <name>", "error");
			return;
		}
		if (!NAME_RE.test(name)) {
			await ctx.ui.notify(`invalid worktree name: ${name}`, "error");
			return;
		}
		const common = await commonDir(exec, ctx.cwd);
		if (!common) {
			await ctx.ui.notify(`not a git repository: ${ctx.cwd}`, "error");
			return;
		}
		try {
			const target = await ensureWorktree(exec, mainRoot(common), name);
			const r = await getCwdApi().setCwd(ctx, target, {
				message: false,
				afterSwitch: announceAfter({
					tui: `Swapped to worktree ${name}`,
					model: `The user swapped to worktree ${name} on branch ${name} in directory ${target}`,
				}),
			});
			if (r === "cancelled") {
				// Safe to use pi here: a cancelled switch never replaced the session.
				await announce(pi, {
					tui: `Worktree ${name} ready at ${target}; switch cancelled`,
					model: `The user created worktree ${name} at ${target} but cancelled switching to it`,
				});
			}
		} catch (error) {
			await ctx.ui.notify(error instanceof Error ? error.message : String(error), "error");
		}
	};

	/** /worktree merge — merge this worktree's branch into main, carry back. */
	const cmdMerge = async (ctx: ExtensionCommandContext): Promise<void> => {
		const wt = await detectWorktree(exec, ctx.cwd);
		if (!wt) {
			await ctx.ui.notify("not in a git worktree — /worktree merge only works from a worktree", "error");
			return;
		}
		if (!wt.branch) {
			await ctx.ui.notify("worktree is on a detached HEAD — commit/branch first", "error");
			return;
		}
		const dirty = await isDirty(exec, ctx.cwd);
		if (dirty.length > 0) {
			const files = dirty.slice(0, 10).map((l) => l.slice(3)).join(", ");
			await ctx.ui.notify(`worktree has uncommitted changes (${dirty.length}): ${files}`, "error");
			return;
		}
		// Untracked worktree siblings are excluded via info/exclude, but
		// worktrees created before that exclusion (or by other tools) would
		// otherwise trip this guard — filter known worktree paths out.
		const wtDirs = new Set((await worktreePaths(exec, ctx.cwd)).map((p) => `${p.split("/").pop()}/`));
		const mainDirty = (await isDirty(exec, wt.root)).filter(
			(l) => !(l.startsWith("?? ") && wtDirs.has(l.slice(3))),
		);
		if (mainDirty.length > 0) {
			const files = mainDirty.slice(0, 10).map((l) => l.slice(3)).join(", ");
			await ctx.ui.notify(`main checkout is dirty (${mainDirty.length}): ${files} — settle it first`, "error");
			return;
		}
		try {
			const outcome = await mergeWorktree(exec, wt.root, wt.branch);
			if (outcome.status === "failed") {
				await ctx.ui.notify(`merge failed: ${outcome.stderr || "unknown git error"}`, "error");
				return;
			}
			const announcement: Announcement = outcome.status === "clean"
				? {
					tui: `Merged ${wt.name} into ${outcome.targetBranch}`,
					model: `The user merged worktree ${wt.name} (branch ${wt.branch}) into branch ${outcome.targetBranch} and moved the session back to the main checkout at ${wt.root}`,
				}
				: {
					tui: `${outcome.conflicts.length} merge conflict${outcome.conflicts.length === 1 ? "" : "s"} — back in main to resolve`,
					model: `The user merged worktree ${wt.name} (branch ${wt.branch}) into branch ${outcome.targetBranch}; there ${outcome.conflicts.length === 1 ? "was 1 merge conflict" : `were ${outcome.conflicts.length} merge conflicts`} at ${outcome.conflicts.join(", ")}. The session moved back to the main checkout at ${wt.root} to resolve them`,
				};
			// Carry the session back to main either way (conflicts are
			// resolved there). Old ctx is dead after a successful switch —
			// announcements ride inside setCwd's afterSwitch.
			const r = await getCwdApi().setCwd(ctx, wt.root, {
				message: false,
				afterSwitch: announceAfter(announcement),
			});
			if (r === "cancelled") {
				// Safe to use pi here: a cancelled switch never replaced the session.
				await announce(pi, announcement);
			}
		} catch (error) {
			await ctx.ui.notify(error instanceof Error ? error.message : String(error), "error");
		}
	};

	/** /worktree delete [name] — delete a worktree: named from anywhere, or
	 * the current one (session carried back to main first). */
	const cmdDelete = async (ctx: ExtensionCommandContext, nameArg: string): Promise<void> => {
		const canonical = (p: string): string => {
			try {
				return realpathSync(p);
			} catch {
				return resolve(p);
			}
		};
		const common = await commonDir(exec, ctx.cwd);
		if (!common) {
			await ctx.ui.notify(`not a git repository: ${ctx.cwd}`, "error");
			return;
		}
		const root = mainRoot(common);

		// Resolve the target: explicit name/path, else the worktree we're in.
		let targetPath: string;
		let targetName: string;
		if (nameArg) {
			const match = (await worktreePaths(exec, ctx.cwd)).find(
				(p) => p.split("/").pop() === nameArg || canonical(p) === canonical(nameArg),
			);
			if (!match) {
				await ctx.ui.notify(`no worktree '${nameArg}' — /worktree ls lists them`, "error");
				return;
			}
			targetPath = canonical(match);
			targetName = match.split("/").pop() ?? match;
		} else {
			const wt = await detectWorktree(exec, ctx.cwd);
			if (!wt) {
				await ctx.ui.notify(
					"not in a git worktree — name one (/worktree delete <name>) or run from inside it",
					"error",
				);
				return;
			}
			targetPath = wt.path;
			targetName = wt.name;
		}

		// Deleting the worktree the session lives in needs the carry-back
		// dance; deleting a sibling only needs git.
		const here = canonical(ctx.cwd);
		if (here !== targetPath && !here.startsWith(`${targetPath}/`)) {
			const dirty = await isDirty(exec, targetPath);
			if (dirty.length > 0) {
				const files = dirty.slice(0, 10).map((l) => l.slice(3)).join(", ");
				await ctx.ui.notify(`worktree ${targetName} has uncommitted changes (${dirty.length}): ${files} — commit or stash first`, "error");
				return;
			}
			try {
				await deleteWorktree(exec, root, targetPath);
				await announce(pi, {
					tui: `Deleted worktree ${targetName}`,
					model: `The user deleted worktree ${targetName} (branch kept); the session stayed where it is`,
				});
			} catch (error) {
				await ctx.ui.notify(error instanceof Error ? error.message : String(error), "error");
			}
			return;
		}

		const wt = await detectWorktree(exec, ctx.cwd);
		const backTo = wt?.root ?? root;
		const dirty = await isDirty(exec, ctx.cwd);
		if (dirty.length > 0) {
			const files = dirty.slice(0, 10).map((l) => l.slice(3)).join(", ");
			await ctx.ui.notify(`worktree has uncommitted changes (${dirty.length}): ${files} — commit or stash first`, "error");
			return;
		}
		try {
			// Preflight the carry BEFORE removing the worktree: if the
			// source session is unreadable, prepareCwd throws while the
			// cwd still exists — a stranded session can't even run tools
			// to fix itself (learned the hard way: headerless session file
			// + removed worktree = dead pi). If the removal itself then
			// fails, only a stray prepared target remains (harmless).
			const api = getCwdApi();
			// Old module copies on globalThis may lack prepareCwd; fall
			// back to the risky order rather than failing the command.
			const preallocated = typeof api.prepareCwd === "function"
				? await api.prepareCwd(ctx, backTo)
				: undefined;
			// Remove BEFORE switching: pi's bash tool still runs with cwd
			// inside the worktree, and git wants it gone in one piece.
			await deleteWorktree(exec, backTo, targetPath);
			const r = await api.setCwd(ctx, backTo, {
				message: false,
				...(preallocated ? { preallocatedSession: preallocated } : {}),
				afterSwitch: announceAfter({
					tui: `Deleted worktree ${targetName} — back in main`,
					model: `The user deleted worktree ${targetName} (branch ${wt?.branch || "(detached)"} was kept) and moved the session back to the main checkout at ${backTo}`,
				}),
			});
			if (r === "cancelled") {
				// Safe to use pi here: a cancelled switch never replaced the session.
				await announce(pi, {
					tui: `Deleted worktree ${targetName} — switch back cancelled`,
					model: `The user deleted worktree ${targetName} but cancelled switching back to ${backTo}; restart pi there`,
				});
			}
		} catch (error) {
			await ctx.ui.notify(error instanceof Error ? error.message : String(error), "error");
		}
	};

	pi.registerCommand("worktree", {
		description: "Worktree manager: /worktree [ls] | go <name> | merge | delete [name]",
		handler: async (args, ctx) => {
			const [sub, ...rest] = args.trim().split(/\s+/).filter(Boolean);
			switch (sub) {
				case undefined:
				case "":
				case "ls":
				case "list": {
					const list = await listWorktrees(exec, ctx.cwd);
					await ctx.ui.notify(list || "not a git repository", "info");
				return;
				}
				case "go":
				case "new": // legacy alias
					return cmdNew(ctx, rest.join(" "));
				case "merge":
					return cmdMerge(ctx);
				case "delete":
				case "rm":
					return cmdDelete(ctx, rest.join(" "));
				default:
					await ctx.ui.notify(
						`unknown subcommand '${sub}' — usage: /worktree go <name> | merge | delete [name] | ls`,
						"error",
					);
			}
		},
	});
}
