class_name BattleMenus
extends RefCounted
## Which rows each of the battle scene's menus offers.
##
## Contents only. Battle still decides when a menu opens, where on screen it
## sits, and what choosing a row does; this decides what is on it. Split out of
## Battle for the same reason BattleView and BattleAnimator were — it is a
## separate job, and this one turns out to need nothing from the scene at all:
## every row below is gated by the command that would run it, or by the same
## terrain data that command validates against.
##
## That gating is the point rather than a convenience. A menu that worked out
## for itself whether a Load were legal would be a second opinion on the rules,
## and the day it disagreed with the command the player would be offered an
## action that is then refused. So each row asks the authority: Load and Join ask
## their commands, Supply asks SupplyCommand who is in reach, and production asks
## the terrain what it builds — exactly what BuildCommand checks.
##
## No scene tree and no sprite here, like the rest of the layers Battle delegates
## to. The one autoload it reads is Settings, for the speed row's label, and that
## is the same rule as everything above rather than an exception to it: whoever
## owns the answer is who gets asked.

const CANCEL := {"id": &"cancel", "label": "Cancel"}


## Rows for a unit whose move preview has finished on `dest` (the last cell of
## `path`). `can_fire` and `drop_passengers` are passed in because working them
## out needs the viewing team's fog, which is Battle's to know and not ours.
##
## Each droppable passenger gets its own row — a Lander can hold two and only one
## of them might fit the ground beside it — so a row names the unit it unloads and
## its id carries the passenger's index into `drop_passengers`.
static func unit_actions(
	game: GameState, unit: Unit, path: Array[Vector2i], can_fire: bool, drop_passengers: Array[Unit]
) -> Array[Dictionary]:
	var dest: Vector2i = path[path.size() - 1]
	var actions: Array[Dictionary] = []
	if can_fire:
		actions.append({"id": &"fire", "label": "Fire"})
	var terrain := game.map.terrain_at(dest)
	if unit.type.can_capture and terrain.is_property and game.owner_at(dest) != unit.team:
		actions.append({"id": &"capture", "label": "Capture"})
	for i in drop_passengers.size():
		# One passenger drops under a plain "Drop"; a Lander's two are named apart.
		var label := "Drop"
		if drop_passengers.size() > 1:
			label += " %s" % drop_passengers[i].type.display_name
		actions.append({"id": StringName("drop_%d" % i), "label": label})
	if (
		unit.type.can_resupply
		and not SupplyCommand.new(unit, path).friendlies_in_reach(game, dest).is_empty()
	):
		actions.append({"id": &"supply", "label": "Supply"})
	if unit.type.can_dive:
		# One row, whichever way the boat is not currently facing. DiveCommand
		# validates the same flag, so the menu cannot offer a dive to something
		# already under.
		actions.append(
			(
				{"id": &"surface", "label": "Surface"}
				if unit.dived
				else {"id": &"dive", "label": "Dive"}
			)
		)
	actions.append({"id": &"wait", "label": "Wait"})
	actions.append(CANCEL)
	return actions


## Rows for confirming onto a reachable cell a friendly already stands on:
## boarding a transport with room, or merging into a damaged twin. Empty when
## neither applies, which is how Battle tells an ordinary move from one of these.
static func destination_actions(
	game: GameState, unit: Unit, path: Array[Vector2i]
) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	if path.is_empty():
		return actions
	if LoadCommand.new(unit, path).validate(game) == "":
		actions.append({"id": &"load", "label": "Load"})
	if JoinCommand.new(unit, path).validate(game) == "":
		actions.append({"id": &"join", "label": "Join"})
	return actions


## Rows for a production property: what this particular facility builds,
## cheapest first, greyed out when the funds fall short.
##
## Filtered by the terrain's own build list, so a hangar never offers a tank and
## a base never offers a bomber — the same list BuildCommand rejects them with.
static func build_actions(
	game: GameState, unit_db: UnitDB, terrain: TerrainType, team: int, identity: SideIdentity
) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	var row := identity.atlas_row(team)  # the building side's faction art, not a team int
	for unit_type in unit_db.all():
		if not terrain.can_build(unit_type.move_class):
			continue
		(
			actions
			. append(
				{
					"id": unit_type.id,
					"label": "%s  %d" % [unit_type.display_name, unit_type.cost],
					"disabled": game.funds[team] < unit_type.cost,
					"icon": UnitSprite.texture_for(unit_type, row),
				}
			)
		)
	actions.append(CANCEL)
	return actions


## Rows for the menu opened on empty ground: the turn-level actions. The HUD has
## a button for the Command Power, and this keeps it reachable from the keyboard
## too, which the rest of the game already is.
##
## The Speed row reads its label off Settings for the same reason every row above
## asks its command: the tier the player is watching at has one owner, and a menu
## that remembered its own copy would eventually show a speed the game is not
## playing at. Choosing it cycles to the next tier — see Battle's map handler.
static func map_actions(game: GameState) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	var co_state := game.commander_state(game.current_team)
	if co_state.is_ready():
		actions.append({"id": &"power", "label": co_state.type.power_name})
	actions.append({"id": &"commanders", "label": "Commanders"})
	actions.append({"id": &"speed", "label": "Speed: %s" % Settings.speed.display_name})
	actions.append({"id": &"end_turn", "label": "End Turn"})
	actions.append({"id": &"save", "label": "Save"})
	actions.append(CANCEL)
	return actions
