class_name Vision
extends RefCounted
## What a team can see under fog of war. Every "can this player see X"
## question routes through here so the rules live in one place; with fog
## disabled the whole map is visible.
##
## Simplified Advance Wars rules:
## - Each unit on the board sees cells within its type's vision range
##   (Manhattan distance). Carried units see nothing.
## - Concealing terrain (woods, reefs) hides what stands on it: revealed only
##   from distance <= 1, regardless of the viewer's range.
## - Owned properties watch their surroundings out to PROPERTY_VISION.
##
## Commanders bend all three: a doctrine can lengthen a unit's sight, let it see
## into cover at range, jam an enemy's sight shorter, or hide its own units from
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
			state, cells, unit.cell, _sight_of(state, unit), co.sees_into_cover(state, unit)
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
	if unit.team == viewer_team:
		return true
	# Asked before the fog check, not after it, because one of the things it
	# answers — a submerged submarine — hides on a clear day too.
	if is_hidden_from(state, viewer_team, unit):
		return false
	if not state.fog_enabled:
		return true
	return visible.has(unit.cell)


## Whether `unit` is hidden from `viewer_team` by something other than the fog
## itself: a doctrine (the invisibility half of Sable Wren's Vanish) or a dive.
##
## Split out from can_see_unit because it is the one visibility rule the AI
## respects: the planner sees the whole board deliberately, but a power that makes
## units unseeable — or a submarine that has gone under — would be inert against it
## otherwise, so it asks this instead of ignoring fog wholesale. Terrain, range and
## property sight stay invisible to that question.
##
## The two halves differ in one way worth being explicit about. Vanish is a fog
## power and does nothing in a clear match. A dive is not: a submerged sub is
## unseeable whether or not the match has fog, because being under the water is
## not a matter of how far anyone can see. Both are lifted by standing next to
## it — hunting a submarine means closing with it.
static func is_hidden_from(state: GameState, viewer_team: int, unit: Unit) -> bool:
	if unit.team == viewer_team:
		return false
	if unit.dived:
		return not _has_neighbour_from(state, unit.cell, viewer_team)
	if not state.fog_enabled:
		return false
	return state.commander_of(unit.team).hides_unit(state, unit)


## True when `team` has a unit standing on a tile orthogonally adjacent to `cell`.
static func _has_neighbour_from(state: GameState, cell: Vector2i, team: int) -> bool:
	for other in state.units_of(team):
		if other.carrier != null:
			continue
		if absi(other.cell.x - cell.x) + absi(other.cell.y - cell.y) == 1:
			return true
	return false


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
	state: GameState, cells: Dictionary, from: Vector2i, radius: int, through_cover: bool
) -> void:
	for dy in range(-radius, radius + 1):
		var span: int = radius - absi(dy)
		for dx in range(-span, span + 1):
			var cell := from + Vector2i(dx, dy)
			if not state.map.in_bounds(cell):
				continue
			if through_cover:
				cells[cell] = true
				continue
			# Which terrain conceals is the terrain's own flag rather than a name
			# checked here, so a reef hides a submarine exactly as woods hide a
			# tank, and adding cover is a data edit.
			if state.map.terrain_at(cell).conceals and absi(dx) + absi(dy) > 1:
				continue  # cover hides anything not right next to a viewer
			cells[cell] = true
