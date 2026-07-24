#!/usr/bin/env bash
set -Eeuo pipefail

PURGE=false
REMOVE_SYSTEM_HELPER=true
for arg in "$@"; do
  case "$arg" in
    --purge) PURGE=true ;;
    --keep-system-helper) REMOVE_SYSTEM_HELPER=false ;;
    --help)
      echo "Usage: ./uninstall.sh [--purge] [--keep-system-helper]"
      exit 0
      ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

PREFIX="${PREFIX:-$HOME/.local}"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
PREFIX="$(python3 -c 'import os,sys; print(os.path.abspath(os.path.expanduser(sys.argv[1])))' "$PREFIX")"
DATA_HOME="$(python3 -c 'import os,sys; print(os.path.abspath(os.path.expanduser(sys.argv[1])))' "$DATA_HOME")"
CONFIG_HOME="$(python3 -c 'import os,sys; print(os.path.abspath(os.path.expanduser(sys.argv[1])))' "$CONFIG_HOME")"
APP_DIR="$DATA_HOME/claude-code-ollama-launcher"
COMMAND_PATH="$PREFIX/bin/claude-code-ollama-launcher"
SYSTEM_HELPER="/usr/local/libexec/claude-code-ollama-launcher/set-context"
SYSTEM_CONFIG="/etc/systemd/system/ollama.service.d/90-claude-code-ollama-context.conf"
MANIFEST="$APP_DIR/install-manifest.txt"
SCRIPT_DIR="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)"
LOCAL_HELPER="$SCRIPT_DIR/set-context"
LOCAL_HELPER_SHA=""
if [[ -f "$LOCAL_HELPER" ]]; then
  LOCAL_HELPER_SHA="$(sha256sum "$LOCAL_HELPER" | cut -d' ' -f1)"
fi

if [[ -L "$COMMAND_PATH" ]] && [[ "$(readlink -f -- "$COMMAND_PATH")" == "$APP_DIR/run-claude-local" ]]; then
  rm -f "$COMMAND_PATH"
fi

python3 - "$MANIFEST" <<'PY'
import hashlib, pathlib, sys
manifest = pathlib.Path(sys.argv[1])
if not manifest.is_file():
    print(f"No ownership manifest found; preserving managed files: {manifest}", file=sys.stderr)
    raise SystemExit(0)
for line in manifest.read_text(encoding="utf-8").splitlines():
    if "  " not in line or len(line.split("  ", 1)[0]) != 64:
        continue
    expected, raw_path = line.split("  ", 1)
    path = pathlib.Path(raw_path)
    if not path.is_file() or path.is_symlink():
        continue
    actual = hashlib.sha256(path.read_bytes()).hexdigest()
    if actual == expected:
        path.unlink()
    else:
        print(f"Preserving modified file: {path}", file=sys.stderr)
manifest.unlink(missing_ok=True)
PY
rmdir "$APP_DIR" 2>/dev/null || true

if $PURGE; then
  rm -rf "$CONFIG_HOME/claude-code-ollama-launcher"
fi

if $REMOVE_SYSTEM_HELPER && [[ -e "$SYSTEM_HELPER" || -e "$SYSTEM_CONFIG" ]]; then
  command -v pkexec >/dev/null || { echo "pkexec is required to remove the system helper" >&2; exit 1; }
  if [[ -n "$LOCAL_HELPER_SHA" && -f "$SYSTEM_HELPER" ]] && [[ "$LOCAL_HELPER_SHA" == "$(sha256sum "$SYSTEM_HELPER" | cut -d' ' -f1)" ]]; then
    pkexec rm -f "$SYSTEM_HELPER"
    [[ ! -e "$SYSTEM_CONFIG" ]] || pkexec rm -f "$SYSTEM_CONFIG"
    pkexec systemctl daemon-reload
    pkexec systemctl restart ollama.service
    pkexec rmdir /usr/local/libexec/claude-code-ollama-launcher 2>/dev/null || true
  else
    echo "Preserving modified or unverified system helper: $SYSTEM_HELPER" >&2
  fi
fi

if command -v update-desktop-database >/dev/null; then
  update-desktop-database "$DATA_HOME/applications" >/dev/null 2>&1 || true
fi
printf 'Claude Code Local Launcher uninstalled.\n'
$PURGE || printf 'Settings preserved in %s\n' "$CONFIG_HOME/claude-code-ollama-launcher"
