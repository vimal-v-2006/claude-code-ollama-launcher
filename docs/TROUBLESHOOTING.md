# Troubleshooting

## The launcher says Ollama is unavailable

```bash
systemctl is-active ollama
curl -fsS http://127.0.0.1:11434/api/tags | jq
```

If the service is inactive:

```bash
sudo systemctl restart ollama
```

## The custom llama.cpp endpoint is unavailable

The launcher expects an Anthropic-compatible recent `llama-server` and checks `<endpoint>/v1/models`.

```bash
curl -fsS http://127.0.0.1:8080/v1/models | jq
curl -fsS http://127.0.0.1:8080/health
```

Enter the server root (`http://127.0.0.1:8080`) or the same URL ending in `/v1`. The launcher intentionally does not set context, GPU layers, sampling, or model files for this backend; restart `llama-server` with the arguments you want.

## The model does not appear

```bash
ollama list
ollama pull <model-tag>
```

Click **Refresh models** after the pull finishes. The launcher requires the exact tag shown by `ollama list`.

## Context changes fail

Check that the root-owned helper exists:

```bash
stat /usr/local/libexec/claude-code-ollama-launcher/set-context
```

Reinstall if it is missing:

```bash
./install.sh
```

Changing context requires a PolicyKit authentication dialog because it updates a systemd service drop-in and restarts `ollama.service`.

Inspect the active value:

```bash
systemctl show ollama -p Environment --no-pager
```

## Ollama runs out of memory

Select a smaller context window. Stop a loaded model before retrying:

```bash
ollama stop <model-tag>
```

Inspect GPU and model allocation:

```bash
ollama ps
nvidia-smi
```

128K context can require substantially more memory than 32K or 64K.

## Claude Code opens but asks for login

Always start it from this launcher or through `ollama launch claude`. Running `claude` directly may use Claude Code's default Anthropic configuration instead of Ollama's local compatibility endpoint.

Verify the integration directly:

```bash
ollama launch claude --model <local-tag> --yes -- --version
```

## Claude Code cannot use tools

Choose an Ollama model that advertises tool capability:

```bash
ollama show <model-tag>
```

Look for `tools` under **Capabilities**.

## GNOME Terminal is unavailable

The current release targets GNOME Terminal. Install it with your distribution's package manager or change `claude_command()` in `core.py` for another terminal emulator.

## Reset launcher preferences

```bash
rm -rf ~/.config/claude-code-ollama-launcher
```

## Diagnostics

```bash
claude-code-ollama-launcher --self-test | python3 -m json.tool
systemctl --failed --no-pager
journalctl -u ollama -n 100 --no-pager
```
