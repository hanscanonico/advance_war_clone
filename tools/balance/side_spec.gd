class_name BalanceSideSpec
extends RefCounted
## One side of a Balance Lab matchup: `<commander>:<tier>` — a commander id (or
## `none`) and a difficulty tier, which is the whole description of a seat.
##
## The grammar lives here rather than in either caller because both need it and
## they must agree: the headless Lab scores a matchup, and the battle scene
## boots the *same* matchup for watch mode. A spec parsed two ways is a spec
## that eventually disagrees, and the replay-fidelity check would be measuring
## the parser instead of the sim.
##
## Node-free, like everything else the sim leans on, so GUT can drive it.

## What a side is when the flag is omitted: no doctrine, the shipped planner.
const DEFAULT_TEXT := "none:normal"

var commander: StringName = CommanderType.NEUTRAL_ID
var tier: StringName = Difficulty.DEFAULT_ID
## Empty when the spec parsed cleanly; otherwise why it did not.
var error: String = ""


## Parses `<commander>:<tier>`. Either half may be omitted (`gideon_holt`,
## `:hard`, or the empty string), and the missing one takes its default.
##
## Ids are checked against the databases rather than accepted on faith: a
## mistyped commander would otherwise silently become neutral through
## CommanderDB's forgiving lookup and the run would measure the wrong matchup.
static func parse(
	text: String, commander_db: CommanderDB, difficulty_db: DifficultyDB
) -> BalanceSideSpec:
	var spec := BalanceSideSpec.new()
	var trimmed := text.strip_edges()
	var parts := trimmed.split(":")
	var co := parts[0].strip_edges() if parts.size() > 0 else ""
	var tier := parts[1].strip_edges() if parts.size() > 1 else ""
	if parts.size() > 2:
		spec.error = "expected <commander>:<tier>, got '%s'" % trimmed
		return spec
	if co != "":
		var id := StringName(co)
		if not commander_db.has(id):
			spec.error = "unknown commander '%s'" % co
			return spec
		spec.commander = id
	if tier != "":
		var id := StringName(tier)
		if not difficulty_db.has(id):
			spec.error = "unknown difficulty tier '%s'" % tier
			return spec
		spec.tier = id
	return spec


## The canonical text form, so a spec round-trips through parse() unchanged and
## a run directory named after one is stable across reruns.
func text() -> String:
	return "%s:%s" % [commander, tier]


## Filename-safe, for the run directory and report labels: `gideon_holt-normal`.
func slug() -> String:
	return "%s-%s" % [commander, tier]


func has_commander() -> bool:
	return commander != CommanderType.NEUTRAL_ID
