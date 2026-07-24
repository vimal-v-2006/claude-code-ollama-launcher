#!/usr/bin/python3
"""Pure launcher logic shared by the GTK UI and tests."""

from __future__ import annotations

import json
import os
import re
import tempfile
import urllib.request
from pathlib import Path
from urllib.parse import urlparse

APP_ID = "io.github.claude_code_ollama_launcher"
APP_NAME = "Claude Code Local Launcher"
VERSION = "1.0.2"
DEFAULT_BACKEND = "ollama"
DEFAULT_MODEL = "qwen3.6:27b"
DEFAULT_CONTEXT = 65536
DEFAULT_CUSTOM_ENDPOINT = "http://127.0.0.1:8080"
OLLAMA_URL = "http://127.0.0.1:11434"
SYSTEM_CONTEXT_CONFIG = Path("/etc/systemd/system/ollama.service.d/90-claude-code-ollama-context.conf")
SYSTEM_CONTEXT_HELPER = Path("/usr/local/libexec/claude-code-ollama-launcher/set-context")
CONTEXT_CHOICES = {
    4096: "4K - light and fastest",
    8192: "8K - small tasks",
    16384: "16K - normal coding",
    32768: "32K - larger projects",
    65536: "64K - agentic recommended",
    131072: "128K - high memory use",
}


def xdg_config_home() -> Path:
    return Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))


def settings_path() -> Path:
    return xdg_config_home() / "claude-code-ollama-launcher" / "settings.json"


def default_projects_dir() -> Path:
    documents_projects = Path.home() / "Documents" / "Projects"
    if documents_projects.is_dir():
        return documents_projects
    projects = Path.home() / "Projects"
    projects.mkdir(parents=True, exist_ok=True)
    return projects


def load_settings() -> dict[str, object]:
    defaults: dict[str, object] = {
        "backend": DEFAULT_BACKEND,
        "model": DEFAULT_MODEL,
        "context": DEFAULT_CONTEXT,
        "custom_endpoint": DEFAULT_CUSTOM_ENDPOINT,
        "project": str(default_projects_dir()),
    }
    try:
        loaded = json.loads(settings_path().read_text(encoding="utf-8"))
        if isinstance(loaded, dict):
            defaults.update(loaded)
    except (OSError, ValueError):
        pass
    if not isinstance(defaults.get("model"), str) or not defaults["model"]:
        defaults["model"] = DEFAULT_MODEL
    if defaults.get("backend") not in {"ollama", "custom"}:
        defaults["backend"] = DEFAULT_BACKEND
    try:
        defaults["custom_endpoint"] = normalize_endpoint(str(defaults["custom_endpoint"]))
    except (KeyError, ValueError):
        defaults["custom_endpoint"] = DEFAULT_CUSTOM_ENDPOINT
    try:
        context = int(defaults["context"])
    except (KeyError, TypeError, ValueError):
        context = DEFAULT_CONTEXT
    defaults["context"] = context if context in CONTEXT_CHOICES else DEFAULT_CONTEXT
    project = Path(str(defaults.get("project", default_projects_dir()))).expanduser()
    defaults["project"] = str(project if project.is_dir() else default_projects_dir())
    return defaults


def save_settings(
    model: str,
    context: int,
    project: Path,
    backend: str = DEFAULT_BACKEND,
    custom_endpoint: str = DEFAULT_CUSTOM_ENDPOINT,
) -> None:
    if not model.strip():
        raise ValueError("Model name cannot be empty")
    if context not in CONTEXT_CHOICES:
        raise ValueError(f"Unsupported context: {context}")
    if backend not in {"ollama", "custom"}:
        raise ValueError(f"Unsupported backend: {backend}")
    custom_endpoint = normalize_endpoint(custom_endpoint)
    destination = settings_path()
    destination.parent.mkdir(parents=True, exist_ok=True)
    payload = json.dumps(
            {
                "backend": backend,
                "model": model.strip(),
                "context": context,
                "custom_endpoint": custom_endpoint,
                "project": str(project),
            },
            indent=2,
        ) + "\n"
    descriptor, raw_temporary = tempfile.mkstemp(prefix=".settings-", dir=destination.parent)
    temporary = Path(raw_temporary)
    try:
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
            descriptor = -1
            stream.write(payload)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, destination)
    finally:
        if descriptor >= 0:
            os.close(descriptor)
        temporary.unlink(missing_ok=True)


def current_context(config_path: Path = SYSTEM_CONTEXT_CONFIG) -> int | None:
    try:
        match = re.search(r"OLLAMA_CONTEXT_LENGTH=(\d+)", config_path.read_text(encoding="utf-8"))
        if match:
            return int(match.group(1))
    except OSError:
        pass
    return None


def trusted_context_helper(path: Path = SYSTEM_CONTEXT_HELPER) -> tuple[bool, str]:
    """Require a fixed, root-owned, non-symlink, non-writable privilege boundary."""
    if path != SYSTEM_CONTEXT_HELPER:
        return False, "Context helper path is not the fixed system path"
    try:
        if path.is_symlink() or not path.is_file():
            return False, "Context helper is missing or is a symlink"
        stat = path.stat()
        if stat.st_uid != 0 or stat.st_mode & 0o022:
            return False, "Context helper must be root-owned and not group/other writable"
        for parent in (path.parent, path.parent.parent):
            parent_stat = parent.stat()
            if parent.is_symlink() or parent_stat.st_uid != 0 or parent_stat.st_mode & 0o022:
                return False, f"Untrusted helper directory: {parent}"
    except OSError as exc:
        return False, str(exc)
    return True, "context control ready"


def ollama_models(timeout: float = 2.0) -> list[str]:
    with urllib.request.urlopen(f"{OLLAMA_URL}/api/tags", timeout=timeout) as response:
        payload = json.load(response)
    names = [item.get("name") for item in payload.get("models", [])]
    return sorted(name for name in names if isinstance(name, str) and name)


def local_model_ready(model: str, timeout: float = 2.0) -> tuple[bool, str]:
    try:
        models = ollama_models(timeout=timeout)
    except Exception as exc:
        return False, f"Ollama is unavailable: {exc}"
    if model in models:
        return True, f"Local model ready: {model}"
    return False, f"Model is not installed in Ollama: {model}"


def normalize_endpoint(endpoint: str) -> str:
    value = endpoint.strip().rstrip("/")
    parsed = urlparse(value)
    if parsed.scheme not in {"http", "https"} or not parsed.netloc:
        raise ValueError("Endpoint must be an http:// or https:// URL")
    if parsed.username or parsed.password or parsed.query or parsed.fragment:
        raise ValueError("Endpoint must not contain credentials, a query, or a fragment")
    if parsed.path.rstrip("/") == "/v1":
        value = value[: -len(parsed.path.rstrip("/"))]
    elif parsed.path not in {"", "/"}:
        raise ValueError("Endpoint must be the server root, optionally ending in /v1")
    return value.rstrip("/")


def custom_endpoint_models(endpoint: str, timeout: float = 2.0) -> list[str]:
    base = normalize_endpoint(endpoint)
    with urllib.request.urlopen(f"{base}/v1/models", timeout=timeout) as response:
        payload = json.load(response)
    names = [item.get("id") for item in payload.get("data", [])]
    return [name for name in names if isinstance(name, str) and name]


def custom_endpoint_ready(endpoint: str, timeout: float = 2.0) -> tuple[bool, str, str]:
    try:
        models = custom_endpoint_models(endpoint, timeout=timeout)
    except Exception as exc:
        return False, f"Custom endpoint is unavailable: {exc}", ""
    if not models:
        return False, "Custom endpoint returned no model from /v1/models", ""
    return True, f"llama.cpp endpoint ready: {models[0]}", models[0]


def claude_command(project: Path, model: str) -> list[str]:
    """Build an argv-only command that opens Claude Code's native terminal UI."""
    return [
        "gnome-terminal",
        f"--working-directory={project}",
        f"--title=Claude Code - Ollama - {model}",
        "--",
        "/usr/bin/env",
        f"OLLAMA_HOST={OLLAMA_URL}",
        "ollama",
        "launch",
        "claude",
        "--model",
        model,
        "--yes",
        "--",
        "--no-chrome",
        "--disallowedTools",
        "WebSearch",
        "WebFetch",
    ]


def custom_claude_command(project: Path, endpoint: str, model: str) -> list[str]:
    """Launch Claude Code against a server-managed Anthropic-compatible endpoint."""
    base = normalize_endpoint(endpoint)
    if not model.strip():
        raise ValueError("Custom endpoint returned no model alias")
    return [
        "gnome-terminal",
        f"--working-directory={project}",
        f"--title=Claude Code - llama.cpp - {model}",
        "--",
        "/usr/bin/env",
        f"ANTHROPIC_BASE_URL={base}",
        "ANTHROPIC_AUTH_TOKEN=local-llama-cpp",
        "ANTHROPIC_API_KEY=",
        f"ANTHROPIC_MODEL={model}",
        f"ANTHROPIC_DEFAULT_SONNET_MODEL={model}",
        f"ANTHROPIC_DEFAULT_OPUS_MODEL={model}",
        f"ANTHROPIC_DEFAULT_HAIKU_MODEL={model}",
        "claude",
        "--no-chrome",
        "--disallowedTools",
        "WebSearch",
        "WebFetch",
    ]
