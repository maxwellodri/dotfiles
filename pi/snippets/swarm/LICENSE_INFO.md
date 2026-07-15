# License & attribution — `swarm` snippet

This snippet (`snippet.md`) is adapted from **OpenAI Codex**, licensed under
the Apache License 2.0: <https://github.com/openai/codex>.

## What was adapted

Codex exposes a product-level **"ultra" reasoning level** that, under the hood,
is not a reasoning depth at all — it maps to an internal
`MultiAgentMode::Proactive` multi-agent delegation mode. The proactive
delegation prompt text, and the root-agent / shared-workspace usage hints that
this snippet is adapted from, come from:

- `codex-rs/core/src/session/multi_agents.rs`
  — `ReasoningEffort::Ultra` → `MultiAgentMode::Proactive`
  (`effective_multi_agent_mode`)
- `codex-rs/core/src/context/multi_agent_mode_instructions.rs`
  — `PROACTIVE_MULTI_AGENT_MODE_TEXT`
- `codex-rs/core/src/config/mod.rs`
  — `DEFAULT_MULTI_AGENT_V2_ROOT_AGENT_USAGE_HINT_TEXT` and
    `DEFAULT_MULTI_AGENT_V2_SHARED_USAGE_HINT_TEXT`

The **spirit** (proactive delegation, root-agent orchestration, shared
workspace, parallel/context-isolation wins) is carried over. The **mechanics**
were rewritten for pi's `subagent` tool (single / parallel / chain) and its
**heterogeneous, tool-restricted** agents — codex's homogeneous
`spawn_agent` / `send_message` / `wait` collaboration model does not apply to
pi, where each subagent is a one-shot headless child with its own allowlist.

## Apache License 2.0

```
Copyright 2025 OpenAI

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
```

Full text: <https://www.apache.org/licenses/LICENSE-2.0>
