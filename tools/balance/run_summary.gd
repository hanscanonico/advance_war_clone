class_name BalanceRunSummary
extends RefCounted
## Turns a Balance Lab run's raw rows into the judgement in summary.json: which
## swept value looks unbalanced, how much the first seat is worth on each board,
## and how much of either number to believe.
##
## It computes **nothing the CSVs do not already say** — every figure here is an
## aggregate of matches.csv and timeline.csv, which is what lets the HTML report
## be checked against the raw files by hand.
##
## Node-free, so GUT can drive it.

## The standing bands, identical to docs/commander_balance.md's, so a Balance Lab
## number is read against the same thresholds the committed record uses.
const BAND_PREFERRED := Vector2(45.0, 55.0)
const BAND_WARNING := Vector2(40.0, 60.0)
const MAX_SIDE_BIAS_PP := 5.0

## Below this share of endings resolved *on the board* (rout/hq), a swept value's
## win rate is flagged low-confidence: it was mostly settled by the day-cap
## tiebreak, which docs/difficulty_check.md finding (a) showed can turn over on
## noise and score the known-weaker side. Plan R2.
const MIN_RESOLVED_PCT := 50.0


static func build(
	config: Dictionary, matches: Array[Dictionary], timeline: Array[Dictionary]
) -> Dictionary:
	var totals := _totals(matches)
	var summary := {
		"run": config,
		"totals": totals,
		"bands":
		{
			"preferred": [BAND_PREFERRED.x, BAND_PREFERRED.y],
			"warning": [BAND_WARNING.x, BAND_WARNING.y],
			"max_side_bias_pp": MAX_SIDE_BIAS_PP,
			"min_resolved_pct": MIN_RESOLVED_PCT,
		},
		"values": _values(matches, timeline),
		"bias":
		{
			"overall": _bias_of(matches),
			"per_map": _bias_per_map(matches),
		},
	}
	summary["notes"] = _notes(summary)
	return summary


# --- totals ------------------------------------------------------------------


static func _totals(matches: Array[Dictionary]) -> Dictionary:
	var decisive := 0
	var draws := 0
	var rejected := 0
	var stalls := 0
	for row in matches:
		rejected += int(row["rejected"])
		stalls += int(row["cap_stall"])
		if int(row["winner"]) == 0:
			draws += 1
		else:
			decisive += 1
	return {
		"matches": matches.size(),
		"decisive": decisive,
		"draws": draws,
		"total_rejected": rejected,
		"total_cap_stalls": stalls,
		# The two hard invariants, inherited verbatim from the shipped runner: a
		# rejected command means the planner and the rules disagree, and a cap
		# stall means a match that will not resolve. Either fails the run.
		"invariants_clean": rejected == 0 and stalls == 0,
	}


# --- per swept value ---------------------------------------------------------


static func _values(matches: Array[Dictionary], timeline: Array[Dictionary]) -> Array:
	var order: Array[String] = []
	var buckets: Dictionary = {}
	for row in matches:
		var value: String = row["sweep_value"]
		if not buckets.has(value):
			buckets[value] = []
			order.append(value)
		buckets[value].append(row)
	var result: Array = []
	for value in order:
		result.append(_value_entry(value, buckets[value], timeline))
	result.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool: return a["win_rate"] < b["win_rate"]
	)
	return result


static func _value_entry(value: String, rows: Array, timeline: Array[Dictionary]) -> Dictionary:
	var wins := 0
	var draws := 0
	var mirror := true
	var naval := false
	var days := 0
	var terminations := {"rout": 0, "hq": 0, "day_cap": 0, "command_cap": 0}
	var subjects: Dictionary = {}  # match_id -> subject team
	for row: Dictionary in rows:
		wins += 1 if int(row["subject_won"]) == 1 else 0
		draws += 1 if int(row["winner"]) == 0 else 0
		days += int(row["day_ended"])
		terminations[row["termination"]] = int(terminations.get(row["termination"], 0)) + 1
		if not bool(row["mirror"]):
			mirror = false
		if bool(row["naval"]):
			naval = true
		subjects[row["match_id"]] = 1 if row["subject_side"] == "red" else 2
	var played := maxi(1, rows.size())
	var rate := 100.0 * float(wins) / float(played)
	# "Resolved" is a stricter word than "decisive" and deliberately so: a day-cap
	# game *has* a winner (it is scored on the tiebreak) and counts as decisive
	# everywhere else in this file, but it was not resolved on the board. That
	# distinction is the whole of R2, so the two never share a name.
	var resolved: int = terminations["rout"] + terminations["hq"]
	var resolved_pct := 100.0 * float(resolved) / float(played)
	return {
		"value": value,
		"matches": rows.size(),
		"wins": wins,
		"draws": draws,
		"win_rate": rate,
		# A mirror's win rate is the *first seat's*, not a balance reading — with
		# both sides identical there is nothing else it could measure. Flagging it
		# against the balance bands would mark every board WARN for being a
		# mirror, so it is labelled for what it is and the bias table below is
		# where that run's answer actually lives.
		"flag": "mirror" if mirror else band_flag(rate),
		"mirror": mirror,
		"naval_bounded": naval,
		"mean_day_ended": float(days) / float(played),
		"termination": terminations,
		"resolved_pct": resolved_pct,
		"confidence": "ok" if resolved_pct >= MIN_RESOLVED_PCT else "low",
		"economy": _economy(subjects, timeline),
	}


## What the swept value did with its money, read straight off the timeline: how
## much it spent, what that bought, and what it destroyed per 1 000 funds spent —
## the "is this doctrine efficient or just rich?" number.
##
## Kills and losses have to be read from **both** sides' rows, and getting that
## wrong is easy: a row records what happened during *that* side's turn, so a
## unit of mine shot down on the opponent's turn is in the opponent's `killed`,
## not in my `lost`. My `lost` holds only what died on my own turn — counter-fire
## and empty tanks. Summing one side's columns alone would therefore compare my
## kills against my counter-fire deaths, which is not an exchange ratio and reads
## as a wild number the moment a side never gets countered.
static func _economy(subjects: Dictionary, timeline: Array[Dictionary]) -> Dictionary:
	var spent := 0
	var built_value := 0
	var captures := 0
	var turns := 0
	var destroyed := 0
	var lost := 0
	for row in timeline:
		if not subjects.has(row["match_id"]):
			continue
		if int(subjects[row["match_id"]]) == int(row["team"]):
			turns += 1
			spent += int(row["spent"])
			built_value += int(row["built_value"])
			captures += int(row["captures"])
			destroyed += int(row["killed_value"])  # enemies I killed on my turn
			lost += int(row["lost_value"])  # my units that died on my turn
		else:
			destroyed += int(row["lost_value"])  # enemies that died attacking me
			lost += int(row["killed_value"])  # my units killed on their turn
	return {
		"turns": turns,
		"spent": spent,
		"built_value": built_value,
		"killed_value": destroyed,
		"lost_value": lost,
		"captures": captures,
		# Value destroyed per 1 000 funds spent. Spending nothing is 0 rather
		# than a division by zero.
		"killed_per_1000_spent": 1000.0 * float(destroyed) / maxf(1.0, float(spent)),
		# Destroyed over lost. -1 when nothing was lost at all: the ratio is
		# undefined there, and reporting a huge number instead would read as a
		# measurement rather than a missing denominator.
		"exchange_ratio": -1.0 if lost == 0 else float(destroyed) / float(lost),
	}


static func band_flag(rate: float) -> String:
	if rate < BAND_WARNING.x or rate > BAND_WARNING.y:
		return "WARN"
	if rate < BAND_PREFERRED.x or rate > BAND_PREFERRED.y:
		return "watch"
	return "ok"


# --- first-seat bias ---------------------------------------------------------


## Bias measured on decisive games only, and never on a mirror pairing's own
## win rate — a mirror is 50% by construction. What a mirror *does* measure is
## precisely this: with both sides identical, every red win above half is the
## seat talking.
static func _bias_of(rows: Array) -> Dictionary:
	var red := 0
	var blue := 0
	for row: Dictionary in rows:
		var winner := int(row["winner"])
		if winner == 1:
			red += 1
		elif winner == 2:
			blue += 1
	var decisive := red + blue
	var bias := 0.0
	if decisive > 0:
		bias = 100.0 * float(red - blue) / float(decisive)
	return {
		"decisive": decisive,
		"red_win_pct": 100.0 * float(red) / maxf(1.0, float(decisive)),
		"bias_pp": bias,
		"ok": absf(bias) <= MAX_SIDE_BIAS_PP,
	}


static func _bias_per_map(matches: Array[Dictionary]) -> Array:
	var order: Array[String] = []
	var buckets: Dictionary = {}
	var naval: Dictionary = {}
	for row in matches:
		var map: String = row["map"]
		if not buckets.has(map):
			buckets[map] = []
			order.append(map)
		buckets[map].append(row)
		naval[map] = bool(row["naval"])
	var result: Array = []
	for map in order:
		var entry := _bias_of(buckets[map])
		entry["map"] = map
		entry["matches"] = buckets[map].size()
		entry["naval_bounded"] = bool(naval[map])
		result.append(entry)
	return result


# --- reading rules -----------------------------------------------------------


## The caveats a reader must carry to the numbers above, emitted as data rather
## than left in a document nobody has open. Each is a *reading rule*, not a
## finding: none of them makes a row wrong, all of them change what it means.
static func _notes(summary: Dictionary) -> Array:
	var notes: Array = []
	var totals: Dictionary = summary["totals"]
	if not totals["invariants_clean"]:
		notes.append(
			(
				(
					"%d rejected command(s) and %d cap stall(s): the planner and"
					+ " the rules disagree, or a match would not resolve. Fix that"
					+ " before reading anything else here."
				)
				% [totals["total_rejected"], totals["total_cap_stalls"]]
			)
		)
	var total: int = summary["values"].size()
	var low: Array[String] = []
	var naval: Array[String] = []
	var mirrors := 0
	for entry: Dictionary in summary["values"]:
		if entry["confidence"] == "low":
			low.append(entry["value"])
		if entry["naval_bounded"]:
			naval.append(entry["value"])
		if entry["mirror"]:
			mirrors += 1
	if mirrors == total and total > 0:
		notes.append(
			(
				"Every matchup here is a mirror, so the win-rate column is the"
				+ " *first seat's* rate, not a balance reading. The answer this run"
				+ " is after is the bias table: with both sides identical, every"
				+ " point above 50% is the seat talking."
			)
		)
	if not low.is_empty():
		notes.append(
			(
				(
					"Low confidence — under %.0f%% of games resolved on the board"
					+ " (rout or HQ), so the rest were settled by the day-cap"
					+ " tiebreak, which can turn over on noise: %s. Probe with a"
					+ " longer --days= before believing the ordering."
				)
				% [MIN_RESOLVED_PCT, _listed(low, total)]
			)
		)
	if not naval.is_empty():
		notes.append(
			(
				(
					"AI-bounded (the board builds hulls): %s. The planner never"
					+ " plans a ferry, so a result here reflects what the AI can"
					+ " express on water, not what the board is worth to a human."
					+ " Documented reading rule, not a fix — see the naval plan's"
					+ " standing R1."
				)
				% _listed(naval, total)
			)
		)
	var bias: Dictionary = summary["bias"]["overall"]
	if not bias["ok"]:
		var tail := (
			"The win rates above are side-normalized and unaffected;"
			+ " the bias is its own finding."
		)
		if mirrors == total and total > 0:
			tail = "On a mirror run that *is* the finding — there is nothing else for it to be."
		notes.append(
			(
				"First-seat bias %+.1f pp exceeds the +-%.0f pp threshold. %s"
				% [bias["bias_pp"], MAX_SIDE_BIAS_PP, tail]
			)
		)
	return notes


## Formats a list of swept values for a note, collapsing "all of them" rather
## than reprinting the whole table inside a sentence.
static func _listed(values: Array[String], total: int) -> String:
	if total > 3 and values.size() == total:
		return "all %d swept values" % total
	return ", ".join(values)
