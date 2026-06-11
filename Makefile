GODOT ?= tools/godot/macos_editor.app/Contents/MacOS/Godot

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
		$(GODOT) --headless --path . --import; \
	fi

## Open the Godot editor (background).
edit: _ensure_import
	$(GODOT) --path . -e &

## Run the game directly.
run: _ensure_import
	$(GODOT) --path .

## Import/reimport all assets headlessly (required before first test run).
import: _check_godot
	$(GODOT) --headless --path . --import

## Run the full GUT test suite (imports first).
test: import
	$(GODOT) --headless --path . \
		-s res://addons/gut/gut_cmdln.gd \
		-gconfig=res://.gutconfig.json \
		-gexit

## Lint all GDScript files.
lint:
	find scripts tests -name "*.gd" | xargs gdlint

## Auto-format all GDScript files.
format:
	find scripts tests -name "*.gd" | xargs gdformat

## Check formatting without modifying files (CI-safe).
format-check:
	find scripts tests -name "*.gd" | xargs gdformat --check

## Regenerate the procedural adaptive-music stems (stdlib Python, idempotent).
stems:
	python3 scripts/tools/generate_stems.py

## Regenerate the procedural sequencer note bank (stdlib Python, idempotent).
notes:
	python3 scripts/tools/generate_notes.py
