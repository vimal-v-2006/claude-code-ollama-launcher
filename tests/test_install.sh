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
  "$TEMP/home/prefix/bin/claude-code-ollama-launcher" --version | grep -F 'Claude Code Local Launcher'
desktop-file-validate "$TEMP/home/data/applications/claude-code-ollama-launcher.desktop"

# A normal upgrade must accept the exact launcher-owned command symlink and manifest.
grep -v '^config=' "$TEMP/home/data/claude-code-ollama-launcher/install-manifest.txt" > "$TEMP/legacy-manifest"
mv "$TEMP/legacy-manifest" "$TEMP/home/data/claude-code-ollama-launcher/install-manifest.txt"
HOME="$TEMP/home" XDG_DATA_HOME="$TEMP/home/data" XDG_CONFIG_HOME="$TEMP/home/config" PREFIX="$TEMP/home/prefix" PATH="$TEMP/bin:$PATH" \
  "$ROOT/install.sh" --no-system-helper >/dev/null
grep -Fx "config=$TEMP/home/config/claude-code-ollama-launcher" "$TEMP/home/data/claude-code-ollama-launcher/install-manifest.txt" >/dev/null
printf 'owned upgrade: OK\n'

mkdir -p "$TEMP/home/config/claude-code-ollama-launcher"
printf '{}\n' > "$TEMP/home/config/claude-code-ollama-launcher/settings.json"
printf 'preserve\n' > "$TEMP/home/config/claude-code-ollama-launcher/unrelated-file"

HOME="$TEMP/home" XDG_DATA_HOME="$TEMP/home/data" XDG_CONFIG_HOME="$TEMP/home/config" PREFIX="$TEMP/home/prefix" \
  "$ROOT/uninstall.sh" --keep-system-helper --purge

test ! -e "$TEMP/home/prefix/bin/claude-code-ollama-launcher"
test ! -e "$TEMP/home/data/applications/claude-code-ollama-launcher.desktop"
test ! -e "$TEMP/home/data/claude-code-ollama-launcher"
test ! -e "$TEMP/home/config/claude-code-ollama-launcher/settings.json"
test -f "$TEMP/home/config/claude-code-ollama-launcher/unrelated-file"
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

# Reject a symlinked ownership manifest without touching its target.
mkdir -p "$TEMP/manifest/data/claude-code-ollama-launcher" "$TEMP/manifest/bin"
printf 'DO NOT MODIFY\n' > "$TEMP/manifest/marker"
ln -s "$TEMP/manifest/marker" "$TEMP/manifest/data/claude-code-ollama-launcher/install-manifest.txt"
if HOME="$TEMP/manifest" XDG_DATA_HOME="$TEMP/manifest/data" PREFIX="$TEMP/manifest/prefix" PATH="$TEMP/bin:$PATH" \
  "$ROOT/install.sh" --no-system-helper >/dev/null 2>&1; then
  echo 'installer accepted a symlinked ownership manifest' >&2
  exit 1
fi
grep -Fx 'DO NOT MODIFY' "$TEMP/manifest/marker" >/dev/null
printf 'manifest symlink refusal: OK\n'

# Reject ancestor symlinks so writes cannot escape the chosen installation roots.
mkdir -p "$TEMP/ancestor/foreign" "$TEMP/ancestor/home"
ln -s "$TEMP/ancestor/foreign" "$TEMP/ancestor/home/data"
if HOME="$TEMP/ancestor/home" XDG_DATA_HOME="$TEMP/ancestor/home/data" PREFIX="$TEMP/ancestor/home/prefix" PATH="$TEMP/bin:$PATH" \
  "$ROOT/install.sh" --no-system-helper >/dev/null 2>&1; then
  echo 'installer accepted a symlinked data-root ancestor' >&2
  exit 1
fi
test ! -e "$TEMP/ancestor/foreign/claude-code-ollama-launcher"
printf 'ancestor symlink refusal: OK\n'

# A forged manifest must not let uninstall remove an arbitrary matching file.
HOME="$TEMP/forged" XDG_DATA_HOME="$TEMP/forged/data" PREFIX="$TEMP/forged/prefix" PATH="$TEMP/bin:$PATH" \
  "$ROOT/install.sh" --no-system-helper >/dev/null
printf 'foreign data\n' > "$TEMP/forged/foreign-file"
sha256sum "$TEMP/forged/foreign-file" >> "$TEMP/forged/data/claude-code-ollama-launcher/install-manifest.txt"
if HOME="$TEMP/forged" XDG_DATA_HOME="$TEMP/forged/data" PREFIX="$TEMP/forged/prefix" \
  "$ROOT/uninstall.sh" --keep-system-helper >/dev/null 2>&1; then
  echo 'uninstaller accepted a forged arbitrary path' >&2
  exit 1
fi
test -f "$TEMP/forged/foreign-file"
printf 'forged-manifest refusal: OK\n'

# Uninstall must refuse a replaced destination ancestor and preserve matching foreign files.
HOME="$TEMP/uninstall-symlink" XDG_DATA_HOME="$TEMP/uninstall-symlink/data" PREFIX="$TEMP/uninstall-symlink/prefix" PATH="$TEMP/bin:$PATH" \
  "$ROOT/install.sh" --no-system-helper >/dev/null
mkdir -p "$TEMP/uninstall-symlink/foreign-applications"
cp "$TEMP/uninstall-symlink/data/applications/claude-code-ollama-launcher.desktop" \
  "$TEMP/uninstall-symlink/foreign-applications/claude-code-ollama-launcher.desktop"
rm -rf "$TEMP/uninstall-symlink/data/applications"
ln -s "$TEMP/uninstall-symlink/foreign-applications" "$TEMP/uninstall-symlink/data/applications"
if HOME="$TEMP/uninstall-symlink" XDG_DATA_HOME="$TEMP/uninstall-symlink/data" PREFIX="$TEMP/uninstall-symlink/prefix" \
  "$ROOT/uninstall.sh" --keep-system-helper >/dev/null 2>&1; then
  echo 'uninstaller accepted a symlinked destination ancestor' >&2
  exit 1
fi
test -f "$TEMP/uninstall-symlink/foreign-applications/claude-code-ollama-launcher.desktop"
printf 'uninstall ancestor symlink refusal: OK\n'

# Purge authorization is bound to the configuration path recorded at installation.
HOME="$TEMP/purge-binding" XDG_DATA_HOME="$TEMP/purge-binding/data" XDG_CONFIG_HOME="$TEMP/purge-binding/owned-config" \
  PREFIX="$TEMP/purge-binding/prefix" PATH="$TEMP/bin:$PATH" "$ROOT/install.sh" --no-system-helper >/dev/null
mkdir -p "$TEMP/purge-binding/foreign-config/claude-code-ollama-launcher"
printf 'foreign sentinel\n' > "$TEMP/purge-binding/foreign-config/claude-code-ollama-launcher/sentinel"
if HOME="$TEMP/purge-binding" XDG_DATA_HOME="$TEMP/purge-binding/data" XDG_CONFIG_HOME="$TEMP/purge-binding/foreign-config" \
  PREFIX="$TEMP/purge-binding/prefix" "$ROOT/uninstall.sh" --keep-system-helper --purge >/dev/null 2>&1; then
  echo 'uninstaller purged a configuration path not bound by the manifest' >&2
  exit 1
fi
test -f "$TEMP/purge-binding/foreign-config/claude-code-ollama-launcher/sentinel"
test -f "$TEMP/purge-binding/data/claude-code-ollama-launcher/install-manifest.txt"
printf 'configuration purge binding: OK\n'
