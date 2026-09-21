/**
 * browser-profiles.ts — give every pi session (and subagent) its OWN chromium
 * instance + profile for the playwright MCP server, cloned from a shared
 * template so logins/extensions are inherited.
 *
 * WHY: @playwright/mcp launches a persistent chromium per server process
 * keyed on the client cwd, so all sessions land on the SAME profile dir and
 * collide on Chromium's SingletonLock ("Browser is already in use …").
 *
 * HOW:
 *   • session_start → derive the session's profile dir:
 *       /tmp/pi/chromium/<session-id>          (tmpfs: free GC on reboot)
 *     mkdir it, GC stale dirs, export PI_BROWSER_PROFILE_DIR=<dir> in
 *     process.env — nothing is copied yet; most sessions never use the
 *     browser, so the 112MB template clone must not be unconditional.
 *   • tool_call (first playwright MCP use — which is also when the lazy MCP
 *     server/browser spawns; tool_call can block, so the clone lands before
 *     the browser reads the dir) → clone from the template profile:
 *       $XDG_CACHE_HOME/ms-playwright-mcp/mcp-chrome-template
 *     (rsync, volatile caches/locks excluded — see EXCLUDES below), then
 *     seed the download-dir prefs (pi/browser/preferences.json), same merge
 *     apply-preferences.sh does. On rsync failure the partial dir is removed
 *     (leaving a truly empty profile, not a half-cloned one) and the stderr
 *     first line is surfaced in the warning. An existing clone from the same
 *     boot (pi --resume, /reload) is detected via its "Local State" marker
 *     and reused as-is.
 *   • session_shutdown ("quit"/"new"/"resume"/"fork") → delete the profile
 *     dir. Skipped for "reload" (same session continues; mid-session logins
 *     not yet snapshotted to the template would be lost) and while a chromium
 *     still runs on it (a previous session's already-connected server keeps
 *     the dir until `/mcp reconnect playwright` or its idle timeout —
 *     expected, harmless); skipped dirs are collected by the >3d GC on the
 *     next session_start, which also backstops crash-orphaned sessions that
 *     never reach session_shutdown.
 *
 * TEMPLATE MAINTENANCE: log into sites once in the template via
 *   pi/user-scripts/browser-template.sh
 * then close it; every future session clones that state. Clones taken while
 * the template window is open may miss the most recent unflushed logins.
 * Promote a live session's state back into the template (manual, merging)
 * with pi/user-scripts/browser-snapshot.sh — see TECHNICAL_DETAILS.md.
 *
 * pi/mcp.json passes PI_BROWSER_PROFILE_DIR through to the MCP server as
 * PLAYWRIGHT_MCP_USER_DATA_DIR (env overrides the JSON config in
 * @playwright/mcp ≥0.0.78); the value is only read at server spawn, which
 * happens after the lazy clone completes.
 *
 * Load: auto-discovered from pi/extensions/*.ts (= ~/.pi/agent/extensions);
 * `/reload` after edits.
 */
import { execFile } from "node:child_process";
import {
	existsSync,
	mkdirSync,
	readFileSync,
	readdirSync,
	rmSync,
	statSync,
	writeFileSync,
} from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const cacheRoot = process.env.XDG_CACHE_HOME ?? join(homedir(), ".cache");
const TEMPLATE_DIR = join(cacheRoot, "ms-playwright-mcp", "mcp-chrome-template");
const SESSIONS_ROOT = "/tmp/pi/chromium";
const PREFS_SEED = join(process.env.PI_CODING_AGENT_DIR ?? "", "browser", "preferences.json");

/** Volatile / bulky dirs+files that must not cross the template→clone boundary. */
const EXCLUDES = [
	"Singleton*", // profile locks
	"lockfile",
	"Default/Cache",
	"Default/Code Cache",
	"Default/GPUCache",
	"Default/GraphiteDawnCache",
	"Default/Service Worker/CacheStorage",
	"GraphiteDawnCache",
	"GrShaderCache",
	"ShaderCache",
	"crash_interval",
].flatMap((pattern) => ["--exclude", pattern]);

function deepMerge(base: Record<string, unknown>, override: Record<string, unknown>): Record<string, unknown> {
	const out: Record<string, unknown> = { ...base };
	for (const [key, value] of Object.entries(override)) {
		const prev = out[key];
		out[key] =
			value && typeof value === "object" && !Array.isArray(value) && prev && typeof prev === "object" && !Array.isArray(prev)
				? deepMerge(prev as Record<string, unknown>, value as Record<string, unknown>)
				: value;
	}
	return out;
}

/** Same pref-seeding apply-preferences.sh does, but for a fresh clone. */
function seedPrefs(profileDir: string): void {
	try {
		const seed = JSON.parse(readFileSync(PREFS_SEED, "utf8")) as Record<string, unknown>;
		const defaultDir = join(profileDir, "Default");
		const prefsPath = join(defaultDir, "Preferences");
		let prefs: Record<string, unknown> = {};
		try {
			prefs = JSON.parse(readFileSync(prefsPath, "utf8")) as Record<string, unknown>;
		} catch {
			// fresh clone without a Preferences file — start from {}
		}
		mkdirSync(defaultDir, { recursive: true });
		// Direct write is safe: no browser runs on a brand-new clone dir, and
		// Chromium only rewrites Preferences at exit.
		writeFileSync(prefsPath, JSON.stringify(deepMerge(prefs, seed), null, 2));
	} catch (error) {
		// Non-fatal: worst case downloads default to ~/Downloads for this clone.
		console.error(`browser-profiles: pref seeding failed: ${error}`);
	}
}

function rsync(from: string, to: string): Promise<{ code: number; stderr: string }> {
	return new Promise((resolve) => {
		// ctx.exec / pi.exec are declared in pi's ExtensionAPI types but absent at
		// runtime (as of pi 0.84.x), so shell out directly.
		execFile("rsync", ["-a", ...EXCLUDES, `${from}/`, `${to}/`], (error, _stdout, stderr) => {
			resolve({ code: error ? (error.code as number ?? 1) : 0, stderr: String(stderr ?? error ?? "") });
		});
	});
}

function chromiumRunningOn(profileDir: string): Promise<boolean> {
	return new Promise((resolve) => {
		execFile("pgrep", ["-f", `--user-data-dir=${profileDir}`], (error) => resolve(!error));
	});
}

/** Collect dirs untouched for >3d: crash orphans and shutdown skips (browser still lived on them). */
function gcAbandonedProfiles(keep: string): void {
	const maxAgeMs = 3 * 24 * 60 * 60 * 1000;
	let entries;
	try {
		entries = readdirSync(SESSIONS_ROOT, { withFileTypes: true });
	} catch {
		return;
	}
	for (const entry of entries) {
		const dir = join(SESSIONS_ROOT, entry.name);
		if (!entry.isDirectory() || dir === keep) continue;
		try {
			// live browsers keep refreshing both mtimes via atomic rewrites
			let defaultDirMtimeMs = 0;
			try {
				defaultDirMtimeMs = statSync(join(dir, "Default")).mtimeMs;
			} catch {
				// never-cloned (empty) dir — root mtime alone decides
			}
			if (Date.now() - Math.max(statSync(dir).mtimeMs, defaultDirMtimeMs) < maxAgeMs) continue;
			rmSync(dir, { recursive: true, force: true });
		} catch {
			// raced with a concurrent session's start/GC — skip
		}
	}
}

/** True for the mcp gateway tool targeting playwright (tool/server/connect/filter) and for natively exposed playwright tool names. */
function isPlaywrightUse(toolName: string, input: unknown): boolean {
	if (/playwright|_browser_|^browser_/.test(toolName)) return true;
	if (toolName !== "mcp") return false;
	const { tool, server, connect, filter } = (input ?? {}) as Record<string, unknown>;
	const gatewayTool = String(tool ?? "");
	return gatewayTool.startsWith("browser_") || /playwright/.test(gatewayTool) || [server, connect, filter].includes("playwright");
}

export default function browserProfiles(pi: ExtensionAPI): void {
	let profileDir: string | null = null;
	let cloneAttempted = false;

	pi.on("session_start", async (_event, ctx) => {
		profileDir = join(SESSIONS_ROOT, ctx.sessionManager.getSessionId());
		cloneAttempted = existsSync(join(profileDir, "Local State"));
		try {
			mkdirSync(profileDir, { recursive: true });
			gcAbandonedProfiles(profileDir);
			process.env.PI_BROWSER_PROFILE_DIR = profileDir;
		} catch (error) {
			ctx.ui.notify(`browser-profiles: ${error}`, "error");
		}
	});

	pi.on("tool_call", async (event, ctx) => {
		if (!profileDir || cloneAttempted || !isPlaywrightUse(event.toolName, event.input)) return;
		cloneAttempted = true;
		try {
			if (existsSync(TEMPLATE_DIR)) {
				const result = await rsync(TEMPLATE_DIR, profileDir);
				if (result.code !== 0) {
					rmSync(profileDir, { recursive: true, force: true });
					mkdirSync(profileDir, { recursive: true });
					ctx.ui.notify(
						`browser-profiles: template clone failed (rsync exit ${result.code}: ${result.stderr.split("\n")[0]}) — starting with a clean profile`,
						"warning",
					);
				}
			}
			seedPrefs(profileDir);
		} catch (error) {
			ctx.ui.notify(`browser-profiles: ${error}`, "error");
		}
	});

	pi.on("session_shutdown", async (event) => {
		if (!profileDir || event.reason === "reload") return;
		if (await chromiumRunningOn(profileDir)) return;
		rmSync(profileDir, { recursive: true, force: true });
	});
}
