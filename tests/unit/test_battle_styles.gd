extends GutTest
## Every unit names a weapon signature that exists, and the ones that cannot
## shoot name one that fires nothing.
##
## In scope despite living beside the cut-in: BattleStyle is a Resource and
## BattleStyleDB is a RefCounted, both Node-free, and what is under test is data
## integrity — a `.tres` naming a style that is not there — not how anything
## looks. The same reason tests/unit/test_maps.gd parses every shipped board.
##
## Worth pinning because the failure is quiet. A misspelled key does not crash:
## BattleStyleDB deliberately degrades to unarmed, so the unit simply stops
## firing anything in the cut-in and the exchange still resolves correctly. That
## is the right behaviour in play and exactly the wrong behaviour to discover in
## play.

var styles: BattleStyleDB
var units: UnitDB


func before_each() -> void:
	styles = BattleStyleDB.load_default()
	units = UnitDB.load_default()


func test_every_unit_names_a_style_that_exists() -> void:
	assert_gt(units.size(), 0, "no units loaded, so this would pass vacuously")
	for type in units.all():
		assert_true(
			styles.has(type.battle_style),
			(
				"%s names battle_style '%s', which is not in %s"
				% [type.id, type.battle_style, BattleStyleDB.STYLE_DIR]
			)
		)


## The roster's three transports are the only units the damage chart gives no
## attack at all. They are staged as defenders and never fire, so their style
## must be the one that puts nothing on screen — a transport with a cannon
## signature would look armed the first time a doctrine let it counter.
func test_unarmed_units_have_a_style_that_fires_nothing() -> void:
	var chart: DamageChart = load("res://data/damage_chart.tres")
	for type in units.all():
		var armed := false
		for other in units.all():
			if chart.can_attack(type.id, other.id):
				armed = true
				break
		assert_eq(
			styles.for_unit(type).fires(),
			armed,
			(
				"%s is %s but its style %s"
				% [
					type.id,
					"armed" if armed else "unarmed",
					"fires nothing" if armed else "fires something"
				]
			)
		)


## The fallback is the safety net BattleStyleDB's whole contract rests on, so it
## has to hold even with no files on disk at all.
func test_an_unknown_style_falls_back_to_unarmed_rather_than_null() -> void:
	var empty := BattleStyleDB.new()
	var style := empty.by_id(&"no_such_style")
	assert_not_null(style)
	assert_false(style.fires())
	assert_eq(style.muzzle, 0.0)
