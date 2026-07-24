#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd)"
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT

valid_body='[Service]
Environment="OLLAMA_CONTEXT_LENGTH=65536"
Environment="OLLAMA_FLASH_ATTENTION=1"
Environment="OLLAMA_KV_CACHE_TYPE=q8_0"
Environment="OLLAMA_KEEP_ALIVE=10m"'
printf '%s\n' "$valid_body" > "$TEMP/legacy.conf"
printf '# Managed by Claude Code Local Launcher\n%s\n' "$valid_body" > "$TEMP/managed.conf"
printf '[Service]\nEnvironment="OLLAMA_CONTEXT_LENGTH=65536"\n' > "$TEMP/subset.conf"
printf '# Managed by Claude Code Local Launcher\n%s\nEnvironment="FOREIGN=1"\n' "$valid_body" > "$TEMP/foreign.conf"
ln -s "$TEMP/managed.conf" "$TEMP/symlink.conf"

"$ROOT/set-context" --validate-config "$TEMP/legacy.conf"
"$ROOT/set-context" --validate-config "$TEMP/managed.conf"
for rejected in subset.conf foreign.conf symlink.conf; do
  if "$ROOT/set-context" --validate-config "$TEMP/$rejected"; then
    echo "validator accepted foreign configuration: $rejected" >&2
    exit 1
  fi
done
printf 'strict systemd drop-in validation: OK\n'
