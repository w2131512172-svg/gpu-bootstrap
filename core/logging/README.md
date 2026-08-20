# EverSpark Forge logging redesign

Status: planned  
Scope owner: `core/logging`

## Why this rewrite is needed

The repository currently has one small shared shell helper, but many modules still define their own `log()`, call `echo` or `print` directly, choose independent file paths, and duplicate level labels inside messages. This makes recovery failures hard to correlate and forces callers such as WebUI to know implementation-specific log filenames.

The rewrite must preserve service startup behavior while making every record attributable, searchable, and safe to expose through future status APIs.

## Naming and configuration contract

The canonical product name is **EverSpark Forge**. Module names such as **ComfyUI Forge**, **Ollama Forge**, **Orchestrator**, and **EverSpark WebUI** remain valid.

| Setting | Default | Purpose |
| --- | --- | --- |
| `EVERSPARK_LOG_DIR` | `/root/everspark_logs` | Root directory for managed logs |
| `EVERSPARK_LOG_LEVEL` | `INFO` | Minimum emitted level |
| `EVERSPARK_LOG_FORMAT` | `text` | `text` for operators, `json` for ingestion |
| `EVERSPARK_RUN_ID` | generated per recovery/start run | Correlates records across scripts and services |
| `EVERSPARK_LOG_CONSOLE` | `1` | Mirrors managed records to the console |

All product-owned configuration must use the `EVERSPARK_*` namespace; historical brand and variable prefixes are forbidden.

## Record contract

Every managed record must contain:

- RFC 3339 timestamp with timezone
- level: `DEBUG`, `INFO`, `OK`, `WARN`, or `ERROR`
- component, for example `comfyui.recovery`, `r2.pull`, or `tunnel`
- event name suitable for filtering
- message intended for humans
- run ID and process ID
- optional key/value fields with secrets redacted

Text output should remain concise:

```text
2026-08-21T10:15:30+09:00 INFO  comfyui.recovery step.start run_id=... step=r2_pull
```

JSON output must carry the same fields rather than embedding level or component labels in the message.

## Public APIs

### Shell

`core/logging/log.sh` will own:

- `core_log_init COMPONENT [LOG_FILE]`
- `core_debug|core_info|core_ok|core_warn|core_error EVENT MESSAGE [key=value ...]`
- `core_step_start|core_step_end`
- `core_run_step NAME COMMAND...`
- `core_die EVENT MESSAGE`

Callers must stop defining local timestamp, `log()`, `die()`, and separator implementations.

### Python

Add a Python adapter under `core/logging` using the standard `logging` package. It must emit the same record contract and read the same `EVERSPARK_*` settings. WebUI and Orchestrator HTTP access logs must use this adapter instead of `print()`.

Shell and Python implementations share a contract, not a process or IPC dependency.

## File layout

The first implementation should keep operational files simple:

```text
/root/everspark_logs/
  recovery.log
  bootstrap.log
  comfyui.log
  ollama.log
  orchestrator.log
  webui.log
  tunnel.log
  r2.log
```

A later status API may expose a manifest of logical log names. WebUI must not hard-code physical paths.

## Migration phases

1. **Canonical naming** — remove historical names and move configuration to `EVERSPARK_*`.
2. **Logging foundation** — rewrite the shell helper, add the Python adapter, record formatter, redaction, and unit tests.
3. **Critical recovery path** — migrate bootstrap, `comfy_start.sh`, `start_all.sh`, dependency repair, R2, and tunnel scripts.
4. **Long-running services** — migrate Ollama Forge, Orchestrator, and EverSpark WebUI; separate access logs from application events where useful.
5. **Operations** — add rotation/retention, a log manifest/status API, and documentation for collection.

Each phase must be independently runnable. Do not combine a logging-behavior rewrite with unrelated dependency or service changes.

## Safety rules

- Never log tokens, credentials, full environment dumps, authorization headers, or private rclone configuration.
- Errors go to stderr while optionally being mirrored to the configured file.
- Logging failure must not silently hide the original command failure.
- Directory creation is centralized and uses restrictive permissions.
- Background services keep stdout/stderr capture, but lifecycle events go through the managed logger.
- Existing operators get an explicit migration note when a path or environment variable changes.

## Acceptance criteria

- Repository search finds no historical product names or variable prefixes.
- ShellCheck and `bash -n` pass for migrated shell files.
- Python logging tests cover text/JSON formats, level filtering, redaction, and invalid configuration.
- A single recovery run has one run ID from bootstrap through service startup.
- Every critical step emits paired start/end events with duration and exit status.
- WebUI and Orchestrator no longer use raw `print()` for operational logging.
- Rotation/retention prevents unbounded disk growth.
