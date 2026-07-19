extends GutTest
## CommanderType.wants_power: when each general thinks a full meter is worth
## spending, and the planner that asks.
##
## The default is the offensive read every commander used to share — an enemy
## inside the reach of a unit that has not acted. That is right for the powers
## whose value lands on the turn they fire, and wrong for the four that are not
## about this turn's fight at all: Hold the Line wants the *opponent's* turn,
## Open the Depots wants a worn-down army and no fight, Popular Uprising wants
## ground, Vanish wants somewhere to hide. Each of those overrides it, so the
## planner keeps asking one question.

var terrain_db: TerrainDB
var unit_db: UnitDB
var chart: DamageChart
var commander_db: CommanderDB


func before_each() -> void:
	terrain_db = TerrainDB.load_default()
	unit_db = UnitDB.load_default()
	chart = load("res://data/damage_chart.tres")
	commander_db = CommanderDB.load_default()


func _state(map_text: String, red: StringName) -> GameState:
	var map := MapData.parse(map_text, terrain_db)
	var state := GameState.create(map, unit_db, chart)
	assert_not_null(state)
	state.set_commander(1, commander_db.by_id(red))
	return state


func _wants(state: GameState) -> bool:
	return state.commander_of(1).wants_power(state, 1)


# --- the neutral default -----------------------------------------------------


## Alina Ward stands in for every commander that did not need an override:
## Coordinated Push is spent on this turn's fight, so this turn's fight gates it.
func test_the_default_fires_when_an_enemy_is_in_reach() -> void:
	var state := _state("[terrain]\n....\n[units]\n1 t 0 0\n2 i 2 0", &"alina_ward")
	assert_true(_wants(state), "a Tank two tiles from an Infantry has a fight to have")


func test_the_default_holds_when_the_enemy_is_far_away() -> void:
	var line := ".".repeat(20)
	var state := _state("[terrain]\n%s\n[units]\n1 i 0 0\n2 i 19 0" % line, &"alina_ward")
	assert_false(_wants(state), "nothing in reach means nothing to spend it on")


## Reach is measured off units that can still act: a side that has already
## spent its turn gains nothing from a power that boosts this turn's attacks.
func test_the_default_ignores_units_that_have_already_acted() -> void:
	var state := _state("[terrain]\n....\n[units]\n1 t 0 0\n2 i 2 0", &"alina_ward")
	state.units[0].acted = true
	assert_false(_wants(state))


# --- Mara Voss: the defensive trigger ----------------------------------------


## The finding this file was written for. Her army sits still with nothing it
## can reach, so the offensive default banks her meter forever — but the enemy
## Tank can reach *her*, which is exactly the turn Hold the Line exists for.
func test_hold_the_line_fires_when_an_enemy_can_reach_her() -> void:
	var state := _state("[terrain]\n........\n[units]\n1 g 0 0\n2 t 5 0", &"mara_voss")
	state.units[0].acted = true
	assert_true(_wants(state), "a Tank five tiles out is a turn she wants covered")


func test_hold_the_line_holds_when_nobody_can_reach_her() -> void:
	var line := ".".repeat(20)
	var state := _state("[terrain]\n%s\n[units]\n1 i 0 0\n2 i 19 0" % line, &"mara_voss")
	assert_false(_wants(state))


## The offensive default would have said yes here and Mara says no: an enemy she
## can shoot but that cannot answer is not what a defensive power is for. This
## pins the override as a genuine difference rather than a superset.
func test_hold_the_line_is_not_merely_the_default_plus_more() -> void:
	var state := _state("[terrain]\n.........\n[units]\n1 R 0 0\n2 i 5 0", &"mara_voss")
	var neutral := CommanderType.neutral()
	assert_true(
		neutral.wants_power(state, 1), "rockets outrange the infantry, so the default fires"
	)
	assert_false(_wants(state), "but an infantry that cannot reach her is no threat")


# --- Gideon Holt: no combat trigger at all -----------------------------------


func test_the_depots_open_for_a_worn_down_army() -> void:
	var state := _state("[terrain]\n....\n[units]\n1 i 0 0\n1 i 1 0", &"gideon_holt")
	assert_false(_wants(state), "a fresh army does not need them")
	state.units[0].hp = 50
	assert_false(_wants(state), "one scratched unit wastes a power that heals the side")
	state.units[1].fuel = 0
	assert_true(_wants(state), "two units in want of a depot is worth the meter")


## Nothing about a fight gates it, in either direction: an enemy in reach does
## not open the depots, and their absence does not keep them shut.
func test_the_depots_ignore_the_enemy_entirely() -> void:
	var state := _state("[terrain]\n....\n[units]\n1 i 0 0\n1 i 1 0\n2 t 2 0", &"gideon_holt")
	assert_false(_wants(state), "an enemy in reach is not a reason to resupply")
	state.units[0].hp = 50
	state.units[1].hp = 50
	assert_true(_wants(state))


# --- Tomas Reed: ground, not damage ------------------------------------------


func test_uprising_waits_for_a_reachable_property() -> void:
	var bare := _state("[terrain]\n....\n[units]\n1 i 0 0\n2 t 1 0", &"tomas_reed")
	assert_false(_wants(bare), "an enemy in reach is not what capture points are for")
	var city := _state("[terrain]\n.C..\n[units]\n1 i 0 0", &"tomas_reed")
	assert_true(_wants(city), "a city his infantry can stand on this turn is")


func test_uprising_ignores_a_property_he_already_owns() -> void:
	var state := _state("[terrain]\n.C..\n[owners]\n1 1 0\n[units]\n1 i 0 0", &"tomas_reed")
	assert_false(_wants(state))


## The flood fill is asked rather than a distance guess, so ground he cannot
## actually stand on this turn does not count.
func test_uprising_holds_when_the_property_is_out_of_range() -> void:
	var line := ".".repeat(19)
	var state := _state("[terrain]\n%sC\n[units]\n1 i 0 0" % line, &"tomas_reed")
	assert_false(_wants(state))


# --- Sable Wren: an ambush needs somewhere to hide ---------------------------


func test_vanish_fires_when_an_enemy_can_reach_her_line_in_cover() -> void:
	var state := _state("[terrain]\nF.......\n[units]\n1 i 0 0\n2 t 5 0", &"sable_wren")
	assert_true(_wants(state))


func test_vanish_holds_when_nobody_is_in_cover() -> void:
	var state := _state("[terrain]\n........\n[units]\n1 i 0 0\n2 t 5 0", &"sable_wren")
	assert_false(_wants(state), "both halves of Vanish key on cover, so it would do nothing")


# --- Nia Rowan and Orin Flux -------------------------------------------------


## Ghost March takes the default's fight *or* ground worth walking onto, since
## a commander with no combat modifier should not wait on a combat trigger.
func test_ghost_march_also_fires_for_reachable_ground() -> void:
	var state := _state("[terrain]\n.C..\n[units]\n1 i 0 0", &"nia_rowan")
	assert_false(CommanderType.neutral().wants_power(state, 1), "no enemy: the default holds")
	assert_true(_wants(state))


## Signal Jam is a debuff, so it goes off when the armies are in contact at all
## — including when it is the enemy closing the distance and his own units,
## having acted, could not answer.
func test_signal_jam_fires_on_contact_from_either_side() -> void:
	var state := _state("[terrain]\n........\n[units]\n1 g 0 0\n2 t 5 0", &"orin_flux")
	state.units[0].acted = true
	assert_true(_wants(state))


func test_signal_jam_holds_when_the_armies_are_apart() -> void:
	var line := ".".repeat(20)
	var state := _state("[terrain]\n%s\n[units]\n1 i 0 0\n2 i 19 0" % line, &"orin_flux")
	assert_false(_wants(state))


# --- the planner asks --------------------------------------------------------


## The gate is reached through AIController, not only by calling the hook: a
## Mara Voss with a full meter and no target of her own still fires, which is
## the behaviour the whole change exists to produce.
func test_the_planner_fires_a_defensive_power_with_no_target_of_its_own() -> void:
	var state := _state("[terrain]\n........\n[units]\n1 g 0 0\n2 t 5 0", &"mara_voss")
	state.add_charge(1, state.commander_of(1).power_cost)
	var command := AIController.new(unit_db).plan_next_command(state)
	assert_true(command is PowerCommand, "expected the power, got %s" % command)


## And the meter still has to be full — the hook decides timing, never legality.
func test_the_planner_never_fires_an_empty_meter() -> void:
	var state := _state("[terrain]\n........\n[units]\n1 g 0 0\n2 t 5 0", &"mara_voss")
	var command := AIController.new(unit_db).plan_next_command(state)
	assert_false(command is PowerCommand)
