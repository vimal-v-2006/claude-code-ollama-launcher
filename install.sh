#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_PATH="$(readlink -f -- "${BASH_SOURCE[0]}")"
SOURCE_DIR="$(cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd)"
VERSION="$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import core; print(core.VERSION)' "$SOURCE_DIR")"
NO_SYSTEM_HELPER=false

for arg in "$@"; do
  case "$arg" in
    --no-system-helper) NO_SYSTEM_HELPER=true ;;
    --help)
      echo "Usage: ./install.sh [--no-system-helper]"
      echo "Environment: PREFIX, XDG_DATA_HOME, XDG_CONFIG_HOME"
      exit 0
      ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

for command in python3 gnome-terminal; do
  command -v "$command" >/dev/null || { echo "Missing prerequisite: $command" >&2; exit 1; }
done
/usr/bin/python3 -c 'import gi; gi.require_version("Gtk", "3.0"); from gi.repository import Gtk' 2>/dev/null || {
  echo "Missing prerequisite: Python GTK 3 bindings (python3-gi and gir1.2-gtk-3.0)" >&2
  exit 1
}
if ! command -v ollama >/dev/null && ! command -v claude >/dev/null; then
  echo "Install Ollama (Ollama mode) or the official Claude Code CLI (custom endpoint mode) first." >&2
  exit 1
fi

PREFIX="${PREFIX:-$HOME/.local}"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
PREFIX="$(python3 -c 'import os,sys; print(os.path.abspath(os.path.expanduser(sys.argv[1])))' "$PREFIX")"
DATA_HOME="$(python3 -c 'import os,sys; print(os.path.abspath(os.path.expanduser(sys.argv[1])))' "$DATA_HOME")"
CONFIG_HOME="$(python3 -c 'import os,sys; print(os.path.abspath(os.path.expanduser(sys.argv[1])))' "$CONFIG_HOME")"
APP_DIR="$DATA_HOME/claude-code-ollama-launcher"
BIN_DIR="$PREFIX/bin"
APPLICATIONS_DIR="$DATA_HOME/applications"
ICON_DIR="$DATA_HOME/icons/hicolor/scalable/apps"
COMMAND_PATH="$BIN_DIR/claude-code-ollama-launcher"
DESKTOP_PATH="$APPLICATIONS_DIR/claude-code-ollama-launcher.desktop"
ICON_PATH="$ICON_DIR/claude-code-ollama-launcher.svg"
CONFIG_DIR="$CONFIG_HOME/claude-code-ollama-launcher"
SYSTEM_HELPER_DIR="/usr/local/libexec/claude-code-ollama-launcher"
SYSTEM_HELPER="$SYSTEM_HELPER_DIR/set-context"

MANIFEST="$APP_DIR/install-manifest.txt"
python3 - "$APP_DIR" "$MANIFEST" "$COMMAND_PATH" "$DESKTOP_PATH" "$ICON_PATH" "$SYSTEM_HELPER" "$CONFIG_DIR" <<'PY'
import os, pathlib, re, sys
app, manifest, command, desktop, icon, helper, config = map(pathlib.Path, sys.argv[1:])
managed = {
    app / "app.py", app / "core.py", app / "run-claude-local",
    app / "uninstall.sh", app / "set-context", desktop, icon,
}
def reject_symlink_components(path: pathlib.Path) -> None:
    current = pathlib.Path(path.anchor)
    for part in path.parts[1:]:
        current /= part
        if os.path.lexists(current) and current.is_symlink():
            raise SystemExit(f"Refusing symlinked path component: {current}")
for path in [app, manifest, command.parent, desktop, icon, *managed]:
    reject_symlink_components(path)
if app.exists():
    if not app.is_dir() or not manifest.is_file() or manifest.is_symlink():
        raise SystemExit(f"Refusing to overwrite an unowned application directory: {app}")
    lines = manifest.read_text(encoding="utf-8").splitlines()
    if not lines or not re.fullmatch(r"version=[0-9]+\.[0-9]+\.[0-9]+", lines[0]):
        raise SystemExit("Refusing malformed or foreign ownership manifest")
    legacy_headers = [f"command={command}", f"desktop={desktop}", f"icon={icon}", f"system_helper={helper}"]
    current_headers = [*legacy_headers, f"config={config}"]
    if lines[1:6] == current_headers:
        records = lines[6:]
    elif lines[1:5] == legacy_headers:
        records = lines[5:]
    else:
        raise SystemExit("Refusing malformed or foreign ownership manifest")
    recorded = set()
    for line in records:
        match = re.fullmatch(r"([0-9a-f]{64})  (/.+)", line)
        if not match:
            raise SystemExit("Refusing malformed ownership manifest record")
        recorded.add(pathlib.Path(match.group(2)))
    if recorded != managed:
        raise SystemExit("Refusing ownership manifest with unexpected paths")
PY
if [[ -e "$COMMAND_PATH" || -L "$COMMAND_PATH" ]]; then
  if [[ ! -L "$COMMAND_PATH" || "$(readlink -f -- "$COMMAND_PATH")" != "$APP_DIR/run-claude-local" ]]; then
    echo "Refusing to replace foreign command: $COMMAND_PATH" >&2
    exit 1
  fi
fi

if ! $NO_SYSTEM_HELPER; then
  for command in pkexec systemctl curl; do
    command -v "$command" >/dev/null || { echo "Missing context-helper prerequisite: $command" >&2; exit 1; }
  done
  pkexec install -d -m 755 "$SYSTEM_HELPER_DIR"
  pkexec install -m 755 "$SOURCE_DIR/set-context" "$SYSTEM_HELPER"
fi

install -d -m 755 "$APP_DIR" "$BIN_DIR" "$APPLICATIONS_DIR" "$ICON_DIR"
install -m 755 "$SOURCE_DIR/app.py" "$SOURCE_DIR/run-claude-local" "$SOURCE_DIR/uninstall.sh" "$SOURCE_DIR/set-context" "$APP_DIR/"
install -m 644 "$SOURCE_DIR/core.py" "$APP_DIR/"
install -m 644 "$SOURCE_DIR/icon.svg" "$ICON_PATH"
ln -sfn "$APP_DIR/run-claude-local" "$COMMAND_PATH"

python3 - "$SOURCE_DIR/claude-code-ollama-launcher.desktop.in" "$DESKTOP_PATH" "$COMMAND_PATH" <<'PY'
import pathlib, sys
source, destination, executable = map(pathlib.Path, sys.argv[1:])
escaped = str(executable).replace('\\', '\\\\').replace(' ', '\\ ')
text = source.read_text(encoding='utf-8').replace('@EXEC@', escaped)
destination.write_text(text, encoding='utf-8')
destination.chmod(0o644)
PY

if command -v desktop-file-validate >/dev/null; then
  desktop-file-validate "$DESKTOP_PATH"
fi
if command -v update-desktop-database >/dev/null; then
  update-desktop-database "$APPLICATIONS_DIR" >/dev/null 2>&1 || true
fi
if command -v gtk-update-icon-cache >/dev/null; then
  gtk-update-icon-cache -f -t "$DATA_HOME/icons/hicolor" >/dev/null 2>&1 || true
fi

MANIFEST_TMP="$(mktemp "$APP_DIR/.install-manifest.XXXXXX")"
trap 'rm -f "$MANIFEST_TMP"' EXIT
{
  printf 'version=%s\n' "$VERSION"
  printf 'command=%s\n' "$COMMAND_PATH"
  printf 'desktop=%s\n' "$DESKTOP_PATH"
  printf 'icon=%s\n' "$ICON_PATH"
  printf 'system_helper=%s\n' "$SYSTEM_HELPER"
  printf 'config=%s\n' "$CONFIG_DIR"
  sha256sum "$APP_DIR/app.py" "$APP_DIR/core.py" "$APP_DIR/run-claude-local" "$APP_DIR/uninstall.sh" "$APP_DIR/set-context" "$DESKTOP_PATH" "$ICON_PATH"
} > "$MANIFEST_TMP"
chmod 644 "$MANIFEST_TMP"
mv -f "$MANIFEST_TMP" "$MANIFEST"
trap - EXIT

printf '\nInstalled %s %s\n' "Claude Code Local Launcher" "$VERSION"
printf 'Application menu: Claude Code Local Launcher\n'
printf 'Command: %s\n' "$COMMAND_PATH"
if $NO_SYSTEM_HELPER; then
  printf 'Context changes are disabled because --no-system-helper was used.\n'
else
  printf 'Context control helper: %s\n' "$SYSTEM_HELPER"
fi
