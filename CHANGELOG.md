# Changelog

All notable changes are documented here.

## [1.0.2] - 2026-07-24

### Security

- Constrained installer and uninstaller manifests to canonical launcher-owned paths; symlinked ancestors, foreign paths, and unbound configuration purges are rejected while unrelated configuration content is preserved.
- Removed environment overrides for the managed Ollama endpoint and privileged configuration path.
- Made settings writes exclusive, private, and atomic.
- Refused foreign systemd drop-ins and preserved service configuration during uninstall.

### Changed

- Release publication now reuses the exact archive tested by CI, pins third-party actions to immutable commits, and normalizes archive modes.
- The GTK window is resizable for accessibility.

## [1.0.1] - 2026-07-24

### Security

- Fixed the privileged context-helper path to a root-owned system location and rejected symlinks or writable helper paths.
- Made a missing Ollama context drop-in explicit so the selected default is applied on first launch.

## [1.0.0] - 2026-07-24

### Added

- Native GTK launcher for Claude Code through local Ollama.
- Custom Anthropic-compatible llama.cpp endpoint mode with server-managed runtime settings.
- Installed-model discovery and editable model selection.
- Context-window selector for 4K through 128K.
- Root-owned, allowlisted context helper for the system Ollama service.
- Project-folder selection and native GNOME Terminal launch.
- Local-only Claude Code integration with web and Chrome tools disabled.
- XDG preference persistence.
- User installer, uninstaller, desktop entry, icon, CI, tests, and reproducible release archive.
