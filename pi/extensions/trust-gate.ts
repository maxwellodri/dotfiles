/**
 * trust-gate.ts — shared content-trust gate for repo-controlled files.
 *
 * HOST of the trust mechanism factored out of subagent's project-override
 * gate. Any extension about to honour repo-controlled content (prompt
 * overrides, executable skill scripts, ...) asks the gate instead of rolling
 * its own store + prompt:
 *
 *   import { getTrustGate } from "../trust-gate";
 *   const ok = await getTrustGate().confirm("subagent-override", {
 *     label: `append override for "explore"`,
 *     path: agent.overridePath,
 *     hasUI: ctx.hasUI && Boolean(ctx.ui?.select),
 *     select: ctx.ui?.select?.bind(ctx.ui),
 *     inspect: () => openInNvim(agent), // optional
 *   });
 *
 * Behaviour:
 *   - Identity = SHA-256 of the file's CURRENT content, keyed by a canonical
 *     git-root-relative path (worktrees/symlinked checkouts of one checkout
 *     share trust; a different repo never inherits it).
 *   - Unknown content prompts: Trust (always) / [Open in editor] / Deny.
 *     "Open in editor" runs `check.inspect` (caller owns the editor UX; edits
 *     allowed) and re-prompts. "Trust (always)" persists the hash of the file
 *     as it stands NOW — post-edit content is what gets trusted.
 *   - No UI (print/JSON mode), denied, dismissed, or unreadable file → fail
 *     closed. Callers re-prompt on next use.
 *   - Store: $XDG_STATE_HOME/pi/trust-gate.json, one section per namespace,
 *     mode 0600 — machine-local, never the (git-tracked) config dir.
 *
 * ── Why globalThis instead of a normal import? ──────────────────────────
 * Same rationale as leader-key.ts: pi loads every extension with jiti
 * `{ moduleCache: false }`, so each importing extension gets its own module
 * copy. The disk store is shared either way, but the gate object itself lives
 * in a globalThis slot so every copy reaches ONE instance — a stable handle
 * for any future in-memory state (e.g. session-scoped trust) without touching
 * consumers. The default export is a no-op that only exists so pi
 * auto-discovery accepts this file as an extension.
 */
import * as crypto from "node:crypto";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

/** globalThis slot under which the shared gate lives. */
const REGISTRY_KEY = "__piTrustGate";

/** What the gate needs to make (and show) a decision. */
export interface TrustCheck {
	/** Shown in the prompt, e.g. `append override for "explore"`. */
	label: string;
	/** File whose CURRENT content is being trusted; hash-keyed so edits re-prompt. */
	path: string;
	/** False in print/JSON mode → fail closed unless already trusted. */
	hasUI: boolean;
	/** Dialog helper from ctx.ui; only called when hasUI is true. */
	select?: (title: string, options: string[]) => Promise<string | undefined>;
	/** Optional inspection hook (e.g. open in editor). Re-prompts after return. */
	inspect?: () => Promise<void>;
}

export interface TrustGate {
	/** True = current content already trusted or approved now. False = denied / no UI / unreadable file. */
	confirm(namespace: string, check: TrustCheck): Promise<boolean>;
	/** Store check only, no prompt — for pre-checks (attention pings) and headless short-circuits. */
	isTrusted(namespace: string, path_: string): boolean;
}

function storePath(): string {
	const stateHome = process.env.XDG_STATE_HOME || path.join(os.homedir(), ".local", "state");
	return path.join(stateHome, "pi", "trust-gate.json");
}

function loadStore(): Record<string, Record<string, string>> {
	try {
		const parsed = JSON.parse(fs.readFileSync(storePath(), "utf-8"));
		return parsed && typeof parsed === "object" ? parsed : {};
	} catch {
		return {};
	}
}

function saveStore(store: Record<string, Record<string, string>>): void {
	const filePath = storePath();
	fs.mkdirSync(path.dirname(filePath), { recursive: true });
	fs.writeFileSync(filePath, JSON.stringify(store, null, "\t") + "\n", { mode: 0o600 });
}

function safeRealpath(p: string): string {
	try {
		return fs.realpathSync(p);
	} catch {
		return p;
	}
}

/**
 * Stable trust-store key: the repository's canonical git dir + path relative
 * to the repo root, so worktrees and symlinked checkouts of the SAME checkout
 * do not re-prompt (a worktree's `.git` file points back at the main
 * checkout's gitdir; worktree-specific `worktrees/<name>` suffixes are
 * stripped), while a different repo — even with identical file content at the
 * same relative path — never inherits trust. Falls back to the absolute file
 * path when no git root is found.
 */
function trustKey(filePath: string): string {
	const resolved = path.resolve(filePath);
	let dir = path.dirname(resolved);
	while (true) {
		const gitPath = path.join(dir, ".git");
		if (fs.existsSync(gitPath)) {
			let canonical = safeRealpath(dir);
			// Worktree: .git is a file "gitdir: <main>/.git/worktrees/<name>".
			// Normalize to the main checkout's git dir so all worktrees agree.
			try {
				if (fs.statSync(gitPath).isFile()) {
					const gitdir = fs.readFileSync(gitPath, "utf-8").trim().replace(/^gitdir:\s*/i, "");
					const mainGit = gitdir.replace(/[\\/]worktrees[\\/][^\\/]+$/, "");
					if (mainGit !== gitdir) canonical = safeRealpath(path.dirname(mainGit));
				}
			} catch {
				/* keep checkout-root fallback */
			}
			return `${canonical}:${path.relative(safeRealpath(dir), safeRealpath(resolved))}`;
		}
		const parent = path.dirname(dir);
		if (parent === dir) return resolved;
		dir = parent;
	}
}

function contentHash(filePath: string): string | null {
	try {
		return crypto.createHash("sha256").update(fs.readFileSync(filePath)).digest("hex");
	} catch {
		return null;
	}
}

export function getTrustGate(): TrustGate {
	// eslint-disable-next-line @typescript-eslint/no-explicit-any
	const g = globalThis as { [key: string]: any };
	let gate = g[REGISTRY_KEY] as TrustGate | undefined;
	if (!gate) {
		gate = {
			async confirm(namespace, check) {
				while (true) {
					const key = trustKey(check.path);
					const hash = contentHash(check.path);
					if (!hash) return false;
					if (loadStore()[namespace]?.[key] === hash) return true;
					if (!check.hasUI || !check.select) return false; // fail closed headless
					const options = check.inspect
						? ["Trust (always)", "Open in editor", "Deny"]
						: ["Trust (always)", "Deny"];
					const choice = await check.select(`Trust ${check.label}?\n${check.path}`, options);
					if (choice === "Trust (always)") {
						// Hash the CURRENT content — it may have been edited via inspect.
						const store = loadStore();
						store[namespace] = store[namespace] ?? {};
						store[namespace][key] = contentHash(check.path) ?? hash;
						saveStore(store);
						return true;
					}
					if (choice === "Open in editor" && check.inspect) {
						try {
							await check.inspect();
						} catch (err) {
							await check.select(
								`Could not open editor: ${err instanceof Error ? err.message : String(err)}`,
								["OK"],
							);
						}
						continue;
					}
					// "Deny", dismissed dialog, unknown choice: fail closed.
					return false;
				}
			},
			isTrusted(namespace, path_) {
				const hash = contentHash(path_);
				return Boolean(hash) && loadStore()[namespace]?.[trustKey(path_)] === hash;
			},
		};
		g[REGISTRY_KEY] = gate;
	}
	return gate;
}

export default function (_pi: ExtensionAPI) {
	// No lifecycle: the gate's state is the on-disk store. This default export
	// only exists so pi auto-discovery loads this file for other extensions.
}
