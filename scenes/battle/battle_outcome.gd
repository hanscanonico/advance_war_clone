class_name BattleOutcome
extends RefCounted
## Owns how a match ends: the victory lockup, fronting it with the winning
## commander, and — for a `make balance-watch` run — the day cap that stops a
## watched replay and the one line the fidelity check diffs.
##
## Split out of Battle the same way BattleView, BattleAnimator, BattleAiRunner and
## BattleScenarioDriver were: it drives Battle's own state machine and scene nodes
## rather than deciding anything itself. The board decides who won; a watched match
## stopped by the day cap is scored on the harness's own tiebreak, not here. Battle
## holds one for the whole scene and calls `enter_victory`/`end_watch_on_day_cap`
## at the same points it used to call the private methods these were.
##
## Holds the scene like BattleAiRunner (it sets Battle.state and needs get_tree()),
## and is handed the victory screen's own nodes at build time like BattleAnimator's
## banner nodes — this reporter draws on them and nothing else does.

var _battle: Battle
var victory_screen: PanelContainer
var victory_portrait: TextureRect
var victory_faction_label: Label
var victory_label: Label
var victory_sub_label: Label
var rematch_button: Button

## True for a `make balance-watch` run: both sides are the computer's and the
## match came from a Balance Lab spec. Makes the scene announce its result and
## exit, which is what turns BS3's replay-fidelity check into a diff.
var _watching := false
## Watch mode's day cap, from `--days=`. Read **only** while `_watching`: normal
## play has no day limit and must not grow one, so a hot-seat or player-vs-AI
## match is untouched by this.
var _watch_days_cap := BalanceMatchEngine.DEFAULT_DAYS
## The team the victory lockup and the watch line report. `game.winner` for a
## match the board decided; a watched match stopped by the day cap is scored on
## BalanceMatchEngine.tiebreak instead — the harness's own authority, so the
## window and the CSV row agree — and that scored winner is not sim state.
var _result_winner := 0


func _init(battle: Battle) -> void:
	_battle = battle


## Watch mode's flags, from the setup. Set once at build; normal play leaves the
## defaults, which is why a hot-seat or player-versus-AI match never grows a cap.
func configure(watching: bool, days_cap: int) -> void:
	_watching = watching
	_watch_days_cap = days_cap


## Watch mode only (balance plan BS3), and true when it ended the match here. The
## harness plays while `day <= days_cap` and scores what is left on the board, so
## most of its rows terminate `day_cap`; without the same seam a watched replay of
## one would run forever and never print the line the fidelity check diffs. It is
## scored on the harness's own tiebreak and held beside the sim rather than
## written into `game.winner`, because the board did not decide this one. Gated on
## `_watching`: a hot-seat or player-versus-AI match has no day limit and must not
## grow one.
func end_watch_on_day_cap() -> bool:
	var game := _battle.game
	if not _watching or game.winner != 0 or game.day <= _watch_days_cap:
		return false
	_result_winner = BalanceMatchEngine.tiebreak(game)
	enter_victory()
	return true


## Idempotent: a rout resolved inside _begin_turn is seen again by whatever was
## driving that turn, and the match is only won once however many callers notice.
func enter_victory() -> void:
	if _battle.state == Battle.State.VICTORY:
		return
	_battle.state = Battle.State.VICTORY
	if _result_winner == 0:
		_result_winner = _battle.game.winner
	_battle.animator.hide_banner()
	Sfx.play(&"fanfare")
	victory_label.text = _result_text()
	victory_sub_label.text = "Day %d" % _battle.game.day
	_bind_victory_commander()
	victory_screen.show()
	victory_screen.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	rematch_button.grab_focus()
	if _watching:
		_report_watched_result()


## The winner lockup — "Verdant League wins!" — or "Draw" for the one case with
## no winner: a watched match that hit the day cap with every tiebreak level.
func _result_text() -> String:
	if _result_winner == 0:
		return "Draw"
	return "%s wins!" % _battle.view.identity.display_name(_result_winner)


## The one line BS3's replay-fidelity check reads: a watched match must end with
## the same winner on the same day as the matches.csv row it was launched from.
## Printed rather than asserted here, because the assertion belongs to whoever is
## comparing the two — and printing it is what lets that be a diff instead of
## someone watching a window and remembering.
##
## The wording is fixed, day-cap rows included: the row's `winner` and
## `day_ended` are what it is checked against, and a scored win is still that
## row's winner.
func _report_watched_result() -> void:
	print("watch: team %d wins on day %d" % [_result_winner, _battle.game.day])
	await _battle.get_tree().create_timer(1.5).timeout  # let the lockup land on screen
	_battle.get_tree().quit()


## Fronts the victory screen with the winning commander's portrait and faction. A
## side that played without one renders gracefully: the portrait and faction line
## simply hide, leaving the plain "<team> wins!" lockup — as does a draw, which
## has no winner to front at all.
func _bind_victory_commander() -> void:
	if _result_winner == 0:
		victory_portrait.visible = false
		victory_faction_label.visible = false
		return
	var winner := _battle.game.commander_of(_result_winner)
	var has_co := winner.id != CommanderType.NEUTRAL_ID
	victory_portrait.visible = has_co
	victory_faction_label.visible = has_co
	if has_co:
		victory_portrait.texture = CommanderVisuals.portrait_for(winner)
		var theme := CommanderVisuals.theme_for(winner)
		victory_faction_label.text = "%s · %s" % [winner.display_name, theme.display]
		victory_faction_label.add_theme_color_override("font_color", theme.color_light)
