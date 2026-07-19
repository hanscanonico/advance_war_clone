class_name CommanderType
extends Resource
## One general: who they are, the Command Power they charge toward, and the
## hooks their doctrine is expressed through.
##
## This base class *is* the neutral commander. Every hook returns the value the
## rules had before commanders existed, so a side that picked no CO plays
## exactly as it did before this file — resolvers call the hooks unconditionally
## and never branch on "does this team have a commander".
##
## Each general is a small subclass in core/commanders/ overriding two or three
## of these, with its balance numbers as @export on a .tres in data/commanders/:
## behaviour in typed classes, numbers in data, like the rest of the repo.
##
## Three rules hold for every hook here:
##
## 1. Simulation state only. Never a Node, never a scene — this is core/.
## 2. Integer percentage points, never floats, so no doctrine can drift the
##    damage numbers a golden-value test pins down.
## 3. A hook checks `is_active()` itself. A Command Power is not a separate
##    system; it is "this hook returns a bigger number while the power runs".

## Inclusive bounds of the standard combat luck roll. They live here rather than
## on CombatResolver because a doctrine may narrow or shift the range (Lyra
## Quill), which makes them commander data.
const LUCK_MIN := 0
const LUCK_MAX := 9

## Terrain defence stars cap after star_bonus and star_pierce have applied.
const MAX_STARS := 5

const NEUTRAL_ID := &"none"

## How long a Command Power lasts once fired. Two expiry points, both
## unambiguous — see PowerCommand.
enum Duration {
	## Ends when the owner ends the turn they fired it on.
	OWNER_TURN,
	## Survives the opponent's turn and ends at the owner's next turn start.
	ROUND,
}

@export var id: StringName = NEUTRAL_ID
@export var display_name: String = "No Commander"
## Which of the four powers this general belongs to. Flavour and UI grouping;
## the rules never read it.
@export var faction: String = ""
## One line of doctrine, for the CO picker.
@export_multiline var doctrine_text: String = ""
@export var power_name: String = ""
@export_multiline var power_text: String = ""
## Charge points the meter must hold before the power fires. 0 means this
## commander has no power, which also stops its meter ever filling.
@export var power_cost: int = 0
@export var power_duration: Duration = Duration.OWNER_TURN

static var _neutral: CommanderType


## The commander a side plays without one: every hook at its default, no power,
## and a meter that never fills. Shared, because it holds no per-match state.
static func neutral() -> CommanderType:
	if _neutral == null:
		_neutral = CommanderType.new()
	return _neutral


func has_power() -> bool:
	return power_cost > 0


## True while this commander's team is running its Command Power. Hooks that a
## power touches gate on this; the passive half of a doctrine ignores it.
func is_active(state: GameState, team: int) -> bool:
	return state.power_active(team)


# --- combat ------------------------------------------------------------------


## Percentage points added to the damage dealt. Asked of the *attacker's*
## commander, including when the attacker is a defender shooting back.
func attack_bonus(_state: GameState, _fight: Engagement) -> int:
	return 0


## Percentage points of damage resistance. Asked of the *defender's* commander.
## The formula reads it as (200 - def) / 100, so +10 is x0.9 damage taken and
## -10 is x1.1 — the classic Advance Wars defence shape.
func defense_bonus(_state: GameState, _fight: Engagement) -> int:
	return 0


## Terrain defence stars added for the defender. Defender's commander.
func star_bonus(_state: GameState, _fight: Engagement) -> int:
	return 0


## Terrain defence stars the attack ignores. Attacker's commander.
func star_pierce(_state: GameState, _fight: Engagement) -> int:
	return 0


## Inclusive lower bound of the luck roll. Attacker's commander.
func luck_min(_state: GameState, _fight: Engagement) -> int:
	return LUCK_MIN


## Inclusive upper bound of the luck roll. Attacker's commander.
func luck_max(_state: GameState, _fight: Engagement) -> int:
	return LUCK_MAX


# --- movement ----------------------------------------------------------------


## Movement points added on top of the unit type's own.
func move_bonus(_state: GameState, _unit: Unit) -> int:
	return 0


## What one step onto `terrain` costs `unit`; `base` is the terrain's own cost
## for that movement class. Called from the Dijkstra flood fill *and* from the
## fuel spend in GameState.advance_unit, so a discount never leaves fuel
## disagreeing with the path the player was shown.
##
## MovementResolver.step_cost enforces the two invariants a doctrine cannot
## break: impassable stays impassable, and a step never costs less than 1.
func terrain_cost(_state: GameState, _unit: Unit, _terrain: TerrainType, base: int) -> int:
	return base


## Tiles added to the unit's maximum firing range.
func range_bonus(_state: GameState, _unit: Unit) -> int:
	return 0


# --- vision ------------------------------------------------------------------


## Vision range added to this commander's own units.
func vision_bonus(_state: GameState, _unit: Unit) -> int:
	return 0


## Vision this commander strips from an *enemy* unit (Orin Flux's Signal Jam).
## Asked of every commander except the viewing unit's own, so it is the one hook
## a team's doctrine uses to reach across the table.
func enemy_vision_bonus(_state: GameState, _unit: Unit) -> int:
	return 0


## True when `unit` sees into woods at range, ignoring the standing rule that
## woods are only revealed from an adjacent tile.
func sees_into_woods(_state: GameState, _unit: Unit) -> bool:
	return false


## True while `unit` is hidden from every enemy, adjacent ones included
## (Sable Wren's Vanish). Fog only — the unit is still on the board, and an
## enemy that tries to move into its cell still finds it there.
func hides_unit(_state: GameState, _unit: Unit) -> bool:
	return false


# --- economy -----------------------------------------------------------------


## Percentage points added to a capture unit's chip per turn.
func capture_bonus_pct(_state: GameState, _unit: Unit) -> int:
	return 0


## How far a supply unit reaches, in tiles.
func supply_range(_state: GameState, _unit: Unit) -> int:
	return 1


## What a paid repair costs, as a percentage of the standard price.
func repair_cost_pct(_state: GameState, _unit: Unit) -> int:
	return 100


# --- powers ------------------------------------------------------------------


## One-shot effects fired the instant the power activates: refills, heals, the
## enemy debuffs Signal Jam applies. Anything that lasts for the duration of the
## power belongs in the hooks above, gated on is_active(), not here.
func on_power_activated(_state: GameState, _team: int) -> void:
	pass
