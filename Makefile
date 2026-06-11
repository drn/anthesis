GODOT ?= tools/godot/macos_editor.app/Contents/MacOS/Godot

# Sandbox the editor's user:// writes (settings, logs, shader cache) away from
# the real home. Godot crashes in RotatedFileLogger if it cannot create
# user://logs, so the directory must exist before any invocation.
GODOT_HOME ?= /tmp/anthesis-home
GODOT_RUN = mkdir -p $(GODOT_HOME) && HOME=$(GODOT_HOME) $(GODOT)

# gdtoolkit: use gdlint/gdformat from PATH when installed, else run them via
# uvx (the CLAUDE.md-sanctioned form) so lint/format work on a fresh machine.
GDLINT ?= $(shell command -v gdlint >/dev/null 2>&1 && echo gdlint || echo "uvx --from 'gdtoolkit==4.*' gdlint")
GDFORMAT ?= $(shell command -v gdformat >/dev/null 2>&1 && echo gdformat || echo "uvx --from 'gdtoolkit==4.*' gdformat")

.PHONY: setup edit run import test lint format format-check stems notes _ensure_import

# Check that the Godot binary exists before targets that need it.
_check_godot:
	@if [ ! -f "$(GODOT)" ]; then \
		echo ""; \
		echo "ERROR: Godot binary not found at: $(GODOT)"; \
		echo "Run  make setup  to download the prebuilt editor, or set"; \
		echo "  GODOT=/path/to/your/Godot  to use an existing installation."; \
		echo ""; \
		exit 1; \
	fi

## Download the Godot+voxel prebuilt editor and install tooling hints.
setup:
	bash scripts/setup.sh

# First-run guard: the class_name registry lives in gitignored
# .godot/global_script_class_cache.cfg. Booting without it produces a wall of
# "Identifier not declared" parse errors, so import once when it is missing.
_ensure_import: _check_godot
	@if [ ! -f .godot/global_script_class_cache.cfg ]; then \
		echo "No import cache found (fresh checkout) — running first import..."; \
		$(GODOT_RUN) --headless --path . --import; \
	fi

## Open the Godot editor (background).
edit: _ensure_import
	$(GODOT_RUN) --path . -e &

## Run the game directly.
run: _ensure_import
	$(GODOT_RUN) --path .

## Import/reimport all assets headlessly (required before first test run).
import: _check_godot
	$(GODOT_RUN) --headless --path . --import

## Run the full GUT test suite (imports first).
test: import
	$(GODOT_RUN) --headless --path . \
		-s res://addons/gut/gut_cmdln.gd \
		-gconfig=res://.gutconfig.json \
		-gexit

## Lint all GDScript files.
lint:
	find scripts tests -name "*.gd" | xargs $(GDLINT)

## Auto-format all GDScript files.
format:
	find scripts tests -name "*.gd" | xargs $(GDFORMAT)

## Check formatting without modifying files (CI-safe).
format-check:
	find scripts tests -name "*.gd" | xargs $(GDFORMAT) --check

## Regenerate the procedural adaptive-music stems (stdlib Python, idempotent).
stems:
	python3 scripts/tools/generate_stems.py

## Regenerate the procedural sequencer note bank (stdlib Python, idempotent).
notes:
	python3 scripts/tools/generate_notes.py
