#!/usr/bin/env bash
# check_stealth_models — list live OpenRouter stealth/* models as paste-ready
# pi models.json entries (drop under the "openrouter" provider's "models").
# Stealth drops are free/cheap preview windows; ids vanish at reveal time.
set -euo pipefail

curl -fsS --max-time 30 https://openrouter.ai/api/v1/models | jq '[
	.data[]
	| select(.id | startswith("stealth/"))
	| {
			id,
			name,
			reasoning: ((.supported_parameters // []) | any(. == "reasoning" or . == "include_reasoning")),
			input: (if ((.architecture.input_modalities // []) | index("image")) then ["text", "image"] else ["text"] end),
			contextWindow: (.context_length // 131072),
			maxTokens: (.top_provider.max_completion_tokens // 32768),
			cost: {
				input: ((.pricing.prompt // "0") | tonumber * 1e6 | round),
				output: ((.pricing.completion // "0") | tonumber * 1e6 | round),
				cacheRead: ((.pricing.input_cache_read // "0") | tonumber * 1e6 | round),
				cacheWrite: 0
			},
			compat: { supportsStore: false, supportsDeveloperRole: false }
		}
]'
