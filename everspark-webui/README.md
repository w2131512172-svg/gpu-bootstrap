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

WebUI lifecycle, request failures, and HTTP access records are written to
`${EVERSPARK_LOG_DIR:-/root/everspark_logs}/webui.log`. Set
`EVERSPARK_WEBUI_LOG` only when a dedicated path override is required.

Runtime endpoints:

- `GET /api/health`: ComfyUI and Orchestrator compatibility health check.
- `GET /api/runtime/status`: service state plus managed-log summary.
- `GET /api/runtime/logs`: manifest-backed log metadata without log contents.

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
- `EVERSPARK_LOG_DIR`
- `EVERSPARK_LOG_MANIFEST`

## Cloudflare Tunnel

The WebUI tunnel uses the shared implementation in `core/network/tunnel`.
Only module entrypoints and a credential-free configuration example live here.

On a new Pod, prepare the deployment files:

```bash
cp everspark-webui/tunnel/env.example /root/.env.webui
chmod 600 /root/.env.webui
```

Replace `REPLACE_WITH_TUNNEL_UUID` in `/root/.env.webui`, then place the
matching tunnel credential at `/root/<Tunnel-UUID>.json`.

Start, check, or stop the dedicated WebUI tunnel with:

```bash
bash everspark-webui/tunnel/start_tunnel.sh
bash everspark-webui/tunnel/check_tunnel.sh
bash everspark-webui/tunnel/stop_tunnel.sh
```

The start command renders `/root/.cloudflared/webui.yml` at runtime from the
shared Core template. The generated file is deployment state and must not be
committed.

Do not commit credentials, `/root/.env.webui`, generated tunnel configuration,
or Cloudflare tunnel tokens into this directory.
