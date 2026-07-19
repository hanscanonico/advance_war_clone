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
##
## Commanders bend all three: a doctrine can lengthen a unit's sight, let it see
## into woods at range, jam an enemy's sight shorter, or hide its own units from
## a viewer who can otherwise see the cell they stand on. Because of that last
## one, seeing a *cell* and seeing the *unit* on it are now separate questions —
## see can_see_unit.

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
		var co := state.commander_of(team)
		_reveal_around(
			state, cells, unit.cell, _sight_of(state, unit), co.sees_into_woods(state, unit)
		)
	for cell in state.properties_of(team):
		_reveal_around(state, cells, cell, PROPERTY_VISION, false)
	return cells


## Whether `viewer_team` can see `unit` at all — the question to ask before
## drawing or targeting an enemy, in place of looking its cell up directly.
##
## Usually that is exactly cell visibility, but a doctrine can hide a unit
## standing somewhere the viewer can otherwise see (Sable Wren's Vanish), so the
## two questions have to be asked separately. `visible` is the dictionary from
## visible_cells, passed in rather than recomputed because callers are drawing a
## whole board and already have it.
static func can_see_unit(
	state: GameState, viewer_team: int, unit: Unit, visible: Dictionary
) -> bool:
	if not state.fog_enabled or unit.team == viewer_team:
		return true
	if not visible.has(unit.cell):
		return false
	return not state.commander_of(unit.team).hides_unit(state, unit)


## How far a unit sees: its type's range, plus what its own commander adds, less
## what any enemy commander jams away. Floored at 0 — a jammed unit goes blind,
## never inside-out.
static func _sight_of(state: GameState, unit: Unit) -> int:
	var radius := unit.type.vision + state.commander_of(unit.team).vision_bonus(state, unit)
	for team in GameState.TEAMS:
		if team != unit.team:
			radius += state.commander_of(team).enemy_vision_bonus(state, unit)
	return maxi(0, radius)


static func _reveal_around(
	state: GameState, cells: Dictionary, from: Vector2i, radius: int, through_woods: bool
) -> void:
	for dy in range(-radius, radius + 1):
		var span: int = radius - absi(dy)
		for dx in range(-span, span + 1):
			var cell := from + Vector2i(dx, dy)
			if not state.map.in_bounds(cell):
				continue
			if through_woods:
				cells[cell] = true
				continue
			if state.map.terrain_at(cell).id == &"woods" and absi(dx) + absi(dy) > 1:
				continue  # woods hide anything not right next to a viewer
			cells[cell] = true
