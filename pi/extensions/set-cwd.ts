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

/** The shared surface other extensions consume via getCwdApi(). */
export interface CwdApi {
	/**
	 * Move pi's working directory to `target` by carrying the session.
	 * Must be called from a command handler (`ExtensionCommandContext`).
	 * `target` may be relative to ctx.cwd or start with `~`.
	 */
	setCwd(ctx: ExtensionCommandContext, target: string): Promise<SetCwdResult>;
}

/** globalThis slot under which the shared api lives (see leader-key.ts). */
const API_KEY = "__piSetCwd";

export function getCwdApi(): CwdApi {
	// eslint-disable-next-line @typescript-eslint/no-explicit-any
	const g = globalThis as { [key: string]: any };
	let api = g[API_KEY] as CwdApi | undefined;
	if (!api) {
		api = { setCwd: setCwdImpl };
		g[API_KEY] = api;
	}
	return api;
}

async function setCwdImpl(ctx: ExtensionCommandContext, target: string): Promise<SetCwdResult> {
	const abs = resolveTarget(ctx.cwd, target);
	if (!existsSync(abs) || !statSync(abs).isDirectory()) {
		await ctx.ui.notify(`setCwd: not a directory: ${abs}`, "error");
		return "failed";
	}
	if (samePath(abs, ctx.cwd)) return "noop";

	let sessionFile: string | undefined;
	try {
		sessionFile = prepareTargetSession(ctx, abs);
		const result = await ctx.switchSession(sessionFile, {
			withSession: async (rctx) => {
				// Replacement context only — old ctx is stale by now.
				await rctx.ui.notify(`cwd → ${abs}`, "info");
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

/**
 * Allocate a session file at `target` carrying the current conversation.
 * Three cases, mirroring what pi-worktree's session.ts does:
 *  1. persisted session, disk leaf in sync → SessionManager.forkFrom
 *  2. history exists but not cleanly persistable  → manual copy of the
 *     active branch into a fresh session at the target
 *  3. empty session → plain SessionManager.create at the target
 */
function prepareTargetSession(ctx: ExtensionCommandContext, target: string): string {
	const sourceFile = ctx.sessionManager.getSessionFile();
	const leaf = ctx.sessionManager.getLeafId();

	if (sourceFile && existsSync(sourceFile)) {
		const persisted = SessionManager.open(sourceFile);
		if (persisted.getLeafId() === leaf) {
			const forked = SessionManager.forkFrom(sourceFile, target);
			const file = forked.getSessionFile();
			if (!file || !existsSync(file)) {
				throw new Error("pi did not create the target session file");
			}
			return file;
		}
		return writeManualSession(ctx, target, sourceFile, leaf);
	}

	if (ctx.sessionManager.getBranch().length > 0) {
		return writeManualSession(ctx, target, undefined, leaf);
	}

	const fresh = SessionManager.create(target);
	const file = fresh.getSessionFile();
	if (!file || !existsSync(file)) {
		throw new Error("pi did not create the target session file");
	}
	return file;
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
	sourceFile: string | undefined,
	expectedLeaf: string | null,
): string {
	const entries: readonly SessionEntry[] = ctx.sessionManager.getBranch();
	const created = SessionManager.create(target, undefined, sourceFile ? { parentSession: sourceFile } : undefined);
	const file = created.getSessionFile();
	const header = created.getHeader();
	if (!file || !header) throw new Error("pi did not allocate a target session.");

	const document = [header, ...entries].map((entry) => JSON.stringify(entry)).join("\n");
	writeFileSync(file, `${document}\n`, { encoding: "utf-8", flag: "wx", mode: 0o600 });

	const verified = SessionManager.open(file);
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
