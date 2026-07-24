#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/.." && pwd)"
VERSION="$(python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); import core; print(core.VERSION)' "$ROOT")"
NAME="claude-code-ollama-launcher-$VERSION"
DIST="$ROOT/dist"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$DIST" "$STAGE/$NAME"

python3 - "$ROOT" "$STAGE/$NAME" <<'PY'
import os, pathlib, shutil, sys
source, destination = map(pathlib.Path, sys.argv[1:])
excluded = {'.git', 'dist', 'build', '__pycache__', '.pytest_cache'}
for item in source.iterdir():
    if item.name in excluded or item.name.endswith(('.tar.gz', '.sha256')):
        continue
    target = destination / item.name
    if item.is_dir():
        shutil.copytree(item, target, ignore=shutil.ignore_patterns('__pycache__', '*.pyc'))
    else:
        shutil.copy2(item, target)
PY

tar --sort=name --mtime='UTC 2020-01-01' --owner=0 --group=0 --numeric-owner -C "$STAGE" -czf "$DIST/$NAME.tar.gz" "$NAME"
(
  cd "$DIST"
  sha256sum "$NAME.tar.gz" > "$NAME.tar.gz.sha256"
)
printf '%s\n' "$DIST/$NAME.tar.gz" "$DIST/$NAME.tar.gz.sha256"
