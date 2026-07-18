GODOT := bin/Godot.app/Contents/MacOS/Godot

run:
	$(GODOT) --path .

hotseat:
	$(GODOT) --path . -- --hotseat

test:
	$(GODOT) --headless --path . -s res://addons/gut/gut_cmdln.gd

tiles:
	$(GODOT) --headless --path . -s res://tools/generate_tiles.gd

import:
	$(GODOT) --headless --path . --import

screenshot:
	$(GODOT) --path . -- --screenshot=$(CURDIR)/screenshot.png

.PHONY: run hotseat test tiles import screenshot
