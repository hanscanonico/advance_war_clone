class_name ThreatMap
extends RefCounted
## Where the enemy could hit next turn, and how hard. For every enemy that can
## reach a firing position and shoot a given board cell, this records that the
## cell is threatened by that unit; a caller then asks "if my unit stood here,
## what damage answers it?" and gets a luck-free forecast summed over those
## enemies. This is the one thing Difficult weighs that Normal and Easy do not:
## it lets a unit refuse to end its move in a kill zone.
##
## Node-free like the rest of ai/. Reuses the single authorities and re-derives
## no rules: MovementResolver for each enemy's reach, AttackRange for its firing
## ring, CombatResolver.forecast for the damage. Forecast is luck-free and draws
## no RNG, so a Difficult match stays as deterministic and replayable as any
## other tier.
##
## The expensive half — one flood fill per enemy — depends only on where the
## enemies are, which does not change during the side's own turn (a unit only
## leaves the board by dying to a counter). So AIController builds one of these
## once per turn and reuses it across every command it plans that turn.
##
## One approximation comes with that, and it is deliberate: an enemy's reach is
## flood-filled against the board as it stood when the map was built, so our own
## units moving during the turn does not re-open or re-block the lanes they were
## standing in. Refreshing per command would cost a fill per enemy per command
## for a second-order correction. The map is a scoring heuristic and never a
## legality check, so the cost of being slightly stale is a slightly wrong
## preference, never an illegal move.

## cell -> Array[Unit]: the enemies that can bring `cell` under fire. An enemy
## appears at most once per cell however many firing positions reach it.
var _by_cell: Dictionary = {}


## Builds the map for `team` from the enemies it can see. The caller passes the
## visible-enemy list (already filtered through Vision) so this stays ignorant of
## the fog rules — it never widens what the AI is allowed to know.
static func build(state: GameState, enemies: Array[Unit]) -> ThreatMap:
	var map := ThreatMap.new()
	for enemy in enemies:
		if enemy.type.max_range <= 0 or not enemy.has_ammo():
			continue  # unarmed or dry: no threat to map
		var low := AttackRange.minimum(state, enemy)
		var high := AttackRange.maximum(state, enemy)
		for from in _firing_cells(state, enemy):
			map._mark_ring(state, enemy, from, low, high)
	return map


## The cells `enemy` could fire from this turn. An indirect unit cannot move and
## fire, so it shoots only from where it stands; a direct unit may fire from any
## cell it can stop on, its current one included.
static func _firing_cells(state: GameState, enemy: Unit) -> Array[Vector2i]:
	if AttackRange.is_indirect(enemy):
		return [enemy.cell]
	var cells: Array[Vector2i] = []
	var reach := MovementResolver.reachable(state, enemy)
	for cell in reach.cells():
		if reach.can_stop_at(cell):
			cells.append(cell)
	return cells


## Flags every in-bounds cell in the [low, high] firing ring around `from` as
## threatened by `enemy`.
func _mark_ring(state: GameState, enemy: Unit, from: Vector2i, low: int, high: int) -> void:
	for dx in range(-high, high + 1):
		var span := high - absi(dx)
		for dy in range(-span, span + 1):
			var dist := absi(dx) + absi(dy)
			if dist < low:
				continue
			var cell := from + Vector2i(dx, dy)
			if state.map.terrain_at(cell) == null:
				continue  # off the board
			var here: Array = _by_cell.get(cell, [])
			if enemy not in here:
				here.append(enemy)
				_by_cell[cell] = here


## Expected luck-free damage `defender` would take standing on `cell`, summed
## over every enemy that threatens it and capped at the defender's HP — two
## attackers cannot cost more than the unit is worth.
##
## Evaluates the shot with the defender *at* `cell`, which is the whole point:
## the terrain it would move onto changes how hard it is hit. Because
## CombatResolver.forecast reads the defender's own cell, the unit is stood on
## `cell` for the calculation and put straight back — a synchronous, restored
## read that never leaves the board changed. The enemy's firing cell does not
## affect outgoing damage (only the defender's terrain does), so any in-range
## origin gives the same number and the stored per-cell list is enough.
func incoming_damage(state: GameState, defender: Unit, cell: Vector2i) -> int:
	var enemies: Array = _by_cell.get(cell, [])
	if enemies.is_empty():
		return 0
	var origin := defender.cell
	defender.cell = cell
	var total := 0
	for enemy: Unit in enemies:
		if not state.damage_chart.can_attack(enemy.type.id, defender.type.id):
			continue
		var forecast := CombatResolver.forecast(state, enemy, enemy.cell, defender)
		if forecast.can_attack:
			total += forecast.attack_damage
	defender.cell = origin
	return mini(total, defender.hp)
