GODOT := bin/Godot.app/Contents/MacOS/Godot
BATTLE := scenes/battle/battle.tscn
# The 36 source sprites the atlases are built from are vendored (CC0), so a
# fresh clone rebuilds with no setup. Override to build from a full extracted
# Revised_PixVoxel_Wargame_1.7z — see assets/LICENSES.md for the source.
PIXVOXEL ?= assets/sprites/pixvoxel_src

run:
	$(GODOT) --path .

hotseat:
	$(GODOT) --path . $(BATTLE) -- --hotseat

test:
	$(GODOT) --headless --path . -s res://addons/gut/gut_cmdln.gd

# The merge gate, in one command. Order is cheapest-feedback-first: parsing
# fails fastest, style next, the suite last.
#
# Note on exit noise: every headless run ends with "N ObjectDB instances were
# leaked at exit" and "resources still in use". That is the engine failing to
# tear down a *script* reference cycle — AttackCommand.validate() referring to
# its sibling MoveCommand pins the core script graph — and it reproduces in
# twelve lines with no GUT involved. No gameplay object leaks. Attempted
# workarounds (static call, split statements) do not avoid it, so the gate
# reads exit status and ignores the diagnostics.
#
# Needs Godot 4.7+ (vendored under bin/, see README) and gdtoolkit 4.x for the
# lint and format steps: pipx install "gdtoolkit==4.*"
verify: check lint format-check test

# Presentation smoke: drives the battle scene's demo scenarios and proves each
# still produces a frame. Renders, so it needs a display — keep it out of any
# headless CI job. `make smoke MODES="attack capture"` narrows it down;
# SMOKE_KEEP=1 keeps the captures for eyeballing.
MODES ?=
smoke:
	tools/smoke_scenarios.sh $(MODES)

# Every .gd file that is actually ours: skips the engine cache, vendored addons,
# the engine binary, and .claude/worktrees, which holds whole nested checkouts of
# this same repo and would otherwise be linted as if it were project source.
SOURCES := $(shell find . -name '*.gd' \
	-not -path './.godot/*' -not -path './addons/*' -not -path './bin/*' \
	-not -path './.claude/*')

# Parse + type check without booting the scene tree — the quick "does this
# compile?" pass. Rules live in tools/check_scripts.sh.
check:
	tools/check_scripts.sh

# Style and smells. Rule overrides live in gdlintrc.
lint:
	gdlint $(SOURCES)

# Reformat in place; `make format-check` only reports. Both need gdtoolkit:
#   pipx install "gdtoolkit==4.*"
format:
	gdformat $(SOURCES)

format-check:
	gdformat --check $(SOURCES)

# generate_tiles.gd draws only the ground; it leaves city/base/hq as bare lots
# and no longer writes units_atlas.png, so the PixVoxel step must follow it.
# `sprites-check` runs first because `ground` is destructive: it replaces the
# committed building art with bare lots that only `sprites` can finish painting,
# so a missing ImageMagick or source sprite has to fail while the tree is clean.
# `import` runs last because Godot caches image imports by size: without it a
# rebuild that changes the atlas dimensions renders a blank map.
# .NOTPARALLEL keeps that order under `make -j` — the two atlas steps write the
# same file, so running them concurrently produces a torn terrain_atlas.png.
.NOTPARALLEL:

tiles: sprites-check ground sprites import

sprites-check:
	tools/build_pixvoxel_atlases.sh --check "$(PIXVOXEL)"

ground:
	$(GODOT) --headless --path . -s res://tools/generate_tiles.gd

sprites:
	tools/build_pixvoxel_atlases.sh "$(PIXVOXEL)"

sfx:
	$(GODOT) --headless --path . -s res://tools/generate_sfx.gd

import:
	$(GODOT) --headless --path . --import

# The battle scene is launched directly so demos and captures skip the menu.
screenshot:
	$(GODOT) --path . $(BATTLE) -- --screenshot=$(CURDIR)/screenshot.png

menu-screenshot:
	$(GODOT) --path . -- --screenshot=$(CURDIR)/screenshot.png

.PHONY: run hotseat test verify smoke check lint format format-check tiles \
	sprites-check ground sprites sfx import screenshot menu-screenshot
