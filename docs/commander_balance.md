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
make commander-balance                 # full batch — a release task, ~1,152 matches
make commander-balance BAL="--commanders=alina_ward,cass_orlov --seeds=2"  # focused
```

Flags (after `--`): `--commanders=`, `--scenarios=`, `--seeds=`, `--neutral`
(adds each commander vs No Commander), `--days=`, `--out=`.

- **Full batch:** 12×12 ordered pairs (mirrors included) × 2 scenarios × 4 seeds
  = **1,152 matches**. Ordered pairs already side-swap every non-mirror matchup.
  It is deliberately out of `make verify`/`make test`.
- **Focused mode** is the fast iteration loop while tuning one commander.
- Output: `reports/commander_balance/matches.csv` (one row per match) and
  `summary.json` (per-commander win rates, first-side bias, threshold flags).

### The scenarios are fair by construction

Both boards are 180° rotationally symmetric with the teams swapped, and the
runner **asserts** that symmetry on startup (`_assert_symmetric`) — a typo that
broke fairness fails the run rather than biasing it. A first-side bias in the
results is therefore the doctrines' doing, not the map's. `clash` is open and
decisive; `ridge` puts more terrain between the lines.

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
1,152-match batch and the 24-session human deck are release tasks** to be run
against the candidate build; their results and any resulting `.tres` tuning are
recorded here when that pass happens.

### Balance changelog

_(none yet — the first tuning pass appends entries here: commander, the one value
changed, from → to, and the evidence that prompted it.)_
