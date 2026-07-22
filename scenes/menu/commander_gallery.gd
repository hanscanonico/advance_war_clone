extends Control
## Dev-only component gallery: renders a CommanderCard for every record the
## CommanderDB holds — the neutral commander plus all twelve generals — so the
## G1 card foundation can be eyeballed and, more importantly, so building all
## thirteen at once proves no id is missing its art or its copy. If any card
## failed to construct, the scene would crash before it could be captured, which
## is what turns the screenshot into a real gate.
##
## Boot with:  Godot --path . scenes/menu/commander_gallery.tscn -- --screenshot=/abs.png
## (see `make gallery-screenshot`).

const _COLUMNS := 4


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.133, 0.153, 0.169)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	add_child(margin)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)
	margin.add_child(rows)

	var title := Label.new()
	title.text = "COMMANDER CARD GALLERY"
	title.add_theme_font_size_override("font_size", 14)
	rows.add_child(title)

	var grid := GridContainer.new()
	grid.columns = _COLUMNS
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	rows.add_child(grid)

	var db := CommanderDB.load_default()
	for commander in db.all():
		var card := CommanderCard.new()
		grid.add_child(card)
		card.bind(commander)

	var shot_path := ScreenshotUtil.requested()
	if shot_path != "":
		ScreenshotUtil.capture_and_quit(self, shot_path)
