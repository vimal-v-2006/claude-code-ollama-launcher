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
CONFIG_DIR="$CONFIG_HOME/claude-code-ollama-launcher"
SCRIPT_DIR="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)"
LOCAL_HELPER="$SCRIPT_DIR/set-context"
LOCAL_HELPER_SHA=""
if [[ -f "$LOCAL_HELPER" ]]; then
  LOCAL_HELPER_SHA="$(sha256sum "$LOCAL_HELPER" | cut -d' ' -f1)"
fi

python3 - "$MANIFEST" "$APP_DIR" "$COMMAND_PATH" "$DATA_HOME/applications/claude-code-ollama-launcher.desktop" "$DATA_HOME/icons/hicolor/scalable/apps/claude-code-ollama-launcher.svg" "$SYSTEM_HELPER" "$CONFIG_DIR" "$PURGE" <<'PY'
import hashlib, os, pathlib, re, sys
manifest, app, command, desktop, icon, helper, config = map(pathlib.Path, sys.argv[1:8])
purge = sys.argv[8] == "true"
managed = {
    app / "app.py", app / "core.py", app / "run-claude-local",
    app / "uninstall.sh", app / "set-context", desktop, icon,
}
def reject_symlink_components(path: pathlib.Path) -> None:
    current = pathlib.Path(path.anchor)
    for part in path.parts[1:]:
        current /= part
        if os.path.lexists(current) and current.is_symlink():
            raise SystemExit(f"Refusing symlinked uninstall path component: {current}")
for path in [app, manifest, command.parent, desktop, icon, *managed]:
    reject_symlink_components(path)
if manifest.is_symlink() or not manifest.is_file() or app.is_symlink():
    raise SystemExit(f"No trusted ownership manifest found; preserving managed files: {manifest}")
lines = manifest.read_text(encoding="utf-8").splitlines()
if not lines or not re.fullmatch(r"version=[0-9]+\.[0-9]+\.[0-9]+", lines[0]):
    raise SystemExit("Malformed or foreign ownership manifest; preserving files")
legacy_headers = [f"command={command}", f"desktop={desktop}", f"icon={icon}", f"system_helper={helper}"]
current_headers = [*legacy_headers, f"config={config}"]
if lines[1:6] == current_headers:
    record_lines = lines[6:]
elif not purge and lines[1:5] == legacy_headers:
    record_lines = lines[5:]
else:
    raise SystemExit("Manifest does not authorize the requested configuration purge")
records = {}
for line in record_lines:
    match = re.fullmatch(r"([0-9a-f]{64})  (/.+)", line)
    if not match:
        raise SystemExit("Malformed ownership manifest record; preserving files")
    records[pathlib.Path(match.group(2))] = match.group(1)
if set(records) != managed:
    raise SystemExit("Ownership manifest contains unexpected paths; preserving files")
if purge:
    reject_symlink_components(config)
    reject_symlink_components(config / "settings.json")
if command.is_symlink() and pathlib.Path(os.path.realpath(command)) == app / "run-claude-local":
    command.unlink()
for path, expected in records.items():
    if not path.is_file() or path.is_symlink():
        continue
    actual = hashlib.sha256(path.read_bytes()).hexdigest()
    if actual == expected:
        path.unlink()
    else:
        print(f"Preserving modified file: {path}", file=sys.stderr)
manifest.unlink()
if purge:
    settings = config / "settings.json"
    if settings.exists():
        if not settings.is_file() or settings.is_symlink():
            raise SystemExit(f"Refusing unverified settings path: {settings}")
        settings.unlink()
    try:
        config.rmdir()
    except FileNotFoundError:
        pass
    except OSError:
        print(f"Preserving non-empty configuration directory: {config}", file=sys.stderr)
PY
rmdir "$APP_DIR" 2>/dev/null || true

if $REMOVE_SYSTEM_HELPER && [[ -e "$SYSTEM_HELPER" || -e "$SYSTEM_CONFIG" ]]; then
  command -v pkexec >/dev/null || { echo "pkexec is required to remove the system helper" >&2; exit 1; }
  if [[ -n "$LOCAL_HELPER_SHA" && -f "$SYSTEM_HELPER" ]] && [[ "$LOCAL_HELPER_SHA" == "$(sha256sum "$SYSTEM_HELPER" | cut -d' ' -f1)" ]]; then
    pkexec rm -f "$SYSTEM_HELPER"
    if [[ -e "$SYSTEM_CONFIG" ]]; then
      echo "Preserving Ollama context configuration: $SYSTEM_CONFIG" >&2
    fi
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
