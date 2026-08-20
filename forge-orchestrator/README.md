# EverSpark Forge Orchestrator v0.1

The current version keeps one active user request at a time, while supporting
batch image submission, persistent conversational context, a local Core API,
a Chinese CLI console, Ollama prompt generation, prompt/seed replacement, and
submission to ComfyUI.

## Current boundary

- Supported image model: `illustrious` only.
- Ollama returns `{"model":"illustrious","positive_prompt":"...","negative_prompt":"...","count":1,"status":"over"}`.
- An unsupported model triggers `Error Model,Reloading.....` and an Ollama retry.
- Batch requests queue one ComfyUI prompt per image with an independent seed.
- Batch size is limited to 20 by default.
- Conversation and successful task history are stored in SQLite at
  `/root/.everspark/orchestrator.db`.
- No Asset Registry, dynamic LoRA mapping, multiple workflows, persistent
  ComfyUI queue recovery, or complex state management yet.

## Before the first generation

`forge_orchestrator/workflow/base_workflow_api.json` is intentionally empty.
Export the selected ComfyUI workflow in **API Format**, put its JSON into that file,
then set `positive_prompt_node`, `negative_prompt_node`, and `seed_node` in
`forge_orchestrator/config/default_config.json`.

Also set `ollama.model` to the Ollama model installed on the current Pod.

## Run

In terminal 1 run `everspark orchestrator start`. In terminal 2 run
`everspark orchestrator console`. The Core listens on `127.0.0.1:8765` and
exposes `GET /health`, `POST /tasks`, `GET /context/history`, and
`POST /context/clear`.

Core lifecycle, request failures, and HTTP access records are written to
`${EVERSPARK_LOG_DIR:-/root/everspark_logs}/orchestrator.log`. Set
`ORCHESTRATOR_LOG` only when a dedicated path override is required.

Console commands:

- `/history`: display the current session context.
- `/clear` or `/new`: clear the current session context.
- `/exit`: close the console without stopping the Core.
