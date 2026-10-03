/**
 * archive.ts — /archive: retire the current thread into archived_sessions/.
 *
 * Moving a session file out from under a live SessionManager is futile —
 * the next append recreates it at the old path (the same trap that makes
 * manage-sessions mark the ·current line undeletable). So /archive
 * switches FIRST: pi starts a fresh session, the old runtime is torn
 * down, and only then does the file move — inside withSession, operating
 * on plain captured strings, never the stale pre-switch ctx.
 *
 * Destination: PI_CODING_AGENT_ARCHIVED_SESSION_DIR when set (the pi
 * wrapper exports the XDG path), else the "archived_sessions" sibling of
 * the session dir's realpath (resolves through the XDG symlink into the
 * private-repo runtime; assumes the nested runtime/pi/<tag>/sessions
 * layout that pi_sessions.sh establishes). Archived files leave /resume, `pi -c` and
 * /manage_sessions by construction — those only ever list the live
 * session dir. Un-archive is a plain mv back.
 *
 * Load: auto-discovered from pi/extensions/*.ts; /reload after edits.
 */
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { copyFileSync, existsSync, mkdirSync, renameSync, unlinkSync } from "node:fs";
import { realpathSync } from "node:fs";
import { basename, dirname, join } from "node:path";

function resolveArchiveDir(sessionDir: string): string {
	const override = process.env.PI_CODING_AGENT_ARCHIVED_SESSION_DIR;
	if (override) return override;
	let real = sessionDir;
	try {
		real = realpathSync(sessionDir);
	} catch {
		// unreachable target: derive from the path as given
	}
	return join(dirname(real), "archived_sessions");
}

/** rename, falling back to copy+unlink across filesystems; a failed
 * copy never leaves a truncated twin of the source in the archive. */
function moveSync(src: string, dest: string): void {
	try {
		renameSync(src, dest);
	} catch (error) {
		if ((error as NodeJS.ErrnoException).code !== "EXDEV") throw error;
		try {
			copyFileSync(src, dest);
		} catch (copyError) {
			try {
				unlinkSync(dest);
			} catch {
				// best effort — dest may never have been created
			}
			throw copyError;
		}
		unlinkSync(src);
	}
}

export default function (pi: ExtensionAPI) {
	pi.registerCommand("archive", {
		description: "Archive this thread — fresh session starts, file moves to archived_sessions/",
		handler: async (_args, ctx) => {
			await ctx.waitForIdle();
			const sessionFile = ctx.sessionManager.getSessionFile();
			if (!sessionFile) {
				if (ctx.hasUI) await ctx.ui.notify("/archive: ephemeral session — nothing to archive", "warning");
				return;
			}
			const sessionDir = ctx.sessionManager.getSessionDir() ?? dirname(sessionFile);
			const archiveDir = resolveArchiveDir(sessionDir);

			const result = await ctx.newSession({
				withSession: async (newCtx) => {
					if (!existsSync(sessionFile)) {
						if (newCtx.hasUI)
							await newCtx.ui.notify("/archive: session file not on disk yet — fresh session started, nothing moved", "info");
						return;
					}
					try {
						mkdirSync(archiveDir, { recursive: true });
						let dest = join(archiveDir, basename(sessionFile));
						if (existsSync(dest)) dest = join(archiveDir, `${Date.now()}_${basename(sessionFile)}`);
						moveSync(sessionFile, dest);
						if (newCtx.hasUI) await newCtx.ui.notify(`archived → ${dest}`, "info");
					} catch (error) {
						if (newCtx.hasUI)
							await newCtx.ui.notify(`/archive: ${String(error)} — file left in place`, "error");
					}
				},
			});
			if (result.cancelled && ctx.hasUI) {
				await ctx.ui.notify("/archive: new session was cancelled — nothing archived", "warning");
			}
		},
	});
}
