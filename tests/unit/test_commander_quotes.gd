extends GutTest
## Every general that has a Command Power ships the spoken lines the activation
## banner reads (power-quotes plan PQ1), and every line fits the card.
##
## In scope for the same reason test_battle_styles.gd is: power_quotes is
## presentation data in the battle_style tradition — a display field on a
## Node-free Resource that no rule reads — and what is under test is data
## integrity, not how anything looks. The failure is quiet: the banner
## deliberately degrades to the quote-less card, which is the right behaviour
## in play and exactly the wrong behaviour to discover in play.

## The editorial ruler, not a rendering fact: the banner wraps at a fixed width,
## so what the cap really guards is each line staying a spoken beat rather than
## a paragraph. Raising it is a writing decision, not a fix.
const MAX_QUOTE_CHARS := 60

var commanders: CommanderDB


func before_each() -> void:
	commanders = CommanderDB.load_default()


func test_every_powered_general_has_quotes() -> void:
	var powered := 0
	for commander in commanders.all():
		if not commander.has_power():
			continue
		powered += 1
		assert_false(
			commander.power_quotes.is_empty(),
			"%s has a Command Power but no power_quotes to speak on the banner" % commander.id
		)
	assert_gt(powered, 0, "no powered commanders loaded, so this would pass vacuously")


func test_quotes_are_spoken_beats_not_paragraphs() -> void:
	for commander in commanders.all():
		for quote in commander.power_quotes:
			assert_false(
				quote.strip_edges().is_empty(), "%s ships an empty quote line" % commander.id
			)
			assert_true(
				quote.length() <= MAX_QUOTE_CHARS,
				(
					'%s quote is %d chars, over the %d cap: "%s"'
					% [commander.id, quote.length(), MAX_QUOTE_CHARS, quote]
				)
			)


## The neutral commander has no power to announce, so it must stay wordless —
## part of the guarantee that a no-CO match plays identically to before.
func test_neutral_commander_stays_silent() -> void:
	assert_true(CommanderType.neutral().power_quotes.is_empty())
