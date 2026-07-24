extends GutTest
## Cargo sunk with its transport charges both Command Power meters exactly as the
## same units killed on deck would. A transport banked only its own value before,
## letting a full lander's worth of tanks vanish uncharged from both sides.

const TANK_COST := 7000
const INFANTRY_COST := 1000
const APC_COST := 5000

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart
var commander_db: CommanderDB


func before_each() -> void:
	terrain_db = TerrainDB.load_default()
	unit_db = UnitDB.load_default()
	chart = load("res://data/damage_chart.tres")
	commander_db = CommanderDB.load_default()


func _state(map_text: String) -> GameState:
	var map := MapData.parse(map_text, terrain_db)
	var state := GameState.create(map, unit_db, chart)
	assert_not_null(state)
	# Both sides need a power for the meter to exist at all.
	state.set_commander(1, commander_db.by_id(&"alina_ward"))
	state.set_commander(2, commander_db.by_id(&"viktor_draeg"))
	return state


func _board(state: GameState, id: StringName, team: int, carrier: Unit) -> Unit:
	var unit := Unit.create(unit_db.by_id(id), team, carrier.cell)
	unit.carrier = carrier
	state.units.append(unit)
	return unit


## A team-1 Tank sinks a team-2 APC carrying a Tank and an Infantry. The two
## passengers used to vanish uncharged; now each banks for both sides exactly as
## it would if it had been killed standing on deck.
func test_sinking_a_loaded_transport_banks_its_cargo_for_both_sides() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 t 0 0\n2 p 1 0")
	state.rng.seed = 4
	var apc := state.units[1]
	apc.hp = 10  # any hit sinks it, so it banks its full remaining 10 HP
	_board(state, &"tank", 2, apc)
	_board(state, &"infantry", 2, apc)
	var result := CombatResolver.resolve(state, state.units[0], apc)
	assert_true(result.defender_died, "the transport has to sink for this test to mean anything")
	# Loser (team 2) banks the whole value of every unit lost; dealer (team 1)
	# banks half of each. The transport lost 10 HP, the cargo was at full HP.
	var transport_loss := APC_COST * 10 / 100
	assert_eq(
		state.commander_state(2).charge,
		transport_loss + TANK_COST + INFANTRY_COST,
		"the loser banks transport and cargo alike"
	)
	assert_eq(
		state.commander_state(1).charge,
		transport_loss / 2 + TANK_COST / 2 + INFANTRY_COST / 2,
		"the dealer banks half of transport and cargo alike"
	)


## An empty transport is unchanged: only its own value is banked, no phantom cargo.
func test_sinking_an_empty_transport_banks_only_itself() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 t 0 0\n2 p 1 0")
	state.rng.seed = 4
	var apc := state.units[1]
	apc.hp = 10
	var result := CombatResolver.resolve(state, state.units[0], apc)
	assert_true(result.defender_died)
	assert_eq(state.commander_state(2).charge, APC_COST * 10 / 100, "just the transport")
	assert_eq(state.commander_state(1).charge, APC_COST * 10 / 100 / 2)


## The cap still holds: a transport whose cargo is worth more than the meter can
## never bank a second power's worth from one sinking.
func test_cargo_banking_respects_the_charge_cap() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 t 0 0\n2 p 1 0")
	state.rng.seed = 4
	var apc := state.units[1]
	apc.hp = 10
	# Two full Tanks alone are 14 000 of loss against a 13 000 power.
	_board(state, &"tank", 2, apc)
	_board(state, &"tank", 2, apc)
	var result := CombatResolver.resolve(state, state.units[0], apc)
	assert_true(result.defender_died)
	var co_state := state.commander_state(2)
	assert_eq(co_state.charge, co_state.type.power_cost, "one sinking never overfills the meter")
	assert_true(co_state.is_ready())


## Nesting can only survive in an old save, but the erase recurses so the banking
## must too: an outer transport holding a transport holding a unit banks all three.
func test_cargo_banking_recurses_through_nested_transports() -> void:
	var state := _state("[terrain]\n..\n[units]\n1 t 0 0\n2 p 1 0")
	state.rng.seed = 4
	var outer := state.units[1]
	outer.hp = 10
	var inner := _board(state, &"apc", 2, outer)
	var passenger := Unit.create(unit_db.by_id(&"infantry"), 2, outer.cell)
	passenger.carrier = inner
	state.units.append(passenger)
	assert_eq(state.cargo_of(inner), [passenger] as Array[Unit], "the nesting is set up")
	var result := CombatResolver.resolve(state, state.units[0], outer)
	assert_true(result.defender_died)
	assert_eq(
		state.commander_state(2).charge,
		APC_COST * 10 / 100 + APC_COST + INFANTRY_COST,
		"the deeply nested passenger is banked too"
	)
