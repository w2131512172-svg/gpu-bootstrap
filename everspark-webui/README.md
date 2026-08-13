# EverSpark WebUI v0.1

The first WebUI unifies the current EverSpark input and image output path without
changing the existing Orchestrator CLI or ComfyUI initialization flow.

## Current features

- Submit Chinese creation requests to the existing Orchestrator `POST /tasks` API.
- Display one or more queued ComfyUI results by their exact `prompt_id`.
- Poll ComfyUI `/history/{prompt_id}` instead of guessing the newest output file.
- Proxy ComfyUI `/view` so the browser never needs the real ComfyUI address.
- Show recent images from ComfyUI history.
- Show lightweight Orchestrator and ComfyUI health state.
- Use only the Python standard library.

## Run

Start ComfyUI and EverSpark Orchestrator first, then run:

```bash
chmod +x everspark-webui/start_webui.sh
everspark-webui/start_webui.sh
```

Open `http://127.0.0.1:8780`. For a remote Pod, use SSH port forwarding during
the first test:

```bash
ssh -L 8780:127.0.0.1:8780 <pod-ssh-target>
```

## Configuration

The defaults match the current repository:

- Orchestrator: `http://127.0.0.1:8765`
- ComfyUI: `http://127.0.0.1:8188`
- WebUI: `http://127.0.0.1:8780`

Copy `config.example.json` to `config.json` only when an override is needed.
Environment variables can also override individual settings:

- `EVERSPARK_WEBUI_HOST`
- `EVERSPARK_WEBUI_PORT`
- `EVERSPARK_ORCHESTRATOR_URL`
- `EVERSPARK_COMFYUI_URL`
- `EVERSPARK_WEBUI_REQUEST_TIMEOUT`
- `EVERSPARK_COMFYUI_TIMEOUT`
- `EVERSPARK_WEBUI_CONFIG`

Do not commit credentials or Cloudflare tunnel tokens into this directory.
