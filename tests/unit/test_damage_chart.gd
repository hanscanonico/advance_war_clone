extends GutTest
## Lint over data/damage_chart.tres, because every way that file goes wrong is
## silent. A missing entry *is* the rule "this attacker cannot damage that
## defender" (DamageChart.base_damage returns -1, can_attack reads it as no), so
## a typo'd id, a forgotten row or a whole missing column produces a matchup that
## simply never happens — no error, no crash, nothing in the log. The only place
## that can be caught is here.
##
## What each test asserts is deliberately structural rather than numerical:
## balance lives in the numbers and moves with playtesting, but "an anti-air gun
## can shoot at aircraft" is not a balance question, and neither is "every id in
## the chart is a unit that exists".

var unit_db: UnitDB
var chart: DamageChart

## Units expected to reach a whole domain, and which. This is the table that
## catches a missing *column* — the failure a per-row check cannot see, since a
## row with nine sensible entries looks perfectly healthy while lacking a tenth.
##
## The B-Copter is listed for land only on purpose: it strafes the ground army
## and duels other helicopters, but a gunship does not dogfight a jet.
const EXPECTED_REACH := {
	&"anti_air": [UnitType.AIR, UnitType.LAND],
	&"fighter": [UnitType.AIR],
	&"bomber": [UnitType.LAND],
	&"b_copter": [UnitType.LAND],
	&"missiles": [UnitType.AIR],
}

## Aircraft that fly beyond the reach of anything but a dedicated air weapon.
## Helicopters are deliberately absent: a tank's machine gun plinks a gunship for
## a tenth of its health, and that chip damage is what stops a copter rush being
## free against an army that brought no anti-air.
const HIGH_FLYING: Array[StringName] = [&"fighter", &"bomber"]

## Everything in the roster that can shoot upward at a fixed-wing aircraft. The
## price of a Bomber buys immunity to everything outside this list, so the list
## growing by accident is a balance change nobody decided to make.
const AIR_ANSWERS: Array[StringName] = [&"anti_air", &"fighter", &"missiles"]


func before_each() -> void:
	unit_db = UnitDB.load_default()
	chart = load("res://data/damage_chart.tres")


## Both levels of the chart are keyed by unit id, and a misspelling on either
## looks exactly like a matchup that was never meant to exist.
func test_every_id_in_the_chart_is_a_real_unit() -> void:
	for attacker: StringName in chart.chart:
		assert_not_null(unit_db.by_id(attacker), "chart row '%s' is not a unit id" % attacker)
		var row: Dictionary = chart.chart[attacker]
		for defender: StringName in row:
			assert_not_null(
				unit_db.by_id(defender),
				"chart entry %s -> '%s' is not a unit id" % [attacker, defender]
			)


## An armed unit with no row cannot attack anything at all, which is a unit that
## quietly does not work rather than one that is weak.
func test_every_armed_unit_has_a_row() -> void:
	for unit_type in unit_db.all():
		if unit_type.max_range <= 0:
			continue
		assert_true(
			chart.chart.has(unit_type.id),
			"%s carries a weapon but has no damage chart row" % unit_type.id
		)


## The mirror: an unarmed unit with a row would be a weapon nobody can fire, and
## a sign the roster and the chart have drifted.
func test_no_unarmed_unit_has_a_row() -> void:
	for unit_type in unit_db.all():
		if unit_type.max_range > 0:
			continue
		assert_false(
			chart.chart.has(unit_type.id),
			"%s is unarmed, so a chart row for it can never be used" % unit_type.id
		)


## Every unit has to be killable by something, or it is an unanswerable piece.
func test_every_unit_can_be_attacked_by_something() -> void:
	for unit_type in unit_db.all():
		var attackers := 0
		for attacker: StringName in chart.chart:
			if chart.can_attack(attacker, unit_type.id):
				attackers += 1
		assert_gt(attackers, 0, "nothing in the roster can damage a %s" % unit_type.id)


## The missing-column check. Each entry in EXPECTED_REACH names a unit whose
## whole point is a domain it must be able to hit; losing one column of that
## domain leaves a row that still looks well-populated.
func test_specialists_reach_every_unit_in_the_domains_they_answer() -> void:
	for attacker: StringName in EXPECTED_REACH:
		var attacker_type := unit_db.by_id(attacker)
		assert_not_null(attacker_type, "EXPECTED_REACH names '%s', which is not a unit" % attacker)
		if attacker_type == null:
			continue
		for domain: StringName in EXPECTED_REACH[attacker]:
			for defender in unit_db.all():
				if defender.domain != domain:
					continue
				assert_true(
					chart.can_attack(attacker, defender.id),
					"%s should be able to damage %s (a %s unit)" % [attacker, defender.id, domain]
				)


## Fixed-wing aircraft are answered by specialists and by nothing else. This is
## the rule that makes Anti-Air worth building and a Bomber worth its price, so
## it is asserted rather than left to whoever edits the chart next: one stray
## column letting artillery shell a fighter rewrites the whole air game by
## accident, and nothing else in the project would notice.
func test_only_air_answers_can_touch_a_fixed_wing_aircraft() -> void:
	for defender: StringName in HIGH_FLYING:
		assert_not_null(unit_db.by_id(defender), "HIGH_FLYING names '%s'" % defender)
		for attacker: StringName in chart.chart:
			if attacker in AIR_ANSWERS:
				continue
			assert_false(
				chart.can_attack(attacker, defender),
				"%s can hit the %s without being an air answer" % [attacker, defender]
			)


## The other half of the same rule: an air answer that cannot reach the thing it
## exists to shoot down is a unit with no purpose, and reads as a balance problem
## rather than the missing chart entry it is.
func test_every_air_answer_reaches_every_fixed_wing_aircraft() -> void:
	for attacker: StringName in AIR_ANSWERS:
		for defender: StringName in HIGH_FLYING:
			assert_true(
				chart.can_attack(attacker, defender),
				"%s exists to shoot down aircraft but cannot damage the %s" % [attacker, defender]
			)


## Damage values are percentages of a full-health unit; a negative one would read
## as "cannot attack" and a wild one is a data-entry slip rather than a balance
## choice.
func test_damage_values_are_sane_percentages() -> void:
	for attacker: StringName in chart.chart:
		var row: Dictionary = chart.chart[attacker]
		for defender: StringName in row:
			var damage: int = row[defender]
			assert_between(damage, 1, 200, "%s -> %s is %d%%" % [attacker, defender, damage])
