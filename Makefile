GODOT := bin/Godot.app/Contents/MacOS/Godot
BATTLE := scenes/battle/battle.tscn

run:
	$(GODOT) --path .

hotseat:
	$(GODOT) --path . $(BATTLE) -- --hotseat

test:
	$(GODOT) --headless --path . -s res://addons/gut/gut_cmdln.gd

tiles:
	$(GODOT) --headless --path . -s res://tools/generate_tiles.gd

sfx:
	$(GODOT) --headless --path . -s res://tools/generate_sfx.gd

import:
	$(GODOT) --headless --path . --import

# The battle scene is launched directly so demos and captures skip the menu.
screenshot:
	$(GODOT) --path . $(BATTLE) -- --screenshot=$(CURDIR)/screenshot.png

menu-screenshot:
	$(GODOT) --path . -- --screenshot=$(CURDIR)/screenshot.png

.PHONY: run hotseat test tiles sfx import screenshot menu-screenshot
