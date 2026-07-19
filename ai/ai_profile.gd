class_name AIProfile
extends Resource
## Everything AIController weighs when it picks a command. Pure data, so
## difficulty and iteration are edits to a .tres rather than to planner logic.
##
## The defaults here match `data/ai/default.tres` and reproduce the behaviour
## the planner had when these were constants: same state plus same profile
## yields the same command. Tests that care about a specific weight build a
## profile explicitly rather than leaning on the default file.
##
## Node-free like the rest of ai/ and core/, so it is usable from tests.

const DEFAULT_PATH := "res://data/ai/default.tres"

## Multiplier on an attack's value when the shot would finish the target off.
@export var kill_bonus: float = 1.6
## How heavily the expected counter-attack discounts an attack's value. Below
## 1.0 because the AI is willing to trade.
@export var counter_weight: float = 0.6
## Base value of taking a property, tuned to sit near a city's worth.
@export var capture_score: float = 900.0
## Capturing the enemy HQ ends the match, so it is worth a multiple of a city.
@export var hq_capture_multiplier: float = 3.0
## Added per capture point already chipped off, so the AI finishes what it
## started instead of wandering to a fresh property.
@export var capture_progress_bonus: float = 45.0
## Charged per step of movement, so all else equal the closer option wins.
@export var step_cost_penalty: float = 4.0
## At or below this HP a unit heads for a friendly property to repair.
@export var retreat_hp: int = 45
## Scores below this are not worth acting on; the unit advances instead.
@export var min_useful_score: float = 40.0
## What advancing is worth. Deliberately tiny: it is the fallback.
@export var advance_score: float = 1.0
## Build preference once enough capture units exist, strongest first.
@export var build_priority: Array[StringName] = [&"md_tank", &"tank", &"artillery", &"mech"]
## Infantry are bought until the team has this many capture-capable units.
@export var capture_unit_target: int = 3


## The profile the game plays with. Falling back to an unmodified profile keeps
## a missing or broken file from taking the AI out entirely — it plays with the
## defaults above, which are the same numbers.
static func load_default() -> AIProfile:
	var profile: AIProfile = load(DEFAULT_PATH)
	if profile == null:
		push_error("AIProfile: cannot load %s; using built-in defaults" % DEFAULT_PATH)
		return AIProfile.new()
	return profile
