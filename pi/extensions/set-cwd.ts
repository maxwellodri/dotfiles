/**
 * set-cwd.ts — a shared setCwd() primitive for pi extensions.
 *
 * pi has no setCwd: the working directory is the session header's cwd, fixed
 * until the session is replaced. The supported way to "cd" a running pi is
 * session surgery — write a session file at the target cwd (carrying the
 * conversation), then switch onto it:
 *
 *   SessionManager.forkFrom(sourceFile, target)  →  ctx.switchSession(file)
 *
 * That is exactly how @narumitw/pi-worktree and pi-worktrunk move pi between
 * worktrees. This extension implements the carry-and-switch logic ONCE and
 * publishes it like leader-key.ts publishes its registry: any extension can
 *
 *   import { getCwdApi } from "./set-cwd";
 *   await getCwdApi().setCwd(ctx, "/abs/path");   // command ctx only!
 *
 * A user-facing `/cd <dir>` command rides on the same function.
 *
 * Constraints:
 *   - ctx.switchSession() lives on ExtensionCommandContext only — calling it
 *     from event handlers deadlocks (per pi docs). setCwd must therefore be
 *     invoked from a command handler. (Editor-bound callers can submit
 *     "/cd <dir>" through the leader key instead.)
 *   - The source session is left untouched — it stays resumable via /resume.
 *
 * Unlike leader-key there is no mutable registry to clear on
 * session_shutdown: the globalThis slot holds a stateless function object,
 * which also makes it /reload-proof (old and new module copies agree).
 *
 * Load: auto-discovered from pi/extensions/*.ts (= ~/.pi/agent/extensions);
 * /reload after edits.
 */
import { SessionManager } from "@earendil-works/pi-coding-agent";
import type { ExtensionAPI, ExtensionCommandContext, SessionEntry } from "@earendil-works/pi-coding-agent";
import { existsSync, realpathSync, statSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { resolve } from "node:path";

export type SetCwdResult = "switched" | "noop" | "cancelled" | "failed";

/**
 * Replacement-session context slice available inside afterSwitch — the
 * fresh ReplacedSessionContext pi hands to withSession, typed structurally
 * so set-cwd needs no further imports.
 */
export interface ReplacementCtx {
	/**
	 * Inject a custom message bound to the NEW session. With triggerTurn
	 * false while idle: persisted entry + TUI card now, model context next
	 * turn — no turn triggered.
	 */
	sendMessage(
		message: { customType: string; content: string; display: boolean; details?: unknown },
		options?: { triggerTurn?: boolean; deliverAs?: "steer" | "followUp" | "nextTurn" },
	): Promise<void>;
	ui: { notify(message: string, level: "info" | "error" | "warning"): Promise<void> | void };
}

/** The shared surface other extensions consume via getCwdApi(). */
export interface CwdApi {
	/**
	 * Move pi's working directory to `target` by carrying the session.
	 * Must be called from a command handler (`ExtensionCommandContext`).
	 * `target` may be relative to ctx.cwd or start with `~`.
	 *
	 * `opts.message` replaces the default "cwd → <abs>" notify (false
	 * silences it). `opts.afterSwitch` runs in the replacement session
	 * (rctx.sendMessage etc. bound to the NEW session — the caller's own
	 * pi/ctx are stale by then, which is exactly why this hook exists).
	 * `opts.preallocatedSession` switches onto a session file returned by
	 * prepareCwd() instead of forking a fresh one — used by callers that
	 * must validate the carry BEFORE an irreversible action.
	 */
	setCwd(
		ctx: ExtensionCommandContext,
		target: string,
		opts?: {
			message?: string | false;
			afterSwitch?: (rctx: ReplacementCtx) => Promise<void>;
			preallocatedSession?: string;
		},
	): Promise<SetCwdResult>;

	/**
	 * Validate the current session and pre-allocate the carry target for
	 * `target` WITHOUT switching. Throws (nothing changed) when the source
	 * session is unreadable/invalid or the target is not a directory —
	 * exactly the failures that must surface BEFORE e.g. removing the
	 * worktree the session lives in. Hand the returned file back to setCwd
	 * via opts.preallocatedSession.
	 */
	prepareCwd(ctx: ExtensionCommandContext, target: string): Promise<string>;
}

/** globalThis slot under which the shared api lives (see leader-key.ts). */
const API_KEY = "__piSetCwd";

export function getCwdApi(): CwdApi {
	// eslint-disable-next-line @typescript-eslint/no-explicit-any
	const g = globalThis as { [key: string]: any };
	const api = (g[API_KEY] ?? {}) as Partial<CwdApi>;
	// Re-bind every /reload: the object stays shared across module copies,
	// but the bound implementations must be the freshest ones (and older
	// slots must gain new methods like prepareCwd).
	api.setCwd = setCwdImpl;
	api.prepareCwd = prepareCwdImpl;
	g[API_KEY] = api;
	return api as CwdApi;
}

async function setCwdImpl(
	ctx: ExtensionCommandContext,
	target: string,
	opts?: {
		message?: string | false;
		afterSwitch?: (rctx: ReplacementCtx) => Promise<void>;
		preallocatedSession?: string;
	},
): Promise<SetCwdResult> {
	const abs = resolveTarget(ctx.cwd, target);
	if (!existsSync(abs) || !statSync(abs).isDirectory()) {
		await ctx.ui.notify(`setCwd: not a directory: ${abs}`, "error");
		return "failed";
	}
	if (samePath(abs, ctx.cwd)) return "noop";

	let sessionFile: string | undefined;
	try {
		if (opts?.preallocatedSession) {
			if (!existsSync(opts.preallocatedSession)) {
				throw new Error("preallocated session file vanished");
			}
			sessionFile = opts.preallocatedSession;
		} else {
			sessionFile = prepareTargetSession(ctx, abs);
		}
		const result = await ctx.switchSession(sessionFile, {
			withSession: async (rctx) => {
				// Replacement context only — old ctx is stale by now.
				if (opts?.message !== false) {
					await rctx.ui.notify(opts?.message ?? `cwd → ${abs}`, "info");
				}
				try {
					await opts?.afterSwitch?.(rctx);
				} catch (error) {
					// Surface, don't swallow: a dropped afterSwitch is invisible
					// otherwise (see the nextTurn-queue loss this caught).
					await rctx.ui.notify(
						`afterSwitch failed: ${error instanceof Error ? error.message : String(error)}`,
						"error",
					);
				}
			},
		});
		return result.cancelled ? "cancelled" : "switched";
	} catch (error) {
		const kept = sessionFile ? ` Target session kept at ${sessionFile}.` : "";
		const message = `setCwd failed: ${error instanceof Error ? error.message : String(error)}.${kept}`;
		try {
			await ctx.ui.notify(message, "error");
		} catch {
			console.error(message);
		}
		return "failed";
	}
}

/** See CwdApi.prepareCwd — validate + pre-allocate, no switch. */
async function prepareCwdImpl(ctx: ExtensionCommandContext, target: string): Promise<string> {
	const abs = resolveTarget(ctx.cwd, target);
	if (!existsSync(abs) || !statSync(abs).isDirectory()) {
		throw new Error(`prepareCwd: not a directory: ${abs}`);
	}
	if (samePath(abs, ctx.cwd)) {
		throw new Error(`prepareCwd: already in ${abs} (nothing to carry)`);
	}
	return prepareTargetSession(ctx, abs);
}

/**
 * Resolve the session store the way pi core does (main.js):
 * PI_CODING_AGENT_SESSION_DIR env, else the current session's own dir.
 * MUST be passed explicitly to forkFrom/create — their fallback default is
 * <agentDir>/sessions/<encoded-cwd>/, which with PI_CODING_AGENT_DIR
 * redirected lands INSIDE the config repo (and /resume never lists it,
 * losing carried sessions across restarts).
 */
function resolveSessionDir(ctx: ExtensionCommandContext): string {
	return process.env.PI_CODING_AGENT_SESSION_DIR || ctx.sessionManager.getSessionDir();
}

/**
 * Allocate a session file at `target` carrying the current conversation.
 * Two cases, mirroring what pi-worktree's session.ts does:
 *  1. persisted session, disk leaf in sync → SessionManager.forkFrom
 *  2. anything else → manual write of the active branch (possibly empty —
 *     SessionManager.create() only allocates the path, the file itself is
 *     written by writeManualSession)
 */
function prepareTargetSession(ctx: ExtensionCommandContext, target: string): string {
	const sourceFile = ctx.sessionManager.getSessionFile();
	const leaf = ctx.sessionManager.getLeafId();
	const sessionDir = resolveSessionDir(ctx);

	if (sourceFile && existsSync(sourceFile)) {
		const persisted = SessionManager.open(sourceFile, sessionDir);
		if (persisted.getLeafId() === leaf) {
			const forked = SessionManager.forkFrom(sourceFile, target, sessionDir);
			const file = forked.getSessionFile();
			if (!file || !existsSync(file)) {
				throw new Error("pi did not create the target session file");
			}
			return file;
		}
		return writeManualSession(ctx, target, sessionDir, sourceFile, leaf);
	}

	return writeManualSession(ctx, target, sessionDir, undefined, leaf);
}

/**
 * Hand-write [header, ...active branch] into a session created at `target`.
 * Needed when the on-disk leaf no longer matches the in-memory leaf (e.g. a
 * branch was taken but not yet appended) — forkFrom would carry the wrong
 * leaf. SessionManager.create() only allocates the path; the file itself is
 * written here with "wx" so a race with a concurrent creator throws loudly.
 */
function writeManualSession(
	ctx: ExtensionCommandContext,
	target: string,
	sessionDir: string,
	sourceFile: string | undefined,
	expectedLeaf: string | null,
): string {
	const entries: readonly SessionEntry[] = ctx.sessionManager.getBranch();
	const created = SessionManager.create(target, sessionDir, sourceFile ? { parentSession: sourceFile } : undefined);
	const file = created.getSessionFile();
	const header = created.getHeader();
	if (!file || !header) throw new Error("pi did not allocate a target session.");

	const document = [header, ...entries].map((entry) => JSON.stringify(entry)).join("\n");
	writeFileSync(file, `${document}\n`, { encoding: "utf-8", flag: "wx", mode: 0o600 });

	const verified = SessionManager.open(file, sessionDir);
	if (!samePath(verified.getCwd(), target) || verified.getLeafId() !== expectedLeaf) {
		throw new Error("target session failed verification (cwd/leaf mismatch)");
	}
	return file;
}

function resolveTarget(cwd: string, target: string): string {
	const expanded = target === "~" || target.startsWith("~/")
		? resolve(homedir(), target.slice(1))
		: target;
	return resolve(cwd, expanded);
}

function samePath(a: string, b: string): boolean {
	const canon = (p: string): string => {
		try {
			return realpathSync(p);
		} catch {
			return resolve(p);
		}
	};
	return canon(a) === canon(b);
}

export default function (pi: ExtensionAPI) {
	pi.registerCommand("cd", {
		description: "Change pi's working directory, carrying the session",
		handler: async (args, ctx) => {
			const target = args.trim();
			if (!target) {
				await ctx.ui.notify(`usage: /cd <dir>  (cwd: ${ctx.cwd})`, "info");
				return;
			}
			await getCwdApi().setCwd(ctx, target);
		},
	});
}
