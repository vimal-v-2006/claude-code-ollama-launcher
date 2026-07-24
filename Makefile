PYTHON ?= python3

.PHONY: test lint install uninstall release

test:
	$(PYTHON) -m unittest discover -s tests -v
	bash tests/test_install.sh
	bash tests/test_set_context.sh

lint:
	$(PYTHON) -m py_compile app.py core.py tests/test_core.py
	bash -n install.sh uninstall.sh set-context run-claude-local scripts/build-release.sh tests/test_install.sh tests/test_set_context.sh
	@if command -v shellcheck >/dev/null; then shellcheck install.sh uninstall.sh set-context run-claude-local scripts/build-release.sh tests/test_install.sh tests/test_set_context.sh; else echo "shellcheck not installed; skipping"; fi

test-all: lint test

install:
	./install.sh

uninstall:
	./uninstall.sh

release:
	./scripts/build-release.sh
