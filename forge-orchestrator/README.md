# EverSpark Forge Orchestrator v0.1

The first version is deliberately small: one task at a time, a persistent local
Core API, a separate Chinese CLI console, Ollama prompt generation, prompt-node
replacement, and submission to ComfyUI.

## Current boundary

- Supported image model: `illustrious` only.
- Ollama must return `{"model":"illustrious","positive_prompt":"...","negative_prompt":"...","status":"over"}`.
- An unsupported model triggers `Error Model,Reloading.....` and an Ollama retry.
- No Asset Registry, LoRA mapping, multiple workflows, persistent queue, task recovery, or complex state management yet.

## Before the first generation

`forge_orchestrator/workflow/base_workflow_api.json` is intentionally empty.
Export the selected ComfyUI workflow in **API Format**, put its JSON into that file,
then set `positive_prompt_node` and `negative_prompt_node` in
`forge_orchestrator/config/default_config.json`.

Also set `ollama.model` to the Ollama model installed on the current Pod.

## Run

In terminal 1 run `everspark orchestrator start`. In terminal 2 run
`everspark orchestrator console`. The Core listens on `127.0.0.1:8765` and
exposes `GET /health` and `POST /tasks`.
