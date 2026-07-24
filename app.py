#!/usr/bin/python3
"""Native GTK starter for Claude Code through local Ollama."""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

from core import (
    APP_ID,
    APP_NAME,
    CONTEXT_CHOICES,
    SYSTEM_CONTEXT_HELPER,
    VERSION,
    claude_command,
    custom_claude_command,
    custom_endpoint_ready,
    current_context,
    default_projects_dir,
    load_settings,
    local_model_ready,
    ollama_models,
    save_settings,
    trusted_context_helper,
)


def self_test() -> int:
    settings = load_settings()
    backend = str(settings["backend"])
    model = str(settings["model"])
    endpoint = str(settings["custom_endpoint"])
    if backend == "custom":
        ready, status, endpoint_model = custom_endpoint_ready(endpoint)
        command = custom_claude_command(Path(str(settings["project"])), endpoint, endpoint_model) if ready else []
    else:
        ready, status = local_model_ready(model)
        command = claude_command(Path(str(settings["project"])), model)
    result = {
        "version": VERSION,
        "backend": backend,
        "ready": ready,
        "status": status,
        "active_context": current_context(),
        "context_choices": list(CONTEXT_CHOICES),
        "context_helper": str(SYSTEM_CONTEXT_HELPER),
        "context_helper_installed": trusted_context_helper()[0],
        "command": command,
    }
    print(json.dumps(result))
    return 0 if ready else 1


if "--self-test" in sys.argv:
    raise SystemExit(self_test())
if "--version" in sys.argv:
    print(f"{APP_NAME} {VERSION}")
    raise SystemExit(0)

# A removed optional XApp module can remain in an existing desktop session.
os.environ.pop("GTK3_MODULES", None)

import gi
gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
from gi.repository import Gdk, GLib, Gtk


class Launcher(Gtk.Application):
    def __init__(self) -> None:
        super().__init__(application_id=APP_ID)
        self.settings = load_settings()

    def do_activate(self) -> None:
        # Force one coherent dark palette. Without this, GTK can render combo
        # popup rows as white text on a white background until they are hovered.
        Gtk.Settings.get_default().set_property("gtk-application-prefer-dark-theme", True)
        window = Gtk.ApplicationWindow(application=self)
        window.set_title(APP_NAME)
        window.set_default_size(640, 520)
        window.set_resizable(False)
        window.set_position(Gtk.WindowPosition.CENTER)

        css = Gtk.CssProvider()
        css.load_from_data(b"""
            window { background: #0d1117; color: #f0f6fc; }
            .title { font-size: 26px; font-weight: 700; color: #f0f6fc; }
            .subtitle { font-size: 14px; color: #9da7b3; }
            .card { background: #161b22; border: 1px solid #30363d; border-radius: 12px; padding: 22px; }
            .label { font-weight: 600; color: #c9d1d9; }
            combobox button, filechooserbutton button {
                background: #21262d;
                background-image: none;
                color: #f0f6fc;
                border: 1px solid #484f58;
                border-radius: 6px;
                box-shadow: none;
            }
            combobox button:hover, filechooserbutton button:hover {
                background: #30363d;
                color: #ffffff;
            }
            combobox entry {
                background: #21262d;
                color: #f0f6fc;
                caret-color: #f0f6fc;
                border: 1px solid #484f58;
            }
            combobox arrow { color: #f0f6fc; }
            window.popup, menu, .menu {
                background: #161b22;
                color: #f0f6fc;
            }
            treeview.view, treeview.view cell {
                background: #161b22;
                color: #f0f6fc;
            }
            treeview.view:selected, treeview.view:selected:focus {
                background: #238636;
                color: #ffffff;
            }
            menuitem {
                background: #161b22;
                color: #f0f6fc;
            }
            menuitem:hover {
                background: #238636;
                color: #ffffff;
            }
            .status-ok { color: #3fb950; font-weight: 600; }
            .status-bad { color: #f85149; font-weight: 600; }
            .run { background: #238636; color: white; border-radius: 8px; padding: 10px 26px; font-weight: 700; }
            .run:hover { background: #2ea043; }
            .note { color: #8b949e; font-size: 12px; }
        """)
        Gtk.StyleContext.add_provider_for_screen(
            Gdk.Screen.get_default(), css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )

        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14)
        outer.set_border_width(26)
        window.add(outer)

        title = Gtk.Label(label="Claude Code Local")
        title.set_xalign(0)
        title.get_style_context().add_class("title")
        outer.pack_start(title, False, False, 0)

        subtitle = Gtk.Label(label="Use Ollama or a server-managed llama.cpp endpoint in Claude Code's native terminal")
        subtitle.set_xalign(0)
        subtitle.get_style_context().add_class("subtitle")
        outer.pack_start(subtitle, False, False, 0)

        card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=13)
        card.get_style_context().add_class("card")
        outer.pack_start(card, True, True, 4)

        backend_label = Gtk.Label(label="Local inference backend")
        backend_label.set_xalign(0)
        backend_label.get_style_context().add_class("label")
        card.pack_start(backend_label, False, False, 0)
        self.backend_choice = Gtk.ComboBoxText()
        self.backend_choice.append("ollama", "Ollama - managed model and context")
        self.backend_choice.append("custom", "Custom endpoint / llama.cpp - server managed")
        self.backend_choice.set_active_id(str(self.settings["backend"]))
        self.backend_choice.connect("changed", self.on_backend_changed)
        card.pack_start(self.backend_choice, False, False, 0)

        self.ollama_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        card.pack_start(self.ollama_box, False, False, 0)

        model_label = Gtk.Label(label="Local Ollama model")
        model_label.set_xalign(0)
        model_label.get_style_context().add_class("label")
        self.ollama_box.pack_start(model_label, False, False, 0)

        self.model_choice = Gtk.ComboBoxText.new_with_entry()
        try:
            models = ollama_models()
        except Exception:
            models = []
        saved_model = str(self.settings["model"])
        if saved_model not in models:
            models.insert(0, saved_model)
        for model in models:
            self.model_choice.append_text(model)
        self.model_choice.set_active(models.index(saved_model) if saved_model in models else 0)
        self.model_choice.connect("changed", lambda _widget: self.refresh_status())
        self.ollama_box.pack_start(self.model_choice, False, False, 0)

        context_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        context_label = Gtk.Label(label="Context window")
        context_label.set_xalign(0)
        context_label.get_style_context().add_class("label")
        self.context_choice = Gtk.ComboBoxText()
        for value, description in CONTEXT_CHOICES.items():
            self.context_choice.append(str(value), description)
        saved_context = int(self.settings["context"])
        self.context_choice.set_active_id(str(saved_context))
        context_row.pack_start(context_label, False, False, 0)
        context_row.pack_end(self.context_choice, False, False, 0)
        self.ollama_box.pack_start(context_row, False, False, 0)

        self.custom_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        custom_label = Gtk.Label(label="llama.cpp server endpoint")
        custom_label.set_xalign(0)
        custom_label.get_style_context().add_class("label")
        self.custom_box.pack_start(custom_label, False, False, 0)
        self.endpoint_entry = Gtk.Entry()
        self.endpoint_entry.set_text(str(self.settings["custom_endpoint"]))
        self.endpoint_entry.set_placeholder_text("http://127.0.0.1:8080")
        self.endpoint_entry.connect("activate", lambda _entry: self.refresh_status())
        self.custom_box.pack_start(self.endpoint_entry, False, False, 0)
        server_note = Gtk.Label(label="Model alias, context, GPU layers, and sampling are read from the running llama.cpp server.")
        server_note.set_xalign(0)
        server_note.get_style_context().add_class("note")
        self.custom_box.pack_start(server_note, False, False, 0)
        card.pack_start(self.custom_box, False, False, 0)

        folder_label = Gtk.Label(label="Coding project folder")
        folder_label.set_xalign(0)
        folder_label.get_style_context().add_class("label")
        card.pack_start(folder_label, False, False, 0)

        self.folder = Gtk.FileChooserButton(
            title="Choose coding project", action=Gtk.FileChooserAction.SELECT_FOLDER
        )
        project = Path(str(self.settings["project"]))
        self.folder.set_filename(str(project if project.is_dir() else default_projects_dir()))
        card.pack_start(self.folder, False, False, 0)

        self.status = Gtk.Label()
        self.status.set_xalign(0)
        self.status.set_line_wrap(True)
        card.pack_start(self.status, False, False, 0)
        self.refresh_status()

        self.note = Gtk.Label(
            label="Changing context restarts the system Ollama service and shows a system authentication dialog. "
            "Cloud AI, web search, web fetch, and Chrome integration are disabled. Claude Code keeps its native permission prompts."
        )
        self.note.set_line_wrap(True)
        self.note.set_xalign(0)
        self.note.get_style_context().add_class("note")
        card.pack_start(self.note, False, False, 0)

        actions = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        outer.pack_end(actions, False, False, 0)
        refresh = Gtk.Button(label="Refresh backend")
        refresh.connect("clicked", lambda _button: self.refresh_models())
        actions.pack_start(refresh, False, False, 0)
        run = Gtk.Button(label="Run Claude Code")
        run.get_style_context().add_class("run")
        run.connect("clicked", self.on_run, window)
        actions.pack_end(run, False, False, 0)

        window.show_all()
        self.update_backend_visibility()

    def selected_model(self) -> str:
        child = self.model_choice.get_child()
        return child.get_text().strip() if child else ""

    def selected_backend(self) -> str:
        return self.backend_choice.get_active_id() or "ollama"

    def on_backend_changed(self, _widget: Gtk.Widget) -> None:
        self.update_backend_visibility()
        self.refresh_status()

    def update_backend_visibility(self) -> None:
        custom = self.selected_backend() == "custom"
        self.ollama_box.set_visible(not custom)
        self.custom_box.set_visible(custom)
        if custom:
            self.note.set_text(
                "The launcher does not change llama.cpp server arguments. Cloud AI, web search, web fetch, "
                "and Chrome integration are disabled. Claude Code keeps its native permission prompts."
            )
        else:
            self.note.set_text(
                "Changing context restarts the system Ollama service and shows a system authentication dialog. "
                "Cloud AI, web search, web fetch, and Chrome integration are disabled. Claude Code keeps its native permission prompts."
            )

    def refresh_models(self) -> None:
        if self.selected_backend() == "custom":
            self.refresh_status()
            return
        selected = self.selected_model()
        try:
            models = ollama_models()
        except Exception:
            self.refresh_status()
            return
        self.model_choice.remove_all()
        if selected and selected not in models:
            models.insert(0, selected)
        for model in models:
            self.model_choice.append_text(model)
        if models:
            self.model_choice.set_active(models.index(selected) if selected in models else 0)
        self.refresh_status()

    def refresh_status(self) -> None:
        if self.selected_backend() == "custom":
            ready, text, _model = custom_endpoint_ready(self.endpoint_entry.get_text())
            self.status.set_text(f"● {text}  |  context and runtime options are controlled by the server")
        else:
            model = self.selected_model()
            ready, text = local_model_ready(model) if model else (False, "Choose a local model")
            active = current_context()
            helper_ok, helper = trusted_context_helper()
            active_text = f"{active // 1024}K" if active else "not configured"
            self.status.set_text(f"● {text}  |  active context: {active_text}  |  {helper}")
        style = self.status.get_style_context()
        style.remove_class("status-ok")
        style.remove_class("status-bad")
        helper_ready = self.selected_backend() == "custom" or trusted_context_helper()[0]
        style.add_class("status-ok" if ready and helper_ready else "status-bad")

    @staticmethod
    def error(window: Gtk.Window, title: str, detail: str) -> None:
        dialog = Gtk.MessageDialog(
            transient_for=window,
            flags=Gtk.DialogFlags.MODAL,
            message_type=Gtk.MessageType.ERROR,
            buttons=Gtk.ButtonsType.CLOSE,
            text=title,
        )
        dialog.format_secondary_text(detail)
        dialog.run()
        dialog.destroy()

    def on_run(self, _button: Gtk.Button, window: Gtk.Window) -> None:
        project = Path(self.folder.get_filename() or default_projects_dir()).resolve()
        backend = self.selected_backend()
        model = self.selected_model()
        context = int(self.context_choice.get_active_id() or current_context() or 65536)
        endpoint = self.endpoint_entry.get_text()
        if backend == "custom":
            ready, message, endpoint_model = custom_endpoint_ready(endpoint)
        else:
            ready, message = local_model_ready(model) if model else (False, "Choose a local Ollama model")
            endpoint_model = ""
        if not ready or not project.is_dir():
            self.error(window, "Cannot start Claude Code", message if not ready else f"Folder does not exist: {project}")
            return
        try:
            if backend == "ollama" and context != current_context():
                helper_ok, helper_message = trusted_context_helper()
                if not helper_ok:
                    raise RuntimeError(helper_message + ". Run install.sh again without --no-system-helper.")
                subprocess.run(
                    ["pkexec", str(SYSTEM_CONTEXT_HELPER), str(context)],
                    check=True,
                    text=True,
                    capture_output=True,
                )
            save_settings(model, context, project, backend=backend, custom_endpoint=endpoint)
            command = (
                custom_claude_command(project, endpoint, endpoint_model)
                if backend == "custom"
                else claude_command(project, model)
            )
            subprocess.Popen(command, start_new_session=True)
        except subprocess.CalledProcessError as exc:
            detail = (exc.stderr or "").strip() or "Context change was cancelled or failed."
            self.error(window, "Launch failed", detail)
            return
        except Exception as exc:
            self.error(window, "Launch failed", str(exc))
            return
        GLib.timeout_add(300, self.quit)


if __name__ == "__main__":
    raise SystemExit(Launcher().run(sys.argv))
