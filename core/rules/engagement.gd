class_name Engagement
extends RefCounted
## One attacker-versus-defender exchange, exactly as the damage formula sees it.
##
## Commander hooks read this rather than the two Units, because a forecast and
## the attack it predicts are not looking at the same board: the attacker has
## usually not moved yet, so the shot comes from a *planned* cell rather than
## `attacker.cell`, and a forecast's counter uses the defender's projected
## post-attack HP. Handing the hooks the effective values keeps the damage
## preview and the resolved attack on identical numbers, which is the whole
## reason both go through CombatResolver._damage_pct.
##
## Pure data, no behaviour: a doctrine asks it questions, never changes it.

var attacker: Unit
## The cell the shot is fired from — not always `attacker.cell`; see above.
var attacker_cell: Vector2i
## Displayed HP (1-10) the formula should use for the attacker.
var attacker_hp: int
var defender: Unit
## The cell the shot is scored against — not always `defender.cell`; a forecast
## may ask about a cell the defender has not moved to (CombatResolver.forecast_at).
var defender_cell: Vector2i
## Displayed HP (1-10) the formula should use for the defender.
var defender_hp: int
## True when this is the defender shooting back, so a doctrine can tell
## initiating from retaliating (Mara Voss).
var is_counter := false


static func create(
	p_attacker: Unit,
	p_attacker_cell: Vector2i,
	p_attacker_hp: int,
	p_defender: Unit,
	p_defender_cell: Vector2i,
	p_defender_hp: int,
	p_is_counter: bool = false
) -> Engagement:
	var fight := Engagement.new()
	fight.attacker = p_attacker
	fight.attacker_cell = p_attacker_cell
	fight.attacker_hp = p_attacker_hp
	fight.defender = p_defender
	fight.defender_cell = p_defender_cell
	fight.defender_hp = p_defender_hp
	fight.is_counter = p_is_counter
	return fight
