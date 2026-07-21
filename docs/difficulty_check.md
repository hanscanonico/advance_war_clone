# Difficulty tiers and the ladder gate

How the three difficulty tiers are built, how their ordering is measured, and
what the measurement currently says. This is the committed record of the
difficulty plan's **DF4 — Prove the ordering, then tune**; the generated
CSV/JSON reports are not committed (they live under `reports/`, gitignored).

**Standing verdict: the gate does not pass.** Easy is clearly weaker than Normal
where the instrument can see it; **Difficult is not measurably stronger than
Normal at all**. Details and the reasoning below — read §4 before changing a
weight, and §5 before deciding what to do about it.

**The recorded numbers are also out of date.** They were measured before
`advance_threat_tiles` split off from `threat_aversion` (§2), which is what makes
Difficult's kill-zone refusal do anything at all on the advance path. Both tiers
plan differently now, so `make difficulty-check` must be re-run and its output
committed over §4 before the standings are quoted again.

## 1. What difficulty is allowed to change

Exactly one thing: **which `AIProfile` the computer plans with**.

The AI never cheats at any tier. No income multiplier, no damage multiplier, no
extra vision, no friendlier dice — in either direction, so the player is not
secretly boosted on Easy any more than the AI is on Difficult (plan D2/D3). The
simulation is not touched by this feature at all: `GameState`, the combat
resolver, the damage chart and the fog boundary are identical at every tier, and
a test asserts a tier resource carries nothing but an id, a label and a profile.

That constraint is the whole reason this document exists. With no handicap to
fall back on, the *only* evidence that "Difficult" means anything is that it
wins more games — which is what the gate measures.

| Tier | id | Profile | Character |
|---|---|---|---|
| Easy | `easy` | `data/ai/easy.tres` | Timid: over-weights danger, retreats early, refuses trades, over-buys infantry, no md tank |
| Normal | `normal` | `data/ai/default.tres` | The shipped AI, bit for bit |
| Difficult | `hard` | `data/ai/hard.tres` | Threat-aware and counter-building, sharper trade weights |

Each tier is a `Difficulty` resource in `data/difficulty/` — a label plus one of
those profiles. Retuning a tier is editing its `.tres`.

## 2. The three capabilities

Difficult's extra judgement is three `@export` weights on `AIProfile`, each
defaulting to `0.0`, which skips the capability entirely. At `0` the code that
reads it never runs, so **Normal plans exactly as the pre-difficulty AI did, on
the same RNG stream** — pinned by `test_capability_defaults_plan_exactly_like_the_shipped_profile`,
which compares a full AI turn command for command.

- **S1 threat awareness — two dials on one map.** Builds a per-turn `ThreatMap`
  (`ai/threat_map.gd`): for every visible enemy, its `MovementResolver` reach ×
  its `AttackRange` firing ring, and the damage a `CombatResolver.forecast`
  says it would do to the unit standing there. Reuses the single authorities and
  re-derives no rules; forecast is luck-free, so it draws no RNG and the replay
  guarantee holds. Cached once per turn, keyed on the day and the enemy set, so a
  new day always rebuilds it and a counter-kill mid-turn does too.

  The map is read by two weights, because the two paths that read it do not score
  in the same unit:

  - **`threat_aversion` — attacks, in value.** An attack's score is
    `cost × damage fraction`, so the firing cell's discount is
    `threat × unit cost × threat_aversion` in that same currency. Must stay
    small; see below.
  - **`advance_threat_tiles` — advances, in tiles.** A destination a unit is
    merely walking to scores as `-distance`, stepping by whole integers, so the
    penalty is `advance_threat_tiles × lethality` *tiles* of forward progress,
    where lethality is the forecast damage over the HP the unit has left — `1.0`
    means the shot kills it, so a hurt unit gives up more ground than a fresh one
    for the same incoming fire. Reusing the value-denominated dial here was a
    real defect: at
    Difficult's ladder-safe `0.1` the advance penalty maxes out at a hundredth of
    a tile and could only break ties, so the tier's headline "refuses a kill
    zone" never once cost it a step. Cost-scaling the advance term instead is not
    the fix — that is the R2 coward the 0.5 row below measures at 88% losses.
    The floor for a live value is ~1.6: below that a healthy unit cannot buy even
    one tile against a full-strength artillery shot (63 of its 100 points), i.e.
    it is inert where nothing is hurt yet.
    `data/ai/hard.tres` ships `2.0` and `easy.tres` `3.0` as **starting values —
    neither has been through the ladder.**
- **S2 `focus_fire_bonus` — focus fire.** Boosts a target other ready friendlies
  could still add damage to. **Ships at `0.0` — see §4.**
- **S3 `build_reactivity` — counter-building.** Re-ranks each affordable combat
  unit by its damage-chart effectiveness against the enemy's actual cost-weighted
  roster, blended over the static `build_priority` list. With no enemy in sight
  there is nothing to react to and the static list decides.

## 3. Running the gate

```sh
make difficulty-check                       # default: 4 seeds
make difficulty-check DIFF="--seeds=15"     # the standing result below
```

It is the same runner as the commander matrix in `--difficulty-check` mode, so a
match here resolves exactly as one in the battle scene. Adjacent tiers only
(Easy-vs-Normal, Normal-vs-Difficult), **no commanders on either side** so a
doctrine cannot colour a measurement of planning, on two committed maps that are
asserted 180°-rotationally symmetric before a match runs, **both seats played on
every seed** so a first-side advantage cancels.

- `scrimmage` (12×9) — the small decisive board.
- `ironworks` (24×16) — the large city-rich board.

**Gate:** the higher tier takes ≥ 70% of its pairing. Missing it means tuning the
`.tres` (or zeroing a misbehaving capability) — never loosening the number.
Rejected commands and cap stalls are hard failures on top: they would mean the
planner and the rules disagree.

## 4. What the measurement says

> **Every number in this section predates the `advance_threat_tiles` split
> described in §2, its rescaling against the HP a unit has left, and the
> threat-map lookup being hoisted out of the per-cell attack and advance
> loops.** It was measured against a build where Difficult's advance path could
> not give up a single tile for safety, and where Easy and Difficult rebuilt the
> visible-enemy list and its cache key once per candidate cell. Both tiers now
> plan differently, so **the ladder has to be re-run before any of the standings
> below mean anything again.** They are kept as the record of what was measured,
> not as a current claim. Nothing here has been re-scored by estimate —
> `make difficulty-check` is the only thing allowed to write these numbers.

**Standing result — 120 matches, 15 seeds, default 20-day cap:**

| Pairing | Overall | scrimmage | ironworks | Gate |
|---|---|---|---|---|
| Normal over Easy | **68.3%** (41/60) | 90.0% | 46.7% | fail (just) |
| Difficult over Normal | **50.0%** (30/60) | 53.3% | 46.7% | fail |

Zero rejected commands and zero cap stalls across all 120 — the planner and the
rules never disagreed, which is the correctness half of this run and it is clean.

### Two findings that matter more than the numbers

**(a) `ironworks` cannot tell the tiers apart — including Easy.** Normal beats
Easy 90% on `scrimmage` and 46.7% on `ironworks`. Easy is *known* to be the
weaker planner, so a board that scores it even with Normal is not measuring
planning strength there. On a 24×16 city-rich map inside a 20-day cap, both
sides sprawl and capture at similar rates and the day-cap tiebreak (properties,
then units, then funds) turns over on noise. Re-running at `--days=40` did not
help (Normal-over-Easy fell to 37.5% on that board), so the cap is not the cause.
**Half the gate is currently blind**, which means the Difficult verdict rests
mostly on the `scrimmage` column.

**(b) Difficult is not stronger.** Even on the discriminating board it is 53.3%.
Isolated single-capability probes on `scrimmage` (60 matches each, against the
shipped Normal profile; 50% is parity) were more encouraging than the shipped
combination turned out to be:

| Variant | Win % | Read |
|---|---|---|
| control (Normal vs Normal) | 50.0 | sanity check — the harness is unbiased |
| `threat_aversion` 0.02 / 0.05 / 0.10 | 56.7 / 53.3 / **58.3** | mild but real gain |
| `threat_aversion` 0.20 | 35.0 | already harmful |
| `threat_aversion` 0.50 | 11.7 | catastrophic — see below |
| `build_reactivity` 0.3 / 0.6 / 1.0 | 50.0 / 53.3 / **55.0** | mild gain |
| `kill_bonus` 1.8 + `counter_weight` 0.5 | 50.0 | neutral |
| `threat` 0.1 + `build` 1.0 | **61.7** | best combination found |
| `focus_fire_bonus` 0.2 / 0.5 / 1.0 | 43.3 / 41.7 / 43.3 | **negative** |

### Why `threat_aversion` must stay small

The penalty is scaled by the exposed unit's cost, and the threat total sums every
enemy that could reach the cell, so on a contested front it saturates at "this
unit dies". Above ~0.15 the discount exceeds the value of almost any attack, the
planner stops attacking, and it loses on time — 0.5 lost 88% of its games. This
is risk R2 (the coward) arriving exactly where the plan predicted.

That ceiling is exactly why the advance path needed `advance_threat_tiles` as a
second field rather than a second reading of this one. A weight low enough to
keep the AI attacking is, on a scale that steps by whole tiles, no weight at all.
Splitting them lets caution be real where a unit is only walking and stay cheap
where it is shooting; **the split is unmeasured** and both new values are
starting points.

The attack dial is also what makes **Easy** weak, turned the other way: Easy
ships `threat_aversion = 0.3` (and now the larger `advance_threat_tiles` of the
two tiers), so its timidity is mechanical rather than cosmetic. That is the
single biggest reason Normal beat it 90% on `scrimmage` in the run above.

### Why focus fire ships switched off

It measured negative in **both** shapes tried:

1. As an independent bonus scaled by follow-up damage (43.3% / 41.7% / 43.3%).
   This term can dwarf the shot's own value, so the AI chased whatever the team
   could gang up on and walked into bad trades to get there.
2. Reshaped as a *proportion of the shot's own value*, capped at doubling it
   (43.3% / 46.7% / 46.7% / 45.0%) — better, still below parity, and it dragged
   the best combination from 61.7% down to 46.7%.

The likely cause is double-counting: the planner already re-plans after every
applied command, so a wounded target's kill is visible to the next attacker for
free. Biasing the *first* shot toward a gang-up only pulls it off its own best
trade. The capability is kept, gated and unit-tested, and set to `0.0` —
"zero a misbehaving smart" is the plan's own remedy, and the ladder can re-test
it in one edit.

### Turn time (risk R3)

Mean AI planning per turn, measured during the standing run:

| Tier | ms/turn | over |
|---|---|---|
| Normal | 72.9 | 2310 turns |
| Difficult | 102.1 | 1160 turns |
| Easy | 144.3 | 1154 turns |

Well inside the budget: `BattleAiRunner` already waits 0.2 s between commands,
so none of this is perceptible in play. Easy was the slowest tier, not Difficult —
its high `min_useful_score` sends more units down the advance path, which
evaluates threat for every reachable cell, while Difficult's lower one usually
finds an attack first.

Most of that gap was avoidable and has since been closed: the advance loop and
the attack sweep both asked for the threat map once per *candidate cell*, and
each ask rebuilt the visible-enemy array and a formatted cache-key string only to
conclude the cached map was still valid. The lookup now happens once per sweep,
not once per cell. The table above was measured before that, so the two tier
costs should be re-read on the next run.

## 5. Where this leaves the feature

Everything the plan asked to be *built* is built, tested and shipping: the tier
plumbing, the menu picker, the save key, all three capabilities, and this gate.
What is not established is the claim the gate exists to prove.

Being straight about it: **shipping a "Difficult" that AI-vs-AI cannot separate
from Normal is a product decision, not a technical one.** It is mechanically
different — it refuses kill zones and counter-builds — and the plan itself notes
the soak proves ordering, not feel, so a human playtest is the missing evidence
either way. But nothing here yet justifies telling a player it is harder.

The candidates, in the order worth trying:

0. **Re-run the ladder.** The standings in §4 predate the `advance_threat_tiles`
   split, and Difficult's threat awareness was inert on the advance path when
   they were taken. Whatever is decided next, it should be decided on numbers
   that describe the planner as it is now.
1. **Fix the instrument first.** A gate whose large board cannot distinguish Easy
   from Normal cannot be trusted about Difficult. Either give `ironworks` a
   decisive win condition instead of a day-cap tiebreak, or replace it with a
   larger board that resolves. Doing this before more tuning avoids optimising
   against noise.
2. **The named reserve (plan §6/R1):** HQ defense and artillery screening. These
   were deliberately benched as follow-ups, not scope creep — they are the next
   thing to build if the ordering still will not appear.
3. **Human playtest at Easy and Difficult**, which the plan calls for regardless
   and which is the only read on whether Easy is timid-but-fun or just passive.

`make difficulty-check` exits non-zero while the gate is unmet. That is
deliberate: it is an opt-in release task, kept out of `make verify`, and a red
result is the honest status of the claim.
