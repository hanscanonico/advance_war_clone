# Commander balance

How commander balance is measured, what "balanced enough to ship" means, and the
rule for changing a number when it isn't. This is the committed record of the
readiness plan's **G4 — Balance Gate**; the generated CSV/JSON reports are not
committed (they live under `reports/`, which is gitignored).

## The two halves

Balance is **evidence, not one giant simulation**. Two instruments, and neither
replaces the other:

1. **Automated matrix (`tools/run_commander_balance.gd`).** Plays AI-vs-AI across
   every commander pairing on rotationally-symmetric boards with paired seeds. It
   catches outliers and, because it drives the same `AIController` and `Command`
   objects as play, rule disagreements — a planned command the rules reject, or a
   match that never resolves. It quantifies; it does not judge feel.
2. **Human test deck (manual).** Twelve informative pairings played with sides
   swapped — 24 structured sessions — scored on clarity, agency, identity, power
   timing, counterplay, and rematch appetite. This decides whether a matchup is
   legible and worth replaying. It cannot be automated and is not in this
   repository; it is run against a candidate build before campaign work resumes.

> **Do not balance to the AI leaderboard alone.** The AI is rule-based and can
> underuse terrain, timing, or a specialised economy effect. A commander outside
> the preferred win band is a **review trigger**, not an automatic numeric nerf.

## Running the automated matrix

```sh
make commander-balance                 # full batch — a release task, ~1,728 matches
make commander-balance BAL="--commanders=alina_ward,cass_orlov --seeds=2"  # focused
```

Flags (after `--`): `--commanders=`, `--scenarios=`, `--seeds=`, `--neutral`
(adds each commander vs No Commander), `--days=`, `--out=`.

- **Full batch:** 12×12 ordered pairs (mirrors included) × 3 scenarios × 4 seeds
  = **1,728 matches**. Ordered pairs already side-swap every non-mirror matchup.
  It is deliberately out of `make verify`/`make test`.
- **Focused mode** is the fast iteration loop while tuning one commander.
- Output: `reports/commander_balance/matches.csv` (one row per match) and
  `summary.json` (per-commander win rates, first-side bias, threshold flags).

### The scenarios are fair by construction

All three boards are 180° rotationally symmetric with the teams swapped, and the
runner **asserts** that symmetry on startup (`_assert_symmetric`) — a typo that
broke fairness fails the run rather than biasing it. A first-side bias in the
results is therefore the doctrines' doing, not the map's. `clash` is open and
decisive; `ridge` puts more terrain between the lines; `combined` adds an
airfield, a port and a shared lake, because a doctrine tuned only against tanks
is tuned against a third of the game — several hooks read a unit's move class or
domain, and they behave differently when half the army is not on the ground.

A fixture also has to **resolve**. The first version of `combined` separated the
armies with water: it ground to the day cap in 430 of 432 matches and produced a
twenty-point first-side bias out of the tiebreak alone. The shipped version puts a
small lake in the middle instead, so the land armies walk past it and meet on day
one. Its measured first-side bias is 0.0 pp — the fairest of the three.

### Timed matches are decided on score

A rule-based AI rarely races to an enemy HQ, so most matches reach the day cap
undecided. Rather than discard that as a draw, a day-cap match is ranked the way
Advance Wars ranks a timed one — **properties, then surviving units, then
funds**. The CSV's `termination` column keeps natural wins (`rout`/`hq`)
distinguishable from scored ones (`day_cap`); a true tie (every measure equal, as
two identical doctrines in a mirror can produce) stays a draw.

### Determinism

Same scenario + seed + command sequence ⇒ **byte-identical** result rows on a
rerun. The RNG is seeded, the AI is lookahead-free and RNG-free, and the runner
reads neither the clock nor an unseeded RNG. This is what lets a tuning change be
attributed to the change and not to noise.

## Thresholds

| Measure | Band | Meaning |
|---|---|---|
| Per-commander side-normalized win rate | **45–55%** | preferred |
| Same | **40–60%** | automated warning — investigate before merge |
| First-side bias (non-mirror decisive games) | **≤ 5 pp** | map/seed fairness |
| Rejected AI commands, cap stalls | **0** | **hard** — the run fails |

Only the hard invariants fail the run (`exit 1`). Out-of-band win rates and side
bias colour the summary; they are review triggers, per the rule above.

## The one-variable tuning loop

When a commander sits outside the band **and** review confirms the anomaly is
real (repeat seeds, inspect side/map splits, verify the AI actually *uses* the
doctrine rather than merely possessing it), change **one** exported value in
`data/commanders/<id>.tres`, in this order of preference:

1. **Power cost first.** Changes how often the power fires while preserving its
   identity; narrowest blast radius.
2. **Then power magnitude / duration.** One value, then rerun the focused
   matchup subset, then the full batch.
3. **Passive doctrine last.** Always-on modifiers touch every turn and matchup;
   require human confirmation before altering them.

Behaviour stays in the `CommanderType` subclass; only numbers move. Record the
change and its rationale below.

## Status and results

The runner and its scenarios are in place and verified (symmetry asserted,
determinism byte-identical, hard invariants clean on focused runs). The **full
batch and the 24-session human deck are release tasks** to be run against the
candidate build; their results and any resulting `.tres` tuning are recorded here
when that pass happens.

### Measured while adding the air and naval domains (N4)

864 matches, `clash` + `ridge`, 3 seeds, run before and after the change so the
two are comparable. No commander `.tres` was touched: the point of the exercise
was to find out whether the new domains had moved the roster, and the answer is
that the AI's *production* moved it, in both directions.

| | base (`c6f103f`) | with air/naval |
|---|---|---|
| Win-rate spread | 25.0 – 77.1 % (52 pp, 6 WARN) | 31.2 – 68.8 % (38 pp, 4 WARN) |
| First-side bias | +5.6 pp | +14.9 pp |
| Rejected commands / cap stalls | 0 / 0 | 0 / 0 |

The spread **tightened**, which is the expected effect of an AI that fields a
mixed army instead of whatever one unit its priority list happens to favour: a
doctrine that answers tanks well has less to feed on.

The first-side bias **worsened**, and that is a real cost of `save_up_turns`.
Banking is what makes a 20 000 airframe or a 28 000 hull reachable at all — with
no banking the AI's treasury never passes about ten thousand and the expensive
half of the roster is not rare but *unbuyable* — and it hands whoever moves first
a timing edge, since they cross a price threshold a turn earlier. Measured at
+5.6 pp with no banking, +14.9 at a two-turn window, +20.2 at three. Two is
shipped: the air and naval soaks build their full rosters there, so three buys
nothing and costs another five points of first-move fairness.

Stated plainly, because it is easy to read the table above as a pass: **the
shipped configuration sits outside this document's own ≤ 5 pp first-side-bias
threshold**, roughly threefold, and the runner flags it REVIEW. That is a
deliberate accepted trade, not an oversight — without banking the expensive half
of the roster never reaches the board at all — and closing it belongs to the
base-game balance pass, alongside the out-of-band commanders, not to the air and
naval work. How much it bites depends strongly on the board: +14.9 pp is the
`clash` + `ridge` average, while the `combined` fixture measured +0.0 pp.

Everything above is the *base game's* balance seen through a better-playing AI.
The out-of-band commanders are the same names as before (Gideon Holt and Tomas
Reed high, Cass Orlov and Rhea Sol low), which makes them a base-game tuning pass
rather than anything the air and naval rosters introduced — and per the rule at
the top of this document, a review trigger rather than an automatic nerf.

### Balance changelog

- **2026-07-23 — every commander, `power_cost`, +2 000 across the roster**
  (8 000→10 000, 9 000→11 000, 10 000→12 000, 11 000→13 000, 12 000→14 000).
  Evidence: human play — powers were firing too often to stay an event. This is
  a global pacing shift, not a per-commander tune, so it moves one value per the
  ladder above while preserving the roster's cost ordering; the top tier now
  sits on the plan's 14 000 ceiling. The accrual split (100 % lost / 50 % dealt)
  is the plan's locked D2 and was not touched.
