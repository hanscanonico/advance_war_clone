class_name GameSpeed
extends RefCounted
## How fast the battle's theatre plays out on screen: one of four tiers, picked
## on the main menu and switchable mid-match.
##
## Presentation pacing and nothing else. No file under core/ or ai/ imports this
## or can reach a tier through Settings, so a speed change cannot move an
## outcome, a save, a replay or a seeded roll — the sim never observes the clock
## the theatre runs on. That is also why these numbers live here as constants
## rather than as .tres files under data/, breaking the difficulty-tier symmetry
## on purpose: data/ is for numbers the *sim* reads, and the whole safety
## argument of this setting is that the sim cannot read the speed.
##
## Which tier is active is Settings' answer and nobody else's. Callers ask it at
## the moment they animate rather than caching it at scene load, so a speed
## changed from the in-battle menu lands on the very next move.

## The tier a fresh install plays at: movement at twice the duration the game
## shipped with, which is the complaint this setting exists to fix. Quick is that
## original feel, one dropdown away.
const DEFAULT_ID := &"normal"
## Captures and scripted scenario runs pin this tier instead of reading the
## device preference: a screenshot must not depend on which machine took it.
##
## Instant, because a still frame has nothing to photograph in an animation and
## every second one runs for is a second `make smoke` spends waiting. Scenarios
## advance on the scene's own state machine rather than a frame count, which is
## what makes that safe — see BattleScenarioDriver._until_state. An explicit
## `--speed=` still wins, so a tier stays inspectable through a capture.
const CAPTURE_ID := &"instant"

## The durations the game shipped with, before any tier scaled them. Quick is
## these values exactly — which is what makes it "today's game, bit for bit".
const BASE_MOVE_STEP_SECONDS := 0.06
const BASE_FLASH_IN_SECONDS := 0.08
const BASE_FLASH_OUT_SECONDS := 0.12
const BASE_DEATH_FADE_SECONDS := 0.25
const BASE_COMMAND_DELAY_SECONDS := 0.2
## Banners are information, not theatre: they hold at a readable length whatever
## the tier and only tighten under Instant, because whose day it is must still
## register even when nothing else is being shown.
const BANNER_SECONDS := 1.2
const POWER_BANNER_SECONDS := 1.1
const INSTANT_BANNER_SECONDS := 0.5
## The AI opens its turn just after the day banner has cleared, so its opening
## beat tracks whatever the banner holds for at this tier rather than fixing a
## number of its own.
const START_DELAY_PADDING := 0.1

## Every tier, gentlest first — the order the menu lists and the in-battle row
## cycles in. `anim` scales movement, the hit flash and the death fade; `pace`
## scales the AI's think-beat between commands; `instant` skips the tweens
## outright instead of shortening them (an explicit branch, in the tradition of
## BattleAnimator's `capturing` flag, not a zero multiplied through the maths).
##
## This is the whole tuning surface: retuning a tier after playtest is one line.
const TIERS: Array[Dictionary] = [
	{"id": &"slow", "display_name": "Slow", "anim": 3.0, "pace": 1.5, "instant": false},
	{"id": &"normal", "display_name": "Normal", "anim": 2.0, "pace": 1.0, "instant": false},
	{"id": &"quick", "display_name": "Quick", "anim": 1.0, "pace": 1.0, "instant": false},
	{"id": &"instant", "display_name": "Instant", "anim": 0.0, "pace": 0.0, "instant": true},
]

## Built once from TIERS by `ordered()`; the four tiers are immutable, so every
## caller shares the same instances and `by_id(x) == by_id(x)` holds.
static var _ordered: Array[GameSpeed] = []

var id: StringName
var display_name: String
var anim_scale: float
var pace_scale: float
## True for the tier that shows results rather than playing them out.
var instant: bool


func _init(tier: Dictionary) -> void:
	id = tier["id"]
	display_name = tier["display_name"]
	anim_scale = tier["anim"]
	pace_scale = tier["pace"]
	instant = tier["instant"]


# --- the tier table ----------------------------------------------------------


## Every tier in menu order, gentlest first.
static func ordered() -> Array[GameSpeed]:
	if _ordered.is_empty():
		for tier: Dictionary in TIERS:
			_ordered.append(GameSpeed.new(tier))
	return _ordered


## The tier a fresh install plays at. Never null.
static func default_speed() -> GameSpeed:
	for tier in ordered():
		if tier.id == DEFAULT_ID:
			return tier
	return ordered()[0]


## Never null: an id naming no tier falls back to the default, the same
## defensive shape DifficultyDB answers a bad tier id with.
static func by_id(wanted: StringName) -> GameSpeed:
	for tier in ordered():
		if tier.id == wanted:
			return tier
	return default_speed()


## The tier after `wanted` in menu order, wrapping — what the in-battle Speed
## row cycles through.
static func next(wanted: StringName) -> GameSpeed:
	var all := ordered()
	for i in all.size():
		if all[i].id == wanted:
			return all[wrapi(i + 1, 0, all.size())]
	return default_speed()


# --- the durations a tier answers with ---------------------------------------


func move_step_seconds() -> float:
	return BASE_MOVE_STEP_SECONDS * anim_scale


func flash_in_seconds() -> float:
	return BASE_FLASH_IN_SECONDS * anim_scale


func flash_out_seconds() -> float:
	return BASE_FLASH_OUT_SECONDS * anim_scale


func death_fade_seconds() -> float:
	return BASE_DEATH_FADE_SECONDS * anim_scale


## Zero under Instant, where BattleAiRunner awaits a single frame instead so the
## board still repaints once per command.
func command_delay_seconds() -> float:
	return BASE_COMMAND_DELAY_SECONDS * pace_scale


func banner_seconds() -> float:
	return INSTANT_BANNER_SECONDS if instant else BANNER_SECONDS


func power_banner_seconds() -> float:
	return INSTANT_BANNER_SECONDS if instant else POWER_BANNER_SECONDS


## How long the AI waits before its first command: just past the day banner,
## however long this tier holds it.
func start_delay_seconds() -> float:
	return banner_seconds() + START_DELAY_PADDING
