class_name Vision
extends RefCounted
## What a team can see under fog of war. Every "can this player see X"
## question routes through here so the rules live in one place; with fog
## disabled the whole map is visible.
##
## Simplified Advance Wars rules:
## - Each unit on the board sees cells within its type's vision range
##   (Manhattan distance). Carried units see nothing.
## - Woods are hiding spots: revealed only from distance <= 1, regardless
##   of the viewer's range.
## - Owned properties watch their surroundings out to PROPERTY_VISION.

const PROPERTY_VISION := 2


## Vector2i -> true for every cell `team` can currently see.
static func visible_cells(state: GameState, team: int) -> Dictionary:
	var cells: Dictionary = {}
	if not state.fog_enabled:
		for y in state.map.height:
			for x in state.map.width:
				cells[Vector2i(x, y)] = true
		return cells
	for unit in state.units_of(team):
		if unit.carrier != null:
			continue
		_reveal_around(state, cells, unit.cell, unit.type.vision)
	for cell in state.properties_of(team):
		_reveal_around(state, cells, cell, PROPERTY_VISION)
	return cells


static func _reveal_around(
	state: GameState, cells: Dictionary, from: Vector2i, radius: int
) -> void:
	for dy in range(-radius, radius + 1):
		var span: int = radius - absi(dy)
		for dx in range(-span, span + 1):
			var cell := from + Vector2i(dx, dy)
			if not state.map.in_bounds(cell):
				continue
			if state.map.terrain_at(cell).id == &"woods" and absi(dx) + absi(dy) > 1:
				continue  # woods hide anything not right next to a viewer
			cells[cell] = true
