/**
 * Additive functionality on top of pi's builtin MCP, not a replacement.
 * Adds `load_mcp` — declare all tools of a given MCP server at once.
 */
import { Type } from "typebox";
import type { AgentToolResult, ExtensionAPI } from "@earendil-works/pi-coding-agent";

const CONNECT_POLL_MS = 250;
const CONNECT_TIMEOUT_MS = 10_000;

/** "dev-Radius", "mcp__dev-radius" → "dev_radius" (pi's tool-name form). */
function normalizeServerName(input: string): string {
	return input.trim().replace(/^mcp__/i, "").replaceAll("-", "_").toLowerCase();
}

function serverTools(pi: ExtensionAPI, server: string) {
	const ns = `mcp__${normalizeServerName(server)}`;
	return pi
		.getAllTools()
		.filter(
			(t) =>
				t.exposure !== "hidden" &&
				(t.namespace?.name === ns || t.name.startsWith(`${ns}__`)),
		);
}

function connectedServers(pi: ExtensionAPI): string[] {
	const namespaces = pi
		.getAllTools()
		.map((t) => t.namespace?.name)
		.filter((n): n is string => !!n?.startsWith("mcp__"));
	return [...new Set(namespaces)].sort();
}

export default function loadMcp(pi: ExtensionAPI): void {
	pi.registerTool({
		name: "load_mcp",
		label: "Load MCP tools",
		description:
			"# MCP tool loading\n\n" +
			"Declare every tool of one MCP server for your next call. " +
			"Deterministic, unlike tool_search (whose BM25 ranking can miss tools with short descriptions). " +
			"Use when a skill or task names an MCP server: load_mcp({ server: \"playwright\" }). " +
			"On an unknown server the error lists the connected ones.",
		promptSnippet:
			"Declare all tools of one MCP server by name (deterministic tool_search alternative)",
		parameters: Type.Object({
			server: Type.String({
				description:
					'MCP server name, e.g. "playwright" or "blender" (mcp__ prefix optional)',
			}),
		}),
		exposure: "model-only",
		async execute(_id, { server }): Promise<AgentToolResult<{ loaded: string[] }>> {
			const deadline = Date.now() + CONNECT_TIMEOUT_MS;
			let tools = serverTools(pi, server);
			while (tools.length === 0 && Date.now() < deadline) {
				await new Promise((r) => setTimeout(r, CONNECT_POLL_MS));
				tools = serverTools(pi, server);
			}
			if (tools.length === 0) {
				const known = connectedServers(pi);
				throw new Error(
					`No MCP server "${server}"${
						known.length
							? `; connected: ${known.join(", ")}`
							: " (none connected yet)"
					}`,
				);
			}

			const active = new Set(pi.getActiveTools());
			const loadable = tools.filter(
				(t) =>
					(t.exposure === "codemode" || t.exposure === "deferred") &&
					!active.has(t.name),
			);
			if (loadable.length > 0)
				pi.setActiveTools([...active, ...loadable.map((t) => t.name)]);

			const listing = tools
				.map((t) => `- ${t.name}: ${t.description.trim().split(/\r?\n/)[0]}`)
				.join("\n");
			const head =
				loadable.length === 0
					? `All ${tools.length} "${server}" tools were already active:`
					: `Loaded ${loadable.length} of ${tools.length} "${server}" tools (rest already active). Available from your next call:`;
			return {
				content: [{ type: "text", text: `${head}\n${listing}` }],
				details: { loaded: loadable.map((t) => t.name) },
			};
		},
	});
}
