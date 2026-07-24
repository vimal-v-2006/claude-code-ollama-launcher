import importlib
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
import core


class FakeResponse:
    def __init__(self, payload):
        self.payload = payload

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return False


def fake_json_load(response):
    return response.payload


class CoreTests(unittest.TestCase):
    def test_context_choices_include_adjustable_agent_sizes(self):
        self.assertEqual(list(core.CONTEXT_CHOICES), [4096, 8192, 16384, 32768, 65536, 131072])

    def test_current_context_reads_dropin(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "context.conf"
            path.write_text('[Service]\nEnvironment="OLLAMA_CONTEXT_LENGTH=32768"\n')
            self.assertEqual(core.current_context(path), 32768)

    def test_current_context_falls_back(self):
        self.assertIsNone(core.current_context(Path("/does/not/exist")))

    def test_privileged_helper_path_cannot_be_overridden(self):
        self.assertEqual(str(core.SYSTEM_CONTEXT_HELPER), "/usr/local/libexec/claude-code-ollama-launcher/set-context")
        with tempfile.TemporaryDirectory() as temp:
            fake = Path(temp) / "helper"
            fake.write_text("#!/bin/sh\n")
            fake.chmod(0o755)
            self.assertFalse(core.trusted_context_helper(fake)[0])

    @mock.patch("core.json.load", side_effect=fake_json_load)
    @mock.patch("core.urllib.request.urlopen")
    def test_ollama_model_discovery(self, urlopen, _json_load):
        urlopen.return_value = FakeResponse({"models": [{"name": "z:latest"}, {"name": "a:latest"}]})
        self.assertEqual(core.ollama_models(), ["a:latest", "z:latest"])

    @mock.patch("core.ollama_models", return_value=["qwen3.6:27b"])
    def test_local_model_ready(self, _models):
        self.assertEqual(core.local_model_ready("qwen3.6:27b"), (True, "Local model ready: qwen3.6:27b"))
        self.assertFalse(core.local_model_ready("missing")[0])

    def test_command_is_argv_only_local_and_disables_web(self):
        command = core.claude_command(Path("/tmp/project with spaces"), "qwen3.6:27b")
        self.assertEqual(command[0], "gnome-terminal")
        self.assertIn("OLLAMA_HOST=http://127.0.0.1:11434", command)
        self.assertIn("--disallowedTools", command)
        self.assertIn("WebSearch", command)
        self.assertIn("WebFetch", command)
        self.assertNotIn("shell=True", command)

    def test_custom_endpoint_normalization(self):
        self.assertEqual(core.normalize_endpoint("http://127.0.0.1:8080/v1/"), "http://127.0.0.1:8080")
        with self.assertRaises(ValueError):
            core.normalize_endpoint("ftp://127.0.0.1:8080")
        with self.assertRaises(ValueError):
            core.normalize_endpoint("http://user:pass@127.0.0.1:8080")

    @mock.patch("core.json.load", side_effect=fake_json_load)
    @mock.patch("core.urllib.request.urlopen")
    def test_custom_endpoint_model_discovery(self, urlopen, _json_load):
        urlopen.return_value = FakeResponse({"data": [{"id": "llama-local"}]})
        self.assertEqual(core.custom_endpoint_models("http://127.0.0.1:8080"), ["llama-local"])
        urlopen.assert_called_once_with("http://127.0.0.1:8080/v1/models", timeout=2.0)

    def test_custom_claude_command_uses_server_managed_model(self):
        command = core.custom_claude_command(Path("/tmp/project"), "http://127.0.0.1:8080/v1", "local-alias")
        self.assertIn("ANTHROPIC_BASE_URL=http://127.0.0.1:8080", command)
        self.assertIn("ANTHROPIC_MODEL=local-alias", command)
        self.assertIn("ANTHROPIC_DEFAULT_SONNET_MODEL=local-alias", command)
        self.assertNotIn("OLLAMA_HOST=http://127.0.0.1:11434", command)
        self.assertNotIn("--model", command)

    def test_settings_roundtrip_and_permissions(self):
        with tempfile.TemporaryDirectory() as temp:
            with mock.patch.dict(os.environ, {"XDG_CONFIG_HOME": temp}):
                project = Path(temp)
                core.save_settings("test-model", 16384, project)
                loaded = core.load_settings()
                self.assertEqual(loaded["model"], "test-model")
                self.assertEqual(loaded["context"], 16384)
                self.assertEqual(loaded["backend"], "ollama")
                self.assertEqual(Path(loaded["project"]), project)
                self.assertEqual(core.settings_path().stat().st_mode & 0o777, 0o600)

    def test_rejects_invalid_settings(self):
        with tempfile.TemporaryDirectory() as temp:
            with mock.patch.dict(os.environ, {"XDG_CONFIG_HOME": temp}):
                with self.assertRaises(ValueError):
                    core.save_settings("", 65536, Path(temp))
                with self.assertRaises(ValueError):
                    core.save_settings("model", 12345, Path(temp))


if __name__ == "__main__":
    unittest.main()
