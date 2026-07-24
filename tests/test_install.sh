#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd)"
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT
mkdir -p "$TEMP/home" "$TEMP/bin"
for command in ollama gnome-terminal; do
  printf '#!/usr/bin/env bash\nexit 0\n' > "$TEMP/bin/$command"
  chmod 755 "$TEMP/bin/$command"
done

HOME="$TEMP/home" \
XDG_DATA_HOME="$TEMP/home/data" \
XDG_CONFIG_HOME="$TEMP/home/config" \
PREFIX="$TEMP/home/prefix" \
PATH="$TEMP/bin:$PATH" \
  "$ROOT/install.sh" --no-system-helper

test -L "$TEMP/home/prefix/bin/claude-code-ollama-launcher"
test -f "$TEMP/home/data/applications/claude-code-ollama-launcher.desktop"
test -f "$TEMP/home/data/icons/hicolor/scalable/apps/claude-code-ollama-launcher.svg"
HOME="$TEMP/home" XDG_DATA_HOME="$TEMP/home/data" XDG_CONFIG_HOME="$TEMP/home/config" PREFIX="$TEMP/home/prefix" \
  "$TEMP/home/prefix/bin/claude-code-ollama-launcher" --version | grep -F '1.0.0'
desktop-file-validate "$TEMP/home/data/applications/claude-code-ollama-launcher.desktop"

HOME="$TEMP/home" XDG_DATA_HOME="$TEMP/home/data" XDG_CONFIG_HOME="$TEMP/home/config" PREFIX="$TEMP/home/prefix" \
  "$ROOT/uninstall.sh" --keep-system-helper --purge

test ! -e "$TEMP/home/prefix/bin/claude-code-ollama-launcher"
test ! -e "$TEMP/home/data/applications/claude-code-ollama-launcher.desktop"
test ! -e "$TEMP/home/data/claude-code-ollama-launcher"
printf 'isolated install/uninstall: OK\n'

# Refuse an application-directory collision without an ownership manifest.
mkdir -p "$TEMP/foreign/data/claude-code-ollama-launcher" "$TEMP/foreign/bin"
for command in ollama gnome-terminal; do
  printf '#!/usr/bin/env bash\nexit 0\n' > "$TEMP/foreign/bin/$command"
  chmod 755 "$TEMP/foreign/bin/$command"
done
if HOME="$TEMP/foreign" XDG_DATA_HOME="$TEMP/foreign/data" PREFIX="$TEMP/foreign/prefix" PATH="$TEMP/foreign/bin:$PATH" \
  "$ROOT/install.sh" --no-system-helper >/dev/null 2>&1; then
  echo 'installer unexpectedly overwrote a foreign directory' >&2
  exit 1
fi
printf 'foreign collision refusal: OK\n'

# Preserve a user-modified installed file during uninstall.
HOME="$TEMP/modified" XDG_DATA_HOME="$TEMP/modified/data" PREFIX="$TEMP/modified/prefix" PATH="$TEMP/bin:$PATH" \
  "$ROOT/install.sh" --no-system-helper >/dev/null
printf '\n# local modification\n' >> "$TEMP/modified/data/claude-code-ollama-launcher/core.py"
HOME="$TEMP/modified" XDG_DATA_HOME="$TEMP/modified/data" PREFIX="$TEMP/modified/prefix" \
  "$ROOT/uninstall.sh" --keep-system-helper >/dev/null

test -f "$TEMP/modified/data/claude-code-ollama-launcher/core.py"
printf 'modified-file preservation: OK\n'
