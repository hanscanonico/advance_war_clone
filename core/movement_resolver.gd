class_name MovementResolver
extends RefCounted
## Dijkstra flood-fill of the cells a unit can reach this turn.
##
## Rules (Advance Wars):
## - Edge cost is the destination terrain's cost for the unit's move class.
## - Enemy-occupied cells cannot be entered at all.
## - Friendly-occupied cells can be passed through but not stopped on.

const DIRECTIONS: Array[Vector2i] = [
	Vector2i.UP,
	Vector2i.LEFT,
	Vector2i.RIGHT,
	Vector2i.DOWN,
]


class MoveRange:
	var origin: Vector2i
	var costs: Dictionary = {}  # Vector2i -> int movement spent to enter
	var parents: Dictionary = {}  # Vector2i -> Vector2i previous cell
	var stoppable: Dictionary = {}  # Vector2i -> bool may end movement here

	func has(cell: Vector2i) -> bool:
		return costs.has(cell)

	func can_stop_at(cell: Vector2i) -> bool:
		return stoppable.get(cell, false)

	func cells() -> Array[Vector2i]:
		var result: Array[Vector2i] = []
		for cell: Vector2i in costs:
			result.append(cell)
		return result

	## Cheapest path origin..cell inclusive; [] if the cell is unreachable.
	func path_to(cell: Vector2i) -> Array[Vector2i]:
		if not costs.has(cell):
			return []
		var path: Array[Vector2i] = [cell]
		var current := cell
		while current != origin:
			current = parents[current]
			path.push_front(current)
		return path


## How far `unit` may travel this turn: its type's movement points plus whatever
## its commander's doctrine adds, capped by fuel — an empty tank keeps a unit
## where it stands however generous the doctrine.
static func move_budget(state: GameState, unit: Unit) -> int:
	var bonus := state.commander_of(unit.team).move_bonus(state, unit)
	return mini(unit.type.move_points + bonus, unit.fuel)


## What one step onto `terrain` actually costs `unit`, after its commander's
## doctrine. The sole place terrain cost is read, so the flood fill below and
## the fuel spend in GameState.advance_unit cannot disagree.
##
## Two invariants no doctrine may break: IMPASSABLE passes straight through — a
## doctrine may discount terrain, never open terrain its units cannot cross —
## and every other result is floored at 1, so a zero-cost step can never stall
## the flood fill in a loop it keeps finding cheaper.
static func step_cost(state: GameState, unit: Unit, terrain: TerrainType) -> int:
	var base := terrain.move_cost(unit.type.move_class)
	if base == TerrainType.IMPASSABLE:
		return base
	return maxi(1, state.commander_of(unit.team).terrain_cost(state, unit, terrain, base))


static func reachable(state: GameState, unit: Unit) -> MoveRange:
	var result := MoveRange.new()
	result.origin = unit.cell
	result.costs[unit.cell] = 0
	result.stoppable[unit.cell] = true
	var budget := move_budget(state, unit)
	var frontier: Array[Vector2i] = [unit.cell]
	while not frontier.is_empty():
		# Maps are small; a linear min-scan beats a heap in simplicity.
		var best := 0
		for i in frontier.size():
			if result.costs[frontier[i]] < result.costs[frontier[best]]:
				best = i
		var current: Vector2i = frontier[best]
		frontier.remove_at(best)
		for dir in DIRECTIONS:
			var next: Vector2i = current + dir
			var terrain := state.map.terrain_at(next)
			if terrain == null:
				continue
			var step := step_cost(state, unit, terrain)
			if step == TerrainType.IMPASSABLE:
				continue
			var occupant := state.unit_at(next)
			if occupant != null and occupant.team != unit.team:
				continue
			var next_cost: int = result.costs[current] + step
			if next_cost > budget:
				continue
			if result.costs.has(next) and result.costs[next] <= next_cost:
				continue
			result.costs[next] = next_cost
			result.parents[next] = current
			result.stoppable[next] = occupant == null
			frontier.append(next)
	return result
