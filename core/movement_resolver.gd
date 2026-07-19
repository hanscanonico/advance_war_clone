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


static func reachable(state: GameState, unit: Unit) -> MoveRange:
	var result := MoveRange.new()
	result.origin = unit.cell
	result.costs[unit.cell] = 0
	result.stoppable[unit.cell] = true
	# An empty tank keeps a unit where it stands: fuel caps the move budget.
	var budget := mini(unit.type.move_points, unit.fuel)
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
			var step := terrain.move_cost(unit.type.move_class)
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
