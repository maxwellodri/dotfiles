/**
 * Agent discovery and configuration.
 *
 * Based on the official pi example (earendil-works/pi), with one deliberate
 * deviation: per-file frontmatter parse errors are collected and returned in
 * `AgentDiscoveryResult.errors` instead of throwing — a single malformed agent
 * file must not take down the whole extension (load happens both at extension
 * init via assertNoReservedAgentNames and every turn via before_agent_start).
 *
 * Agent definitions are Markdown files with YAML frontmatter, discovered from:
 *   - user agents:    <getAgentDir()>/agents/*.md   (here: pi/agents/*.md)
 *   - project agents: <cwd>/.pi/agents/*.md          (repo-controlled)
 */

import * as fs from "node:fs";
import * as path from "node:path";
import { CONFIG_DIR_NAME, getAgentDir, parseFrontmatter } from "@earendil-works/pi-coding-agent";

export type AgentScope = "user" | "project" | "both";

/**
 * Project-local system-prompt overrides. A project may customize any agent
 * (typically a user agent) by dropping a magic file into its agents dir:
 *   .pi/agents/<name>/append.md   -> body is appended to the agent's prompt
 *   .pi/agents/<name>/replace.md  -> body replaces the agent's prompt
 * `append`/`replace` are therefore reserved agent names (checked at init).
 */
export type AgentOverrideMode = "append" | "replace";
export const RESERVED_AGENT_NAMES: readonly AgentOverrideMode[] = ["append", "replace"];

export interface AgentConfig {
	name: string;
	description: string;
	tools?: string[];
	model?: string;
	systemPrompt: string;
	/** Prompt before an override was applied; undefined = no override. */
	baseSystemPrompt?: string;
	source: "user" | "project";
	filePath: string;
	override?: AgentOverrideMode;
	overridePath?: string;
}

export interface AgentDiscoveryResult {
	agents: AgentConfig[];
	projectAgentsDir: string | null;
	/** Files skipped for bad frontmatter — surfaced to the user, never thrown. */
	errors: AgentParseError[];
}

export interface AgentParseError {
	filePath: string;
	message: string;
}

function loadAgentsFromDir(
	dir: string,
	source: "user" | "project",
): { agents: AgentConfig[]; errors: AgentParseError[] } {
	const agents: AgentConfig[] = [];
	const errors: AgentParseError[] = [];

	if (!fs.existsSync(dir)) {
		return agents;
	}

	let entries: fs.Dirent[];
	try {
		entries = fs.readdirSync(dir, { withFileTypes: true });
	} catch {
		return agents;
	}

	for (const entry of entries) {
		if (!entry.name.endsWith(".md")) continue;
		if (!entry.isFile() && !entry.isSymbolicLink()) continue;

		const filePath = path.join(dir, entry.name);
		let content: string;
		try {
			content = fs.readFileSync(filePath, "utf-8");
		} catch {
			continue;
		}

		let frontmatter: Record<string, string>;
		let body: string;
		try {
			({ frontmatter, body } = parseFrontmatter<Record<string, string>>(content));
		} catch (err) {
			// e.g. an unquoted value containing ": " — "Nested mappings are not
			// allowed in compact mappings". First line has the line/col.
			const detail = err instanceof Error ? err.message.split("\n")[0] : String(err);
			errors.push({ filePath, message: `bad frontmatter: ${detail}` });
			continue;
		}

		if (!frontmatter.name || !frontmatter.description) {
			errors.push({ filePath, message: "frontmatter missing `name` or `description`" });
			continue;
		}

		const tools = frontmatter.tools
			?.split(",")
			.map((t: string) => t.trim())
			.filter(Boolean);

		agents.push({
			name: frontmatter.name,
			description: frontmatter.description,
			tools: tools && tools.length > 0 ? tools : undefined,
			model: frontmatter.model,
			systemPrompt: body,
			source,
			filePath,
		});
	}

	return { agents, errors };
}

function isDirectory(p: string): boolean {
	try {
		return fs.statSync(p).isDirectory();
	} catch {
		return false;
	}
}

/**
 * Crash the session at init if a user agent squats on a reserved override
 * name ("append"/"replace") — the magic override directories would make its
 * resolution ambiguous.
 */
export function assertNoReservedAgentNames(): void {
	const userDir = path.join(getAgentDir(), "agents");
	for (const agent of loadAgentsFromDir(userDir, "user").agents) {
		if ((RESERVED_AGENT_NAMES as readonly string[]).includes(agent.name)) {
			throw new Error(
				`Agent name "${agent.name}" is reserved for system-prompt overrides ` +
					`(magic files .pi/agents/<name>/append.md and replace.md). ` +
					`Rename ${agent.filePath}.`,
			);
		}
	}
}

function loadAgentOverride(
	projectAgentsDir: string,
	name: string,
): { mode: AgentOverrideMode; body: string; filePath: string } | null {
	const found: { mode: AgentOverrideMode; body: string; filePath: string }[] = [];
	for (const mode of RESERVED_AGENT_NAMES) {
		const filePath = path.join(projectAgentsDir, name, `${mode}.md`);
		if (!fs.existsSync(filePath)) continue;
		let body: string;
		try {
			body = fs.readFileSync(filePath, "utf-8");
		} catch {
			continue;
		}
		found.push({ mode, body, filePath });
	}
	if (found.length === 0) return null;
	if (found.length > 1) {
		const paths = found.map((f) => f.filePath).join(" and ");
		throw new Error(`Conflicting agent overrides for "${name}": ${paths}. Keep only one.`);
	}
	return found[0];
}

function findNearestProjectAgentsDir(cwd: string): string | null {
	let currentDir = cwd;
	while (true) {
		const candidate = path.join(currentDir, CONFIG_DIR_NAME, "agents");
		if (isDirectory(candidate)) return candidate;

		const parentDir = path.dirname(currentDir);
		if (parentDir === currentDir) return null;
		currentDir = parentDir;
	}
}

export function discoverAgents(cwd: string, scope: AgentScope): AgentDiscoveryResult {
	const userDir = path.join(getAgentDir(), "agents");
	const projectAgentsDir = findNearestProjectAgentsDir(cwd);

	const userResult = scope === "project" ? undefined : loadAgentsFromDir(userDir, "user");
	const projectResult =
		scope === "user" || !projectAgentsDir ? undefined : loadAgentsFromDir(projectAgentsDir, "project");
	const userAgents = userResult?.agents ?? [];
	const projectAgents = projectResult?.agents ?? [];
	const errors = [...(userResult?.errors ?? []), ...(projectResult?.errors ?? [])];

	const agentMap = new Map<string, AgentConfig>();

	if (scope === "both") {
		for (const agent of userAgents) agentMap.set(agent.name, agent);
		for (const agent of projectAgents) agentMap.set(agent.name, agent);
	} else if (scope === "user") {
		for (const agent of userAgents) agentMap.set(agent.name, agent);
	} else {
		for (const agent of projectAgents) agentMap.set(agent.name, agent);
	}

	const agents = Array.from(agentMap.values());

	// Apply project-local system-prompt overrides (append/replace), wherever the
	// base agent came from. Loading one requires project scope so the dir is known.
	if (projectAgentsDir && (scope === "project" || scope === "both")) {
		for (const agent of agents) {
			const override = loadAgentOverride(projectAgentsDir, agent.name);
			if (!override) continue;
			agent.baseSystemPrompt = agent.systemPrompt;
			agent.systemPrompt =
				override.mode === "append" ? `${agent.systemPrompt}\n\n${override.body}` : override.body;
			agent.override = override.mode;
			agent.overridePath = override.filePath;
		}
	}

	return { agents, projectAgentsDir, errors };
}

export function formatAgentList(agents: AgentConfig[], maxItems: number): { text: string; remaining: number } {
	if (agents.length === 0) return { text: "none", remaining: 0 };
	const listed = agents.slice(0, maxItems);
	const remaining = agents.length - listed.length;
	return {
		text: listed.map((a) => `${a.name} (${a.source}): ${a.description}`).join("; "),
		remaining,
	};
}
