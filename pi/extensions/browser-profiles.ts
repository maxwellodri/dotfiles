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
 *   • If it doesn't exist yet, clone it from the template profile:
 *       $XDG_CACHE_HOME/ms-playwright-mcp/mcp-chrome-template
 *     (rsync, volatile caches/locks excluded — see EXCLUDES below).
 *   • Seed the download-dir prefs (pi/browser/preferences.json) into the
 *     clone, same merge apply-preferences.sh does (skipped if the clone's
 *     browser is somehow already running — Chromium would overwrite on exit).
 *   • Export PI_BROWSER_PROFILE_DIR=<dir> in process.env; pi/mcp.json passes
 *     it through to the MCP server as PLAYWRIGHT_MCP_USER_DATA_DIR (env
 *     overrides the JSON config in @playwright/mcp ≥0.0.78), so the launch
 *     is lazy-safe: the server only spawns on first browser use, long after
 *     session_start set the var.
 *
 * TEMPLATE MAINTENANCE: log into sites once in the template via
 *   pi/user-scripts/browser-template.sh
 * then close it; every future session clones that state. Clones taken while
 * the template window is open may miss the most recent unflushed logins.
 *
 * NOT RE-CLONED: an existing /tmp/pi/chromium/<sid> is reused as-is (same
 * boot, e.g. pi --resume); after reboot it is rebuilt from the template.
 *
 * After /resume or /new, an already-connected playwright server keeps the
 * previous session's profile until `/mcp reconnect playwright` or its idle
 * timeout — expected, harmless.
 *
 * Load: auto-discovered from pi/extensions/*.ts (= ~/.pi/agent/extensions);
 * `/reload` after edits.
 */
import { execFile } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
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

export default function browserProfiles(pi: ExtensionAPI): void {
	pi.on("session_start", async (_event, ctx) => {
		const sessionId = ctx.sessionManager.getSessionId();
		const profileDir = join(SESSIONS_ROOT, sessionId);

		try {
			if (!existsSync(profileDir)) {
				mkdirSync(profileDir, { recursive: true });
				if (existsSync(TEMPLATE_DIR)) {
					const result = await rsync(TEMPLATE_DIR, profileDir);
					if (result.code !== 0) {
						ctx.ui.notify(`browser-profiles: template clone failed (rsync exit ${result.code}) — starting with a clean profile`, "warning");
					}
				}
				seedPrefs(profileDir);
			}
			process.env.PI_BROWSER_PROFILE_DIR = profileDir;
		} catch (error) {
			ctx.ui.notify(`browser-profiles: ${error}`, "error");
		}
	});
}
