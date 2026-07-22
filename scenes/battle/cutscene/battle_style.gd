class_name BattleStyle
extends Resource
## How one kind of weapon looks and sounds when it fires in the battle cut-in.
##
## Pure presentation, and deliberately so (plan D5): there is no gameplay number
## anywhere below. What a shot *does* is the damage chart's and the resolver's;
## this only says whether it reads as a burst of tracer, a single heavy shell or
## a smoke-trailed rocket, and how long it hangs in the air on the way. Six of
## these cover eighteen units, which is why the roster needed no per-unit art.
##
## The class lives under scenes/ and the resources under data/battle_anim/, the
## same split every other data-driven thing here uses — except that this one may
## never be loaded from core/, which is why it is not in core/ to be reached for.
## UnitType carries only the key (`battle_style`), exactly as it carries
## `atlas_col`: a StringName naming a presentation record, and nothing more.

## Projectile kinds. What each looks like is CutsceneFx's business; this is the
## vocabulary the two agree on.
const NONE := &"none"  # unarmed — nothing leaves the barrel, ever
const TRACER := &"tracer"  # rapid dashes, several per volley
const SHELL := &"shell"  # one heavy round on a lobbed arc

@export var id: StringName
@export var projectile: StringName = NONE
## Rounds each standing figure contributes to the volley. A squad of five
## infantry throws a wall of tracer; a battleship fires once.
@export_range(1, 4) var shots_per_figure: int = 1
## Sfx name for the volley. Missing entries are silently skipped by Sfx, so a
## style may name a sound that has not been generated yet without breaking.
@export var sfx: StringName = &"shot"
## Multiplies the volley's travel budget. Under 1.0 snaps, over 1.0 hangs — an
## arcing shell has to look like it took its time getting there.
@export_range(0.5, 2.0) var travel_scale: float = 1.0
## Peak height of a lobbed round above the firing line, in pixels. Zero is flat.
@export var arc: float = 0.0
## Colour of the round in flight and of the streak behind it.
@export var tint: Color = Color(1.0, 0.949, 0.659)
## Radius of the muzzle starburst. Zero draws none, which is what `NONE` wants.
@export var muzzle: float = 12.0


## True when this weapon puts anything on screen at all. An APC, a T-Copter and a
## Lander only ever take the hit, and their side of the frame stays quiet.
func fires() -> bool:
	return projectile != NONE
