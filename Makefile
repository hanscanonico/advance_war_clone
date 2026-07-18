GODOT := bin/Godot.app/Contents/MacOS/Godot
BATTLE := scenes/battle/battle.tscn
# Extracted Revised_PixVoxel_Wargame_1.7z — see assets/LICENSES.md for the source.
PIXVOXEL ?= $(HOME)/Downloads/Revised_PixVoxel_Wargame/standing_frames

run:
	$(GODOT) --path .

hotseat:
	$(GODOT) --path . $(BATTLE) -- --hotseat

test:
	$(GODOT) --headless --path . -s res://addons/gut/gut_cmdln.gd

# generate_tiles.gd draws only the ground; it leaves city/base/hq as bare lots
# and no longer writes units_atlas.png, so the PixVoxel step must follow it.
tiles: ground sprites

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

.PHONY: run hotseat test tiles ground sprites sfx import screenshot menu-screenshot
