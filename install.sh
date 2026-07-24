#!/usr/bin/env bash
set -Eeuo pipefail

VERSION="1.0.0"
SCRIPT_PATH="$(readlink -f -- "${BASH_SOURCE[0]}")"
SOURCE_DIR="$(cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd)"
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
if ! command -v ollama >/dev/null && ! command -v claude >/dev/null; then
  echo "Install Ollama (Ollama mode) or the official Claude Code CLI (custom endpoint mode) first." >&2
  exit 1
fi

PREFIX="${PREFIX:-$HOME/.local}"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
PREFIX="$(python3 -c 'import os,sys; print(os.path.abspath(os.path.expanduser(sys.argv[1])))' "$PREFIX")"
DATA_HOME="$(python3 -c 'import os,sys; print(os.path.abspath(os.path.expanduser(sys.argv[1])))' "$DATA_HOME")"
APP_DIR="$DATA_HOME/claude-code-ollama-launcher"
BIN_DIR="$PREFIX/bin"
APPLICATIONS_DIR="$DATA_HOME/applications"
ICON_DIR="$DATA_HOME/icons/hicolor/scalable/apps"
COMMAND_PATH="$BIN_DIR/claude-code-ollama-launcher"
DESKTOP_PATH="$APPLICATIONS_DIR/claude-code-ollama-launcher.desktop"
ICON_PATH="$ICON_DIR/claude-code-ollama-launcher.svg"
SYSTEM_HELPER_DIR="/usr/local/libexec/claude-code-ollama-launcher"
SYSTEM_HELPER="$SYSTEM_HELPER_DIR/set-context"

MANIFEST="$APP_DIR/install-manifest.txt"
if [[ -L "$APP_DIR" ]]; then
  echo "Refusing symlinked application directory: $APP_DIR" >&2
  exit 1
fi
if [[ -e "$APP_DIR" && ! -f "$MANIFEST" ]]; then
  echo "Refusing to overwrite an unowned application directory: $APP_DIR" >&2
  exit 1
fi
if [[ -e "$COMMAND_PATH" || -L "$COMMAND_PATH" ]]; then
  if [[ ! -L "$COMMAND_PATH" || "$(readlink -f -- "$COMMAND_PATH")" != "$APP_DIR/run-claude-local" ]]; then
    echo "Refusing to replace foreign command: $COMMAND_PATH" >&2
    exit 1
  fi
fi
for destination in "$APP_DIR/app.py" "$APP_DIR/core.py" "$APP_DIR/run-claude-local" "$APP_DIR/uninstall.sh" "$APP_DIR/set-context" "$DESKTOP_PATH" "$ICON_PATH"; do
  if [[ -L "$destination" ]]; then
    echo "Refusing symlinked destination: $destination" >&2
    exit 1
  fi
done

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

if ! $NO_SYSTEM_HELPER; then
  command -v pkexec >/dev/null || { echo "pkexec is required for context control" >&2; exit 1; }
  pkexec install -d -m 755 "$SYSTEM_HELPER_DIR"
  pkexec install -m 755 "$SOURCE_DIR/set-context" "$SYSTEM_HELPER"
fi

{
  printf 'version=%s\n' "$VERSION"
  printf 'command=%s\n' "$COMMAND_PATH"
  printf 'desktop=%s\n' "$DESKTOP_PATH"
  printf 'icon=%s\n' "$ICON_PATH"
  printf 'system_helper=%s\n' "$SYSTEM_HELPER"
  sha256sum "$APP_DIR/app.py" "$APP_DIR/core.py" "$APP_DIR/run-claude-local" "$APP_DIR/uninstall.sh" "$APP_DIR/set-context" "$DESKTOP_PATH" "$ICON_PATH"
} > "$MANIFEST"
chmod 644 "$MANIFEST"

printf '\nInstalled %s %s\n' "Claude Code Local Launcher" "$VERSION"
printf 'Application menu: Claude Code Local Launcher\n'
printf 'Command: %s\n' "$COMMAND_PATH"
if $NO_SYSTEM_HELPER; then
  printf 'Context changes are disabled because --no-system-helper was used.\n'
else
  printf 'Context control helper: %s\n' "$SYSTEM_HELPER"
fi
