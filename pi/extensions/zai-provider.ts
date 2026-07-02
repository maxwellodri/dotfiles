import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

// Z.AI Coding Plan (GLM-5.2), OpenAI-compatible.
// Uses the coding-only endpoint — the general /api/paas/v4 endpoint 404s on
// coding-plan keys. The API key comes from $ZAI_API_KEY (set by the pi wrapper
// via `pass`); Pi interpolates it into the Authorization header.
export default function (pi: ExtensionAPI) {
	pi.registerProvider("zai", {
		name: "Z.AI (Coding Plan)",
		baseUrl: "https://api.z.ai/api/coding/paas/v4",
		apiKey: "$ZAI_API_KEY",
		api: "openai-completions",
		models: [
			{
				id: "glm-5.2",
				name: "GLM-5.2",
				reasoning: true,
				input: ["text"],
				cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
				contextWindow: 204800,
				maxTokens: 131072,
			},
		],
	});
}
