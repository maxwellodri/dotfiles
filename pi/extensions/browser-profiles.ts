/**
 * browser-profiles.ts — per-session chromium + profile for the playwright
 * (and blender) MCP servers, cloned from a shared template so logins and
 * extensions are inherited. WHY separate profiles: @playwright/mcp keys its
 * persistent chromium on the client cwd, so concurrent sessions collide on
 * Chromium's SingletonLock.
 *
 * The servers are registered HERE (exposure "deferred"), not in pi/mcp.json —
 * mcp.json is shared across hosts, these should only exist where the tools
 * are installed. The playwright binary comes from nixpkgs via nix_config's
 * dotfiles-env (version pinned by the nixpkgs-dotfiles flake.lock); npx is
 * only the fallback for hosts without the nix env.
 *
 * Template maintenance: log into sites once via
 * pi/user-scripts/browser-template.sh; promote a live session's state back
 * with pi/user-scripts/browser-snapshot.sh. Full mechanics in
 * skills/web-browser-use/TECHNICAL_DETAILS.md.
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

/** First PATH entry containing bin, or null (avoids spawning sh for lookup). */
function resolveOnPath(bin: string): string | null {
	for (const dir of process.env.PATH?.split(":") ?? []) {
		const candidate = join(dir, bin);
		if (existsSync(candidate)) return candidate;
	}
	return null;
}

/** True for any playwright browser tool call (mcp__playwright__browser_*). */
function isPlaywrightUse(toolName: string): boolean {
	return /playwright|_browser_|^browser_/.test(toolName);
}

export default function browserProfiles(pi: ExtensionAPI): void {
	let profileDir: string | null = null;
	let cloneAttempted = false;

	/** Register a stdio MCP server unless it is already file-configured. */
	const registerMcpServers = (): void => {
		const agentDir = process.env.PI_CODING_AGENT_DIR;
		if (!agentDir) return;
		if (existsSync("/usr/bin/chromium")) {
			// /usr/bin/chromium is the executablePath pinned in pi/browser/playwright-config.json
			const playwrightMcp = resolveOnPath("playwright-mcp");
			pi.registerMcpServer("playwright", {
				command: playwrightMcp ?? "npx",
				// no pinned version for the nix binary: the nixpkgs-dotfiles
				// flake.lock is the pin; npx fallback pins its own
				args: [
					...(playwrightMcp ? [] : ["@playwright/mcp@0.0.80"]),
					"--sandbox",
					"--config",
					"playwright-config.json",
				],
				cwd: join(agentDir, "browser"),
				env: { PLAYWRIGHT_MCP_USER_DATA_DIR: profileDir ?? "" },
				exposure: "deferred",
				description: "Headed per-session chromium: navigate, click, type, screenshot, scrape, run JS. Tools load via load_mcp/tool_search.",
			});
		}
		if (existsSync("/usr/bin/blender")) {
			pi.registerMcpServer("blender", {
				command: "uv",
				// --frozen: never resolve against the network at session start;
				// the venv is pre-synced by nix_config's install_flake.sh
				args: ["run", "--frozen", "blender-mcp"],
				cwd: join(agentDir, "..", "uv", "mcp"),
				env: { UV_PYTHON_PREFERENCE: "only-managed", DISABLE_TELEMETRY: "true" },
				exposure: "deferred",
				description: "Inspect and drive the user's running Blender: scene info, viewport screenshot, execute bpy code. Tools load via tool_search.",
			});
		}
	};

	/** Footer status: only servers whose tools are declared to the model (active), else None. */
	const setMcpFooterStatus = (ctx: { hasUI?: boolean; ui?: { setStatus(key: string, text: string | undefined): void } }): void => {
		if (!ctx.hasUI || !ctx.ui) return;
		const servers = new Set<string>();
		for (const toolName of pi.getActiveTools()) {
			const match = toolName.match(/^mcp__([A-Za-z0-9_-]+?)__/);
			if (match) servers.add(match[1].replaceAll("_", "-"));
		}
		const text = servers.size > 0 ? [...servers].join(", ") : "None";
		ctx.ui.setStatus("mcp", `MCP: ${text}`);
	};

	pi.on("session_start", async (_event, ctx) => {
		profileDir = join(SESSIONS_ROOT, ctx.sessionManager.getSessionId());
		cloneAttempted = existsSync(join(profileDir, "Local State"));
		try {
			mkdirSync(profileDir, { recursive: true });
			gcAbandonedProfiles(profileDir);
		} catch (error) {
			ctx.ui.notify(`browser-profiles: ${error}`, "error");
		}
		registerMcpServers();
		setMcpFooterStatus(ctx);
	});

	pi.on("tool_result", (_event, ctx) => {
		setMcpFooterStatus(ctx);
	});

	pi.on("tool_call", async (event, ctx) => {
		if (!profileDir || cloneAttempted || !isPlaywrightUse(event.toolName)) return;
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
