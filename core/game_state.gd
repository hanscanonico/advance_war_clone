class_name GameState
extends RefCounted
## Authoritative battle state: the map, all units, property ownership, funds,
## and whose turn it is. Scenes render from this; commands mutate it.
## No Node dependencies.

const TEAMS: Array[int] = [1, 2]
const CAPTURE_POINTS := 20
const INCOME_PER_PROPERTY := 1000

## Command Power charge, as a percentage of the value destroyed in an exchange:
## the side that *loses* the HP banks the first, the side that dealt it banks
## the second. Asymmetric on purpose — the aggressor cannot out-charge the
## defender on the same trade, so a player winning the field does not run away
## with the meter as well.
const CHARGE_PCT_LOST := 100
const CHARGE_PCT_DEALT := 50

var map: MapData
var units: Array[Unit] = []
var damage_chart: DamageChart
## Match RNG (combat luck). Set `rng.seed` explicitly for deterministic
## tests and replays; the battle scene randomizes it.
var rng := RandomNumberGenerator.new()

var current_team: int = 1
var day: int = 1
var funds: Dictionary = {}  # team -> int
## Runtime property ownership (Vector2i -> team). Starts from the map's
## [owners] section; capture changes it here, never in MapData.
var property_owners: Dictionary = {}
## In-progress captures: property cell -> capture points remaining.
## Cleared when the capturing unit leaves the cell or dies.
var capture_progress: Dictionary = {}
## 0 while the match runs; the winning team once decided.
var winner: int = 0
## Fog of war (a match option; see Vision for the rules).
var fog_enabled := false
## team -> CommanderState. A team with no entry plays the neutral commander,
## which is created on demand — see commander_state().
var commanders: Dictionary = {}
## res:// path of the map this match runs on; kept for save files.
var map_path := ""


## Builds the starting state from a parsed map. Returns null (with a pushed
## error) if any starting unit is invalid. The damage chart is optional for
## states that never resolve combat (e.g. movement-only tests).
##
## `p_commanders` (team -> CommanderType) is assigned *before* the opening
## begin_turn, so the first player's day-1 start-of-turn doctrine — a supply
## radius, a repair discount — is resolved against its real commander rather
## than the neutral one. Callers that name commanders must pass them here, not
## set_commander after: begin_turn only runs once, and it runs inside create.
static func create(
	p_map: MapData,
	unit_db: UnitDB,
	p_damage_chart: DamageChart = null,
	p_commanders: Dictionary = {}
) -> GameState:
	var state := GameState.new()
	state.map = p_map
	state.damage_chart = p_damage_chart
	state.property_owners = p_map.initial_owners()
	for team in TEAMS:
		state.funds[team] = 0
	for entry: Dictionary in p_map.starting_units:
		var type: UnitType = unit_db.by_symbol(entry.symbol)
		if type == null:
			push_error("GameState: unknown unit symbol '%s'" % entry.symbol)
			return null
		var cell: Vector2i = entry.cell
		if state.unit_at(cell) != null:
			push_error("GameState: two starting units on cell %s" % cell)
			return null
		if not p_map.terrain_at(cell).is_passable(type.move_class):
			push_error(
				(
					"GameState: %s cannot stand on %s at %s"
					% [type.id, p_map.terrain_at(cell).id, cell]
				)
			)
			return null
		state.units.append(Unit.create(type, entry.team, cell))
	for team: int in p_commanders:
		state.set_commander(team, p_commanders[team])
	TurnRules.begin_turn(state)  # day-1 income and upkeep for the first player
	return state


# --- commanders --------------------------------------------------------------


## A team's commander record, created neutral on demand so no caller ever has to
## branch on "does this side have a CO".
func commander_state(team: int) -> CommanderState:
	if not commanders.has(team):
		commanders[team] = CommanderState.create(CommanderType.neutral())
	return commanders[team]


## The doctrine hooks to ask about a team's units. Never null.
func commander_of(team: int) -> CommanderType:
	return commander_state(team).type


func set_commander(team: int, type: CommanderType) -> void:
	commanders[team] = CommanderState.create(type)


func power_active(team: int) -> bool:
	return commander_state(team).power_active


## Banks charge for a team, capped at what its power costs: an idle meter can
## never hold a second power's worth. A commander with no power banks nothing,
## which is what keeps a no-CO match free of the whole economy. And a team whose
## power is *running* banks nothing either: firing empties the meter, and letting
## the combat the power enables refill it would mean the meter never has to be
## earned again — you fire, and it is READY the moment the power comes down. So it
## only fills once the power is back down, which is what makes the reset stick.
func add_charge(team: int, points: int) -> void:
	var co_state := commander_state(team)
	if not co_state.type.has_power() or points <= 0 or co_state.power_active:
		return
	co_state.charge = mini(co_state.charge + points, co_state.type.power_cost)


## Banks both sides' share of one unit losing `hp_lost` internal HP. Value is
## the victim's cost prorated by the HP taken off it — halving a 7 000 Tank is
## 3 500 points — and all of it is integer math so replays stay exact.
func bank_losses(victim: Unit, hp_lost: int, dealer_team: int) -> void:
	if hp_lost <= 0:
		return
	var value := victim.type.cost * hp_lost / 100
	add_charge(victim.team, value * CHARGE_PCT_LOST / 100)
	add_charge(dealer_team, value * CHARGE_PCT_DEALT / 100)


# --- board -------------------------------------------------------------------


func unit_at(cell: Vector2i) -> Unit:
	for unit in units:
		if unit.carrier == null and unit.cell == cell:
			return unit
	return null


func units_of(team: int) -> Array[Unit]:
	var result: Array[Unit] = []
	for unit in units:
		if unit.team == team:
			result.append(unit)
	return result


## Units riding inside the given transport.
func cargo_of(transport: Unit) -> Array[Unit]:
	var result: Array[Unit] = []
	for unit in units:
		if unit.carrier == transport:
			result.append(unit)
	return result


func remove_unit(unit: Unit) -> void:
	# Cargo goes down with its transport.
	for passenger in cargo_of(unit):
		remove_unit(passenger)
	units.erase(unit)
	# A dying unit abandons any capture in progress. A passenger owns no cell of
	# its own — its stored cell is stale from wherever it last boarded — so it can
	# hold no capture, and erasing by that cell would wipe an unrelated one.
	if unit.carrier == null:
		capture_progress.erase(unit.cell)
	_check_rout(unit.team)


func owner_at(cell: Vector2i) -> int:
	return property_owners.get(cell, MapData.NEUTRAL)


func set_owner(cell: Vector2i, team: int) -> void:
	property_owners[cell] = team


func properties_of(team: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for cell: Vector2i in property_owners:
		if property_owners[cell] == team:
			cells.append(cell)
	cells.sort()
	return cells


## Commits a unit's move along `path`: an abandoned capture on the vacated cell
## resets to the full point count, fuel is spent per terrain cost, cargo rides
## along, and the unit is exhausted. Sole move-commit entry point, shared by
## every movement-type command's apply.
##
## The path was planned with the mover's knowledge, so it may run onto or through
## an enemy the mover could not see (fogged, or a dived sub it was not next to).
## When it does, the move is cut short at the last free cell before that enemy —
## the Advance Wars trap — and the return says so, telling the caller to drop any
## follow-on it had bound to the move. Fuel is charged only for the steps taken.
func advance_unit(unit: Unit, path: Array[Vector2i]) -> bool:
	var stop := path.size() - 1
	var ambushed := false
	for i in range(1, path.size()):
		var blocker := unit_at(path[i])
		if blocker != null and blocker.team != unit.team:
			ambushed = true
			# Never end on a cell a friendly is passing-through, nor past the
			# origin: back up to the last cell that is actually free to stand on.
			stop = i - 1
			while stop > 0 and unit_at(path[stop]) != null:
				stop -= 1
			break
	var walked: Array[Vector2i] = path.slice(0, stop + 1)
	var dest: Vector2i = walked[walked.size() - 1]
	if dest != walked[0]:
		capture_progress.erase(walked[0])
	var fuel_spent := 0
	for i in range(1, walked.size()):
		# Through MovementResolver, not the terrain directly, so a doctrine that
		# discounts terrain charges the discounted fuel too — the player is never
		# billed for a step the range overlay showed them as cheaper.
		fuel_spent += MovementResolver.step_cost(self, unit, map.terrain_at(walked[i]))
	unit.fuel = maxi(0, unit.fuel - fuel_spent)
	unit.cell = dest
	unit.acted = true
	for passenger in cargo_of(unit):
		passenger.cell = dest
	return ambushed


func next_team() -> int:
	var index := TEAMS.find(current_team)
	return TEAMS[(index + 1) % TEAMS.size()]


func _check_rout(dead_team: int) -> void:
	if winner != 0 or not units_of(dead_team).is_empty():
		return
	for team in TEAMS:
		if team != dead_team:
			winner = team
			return
