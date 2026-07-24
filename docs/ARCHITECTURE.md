# Architecture

## Components

- `app.py`: GTK interface and lifecycle orchestration.
- `core.py`: testable model discovery, settings, context parsing, and command construction.
- `set-context`: root-owned runtime helper that updates a fixed systemd drop-in.
- `run-claude-local`: portable installed wrapper.
- `install.sh` / `uninstall.sh`: user desktop integration and privileged-helper lifecycle.

## Launch path

```text
GTK launcher
  -> choose Ollama or custom llama.cpp endpoint
  -> Ollama: validate model, optionally apply context and restart ollama.service
  -> custom: discover alias from /v1/models; leave all runtime settings to server
  -> gnome-terminal
  -> ollama launch claude --model <tag>, or claude with ANTHROPIC_BASE_URL
  -> official Claude Code native terminal UI
```

## Data flow

Ollama discovery reads `GET http://127.0.0.1:11434/api/tags`; custom discovery reads `GET <endpoint>/v1/models`. No launcher API is exposed. Preferences contain backend, model tag, context choice, endpoint, and project path and are written mode `0600` under the XDG config home.

## Context control

Ollama's Anthropic-compatible endpoint does not receive a launcher-specific `num_ctx` value from Claude Code. Context is therefore set at the Ollama service layer with `OLLAMA_CONTEXT_LENGTH`. The helper also enables Flash Attention and a `q8_0` KV cache.
