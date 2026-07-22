# Balance Lab

Two independent AIs on any shipped board, each side carrying any commander at
any difficulty tier, over N seeded matches with both seats swapped — recording
not just who won but a turn-by-turn timeline of *how*. This is the committed
record of the balance-simulator plan's **BS1–BS4**.

It is an **instrument, not a gate**. Like `make commander-balance` and
`make difficulty-check` it stays out of `make verify` and `make test`; only its
own unit tests (`tests/unit/test_balance_engine.gd`,
`tests/unit/test_balance_recorder.gd`) are in the suite. Generated reports are
not committed — they live under `reports/`, which is gitignored.

## The three instruments

| Tool | Question it answers |
|---|---|
| `make commander-balance` | Is the commander roster balanced against itself? (`docs/commander_balance.md`) |
| `make difficulty-check` | Do the tiers actually order Easy < Normal < Difficult? (`docs/difficulty_check.md`) |
| **`make balance-sim`** | **Everything in between, plus *why*.** |

All three now run the same match loop — `tools/balance/match_engine.gd` — so a
number one reports means the same thing in the other two. The two above are
**presets** over it and keep their own CLIs, because two committed documents cite
their exact flags. The extraction's merge bar was a fixed-seed byte-diff of both
their reports before and after; see [Extraction](#the-extraction-plan-d1).

## Running it

```sh
# one matchup, full telemetry — "why does Gideon crush Cass here?"
make balance-sim SIM="--map=ironworks --red=gideon_holt:normal --blue=cass_orlov:normal --seeds=10"

# mixed tiers and doctrines — "is Difficult worth a commander handicap?"
make balance-sim SIM="--map=scrimmage --red=cass_orlov:hard --blue=gideon_holt:easy --seeds=15"

# sweep axis 1 — every commander (vs --blue) at one tier on one board
make balance-sim SIM="--map=the_straits --sweep=commanders --tier=normal --seeds=4"

# sweep axis 2 — map fairness: identical mirror on every shipped board
make balance-sim SIM="--sweep=maps --red=none:normal --blue=none:normal --seeds=6"

# sweep axis 3 — the tier ladder, with doctrines allowed on both sides
make balance-sim SIM="--sweep=tiers --map=scrimmage --commander=alina_ward --seeds=15"

# watch a match from the report live — same spec + seed = the same battle
make balance-watch SIM="--map=ironworks --red=gideon_holt:normal --blue=cass_orlov:normal --seed=1003"
```

### A side is `<commander>:<tier>`

Commander id or `none`; tier `easy`/`normal`/`hard`. Both halves are optional
(`gideon_holt`, `:hard`, or nothing) and default to `none:normal`. Ids are
checked against the databases, so a typo fails the run instead of quietly
measuring a neutral matchup.

**A tier is only which `AIProfile` plans that side's moves.** No income tilt, no
vision, no damage or luck differs at any tier, in either direction — the
difficulty plan's D2/D3 lock. Mixing tier and commander per side is new
*measurement*, not new mechanics.

### Flags

| Flag | Meaning |
|---|---|
| `--map=` | Any shipped board, or a balance fixture (`clash`, `ridge`, `combined`) |
| `--red=` / `--blue=` | Side specs; default `none:normal` |
| `--seeds=` | Paired seed count, default 4. Each seed plays **both seats** |
| `--seed=` | One specific seed instead — replays a single row |
| `--days=` | Day cap before a match is scored on points, default 20 |
| `--sweep=` | `commanders`, `maps` or `tiers` — one free axis per run |
| `--tier=` | The tier both sides play at, for `--sweep=commanders` |
| `--commander=` | The doctrine both sides carry, for `--sweep=tiers` |
| `--no-commands` | Skip `commands.jsonl`; a large sweep's is big |
| `--out=` | Output directory, default `reports/balance_sim/<run-name>` |

**One axis per run** (plan D5). Commanders × tiers × maps × seeds is a six-figure
matrix nobody reads; a run pins everything except one swept axis, so every batch
answers one question and finishes in minutes. Broad sweeps are a *sequence* of
runs, which the deterministic seeds make exactly reproducible and comparable.

The run directory is named after the spec, never a timestamp, so rerunning a
question overwrites its own directory and two runs of it are diffable file for
file. Every flag that changes the numbers is in that name — including `--seed=`
and `--days=`, so two seed replays of one matchup, or a 20- and a 25-day run of
it, land in directories of their own instead of overwriting each other.

## What it writes

| File | Grain |
|---|---|
| `matches.csv` | one row per match |
| `timeline.csv` | one row per side per **played turn**, keyed by `match_id` (plus the one edge case below) |
| `commands.jsonl` | one line per applied command (plan Q3) |
| `summary.json` | the aggregates, the flags and the reading rules |
| `report.html` | the same numbers drawn — open it off disk, no server |

### Reading the timeline

Filter one `match_id` in any spreadsheet and you watch the game: day 3 Blue banks
for a bomber, day 5 Red's army value collapses to a power spike, day 8 the
property lines cross.

| Column group | Columns | Detail |
|---|---|---|
| Key | `match_id · day · team · commander · tier` | Joins to `matches.csv` for map, seed, seats, outcome |
| Money | `funds_start · income · spent · funds_end` | See below |
| Production | `built · built_value` | `infantry x2;tank` and its summed cost |
| Combat | `killed · lost · killed_value · lost_value` | See attribution below |
| Board | `merged · unit_count · army_value · properties · captures` | End-of-turn strength; `army_value` = Σ cost × HP fraction, because a 2 HP tank isn't a tank |
| Powers | `power_charge · power_fired` | Meter percentage at turn end; whether the power went off |
| Cost | `commands · planning_ms` | Commands issued and AI planning time |

**A row covers everything from that side's start-of-turn tick to its own
`EndTurnCommand`**, so every event in the match lands in exactly one row. That
seam matters: a side's income, its paid repairs and any unit that dies with a dry
tank all happen inside the *previous* side's `EndTurnCommand`, and they belong to
the incoming side's row.

The one row that is *not* a played turn is that seam's own edge. A match can end
on the tick that opens a turn nobody then plays — the day cap falls, or the tick
strands a side's last aircraft and routs it. When that tick took a unit off the
board the row is filed anyway, with `commands = 0`: the death is real, the census
below has to see it, and it is worth reading in the timeline rather than only
balancing an equation. An otherwise empty final row is dropped.

**`income` is the whole start-of-turn tick** — property income less any repairs
paid on it — because that is what can be observed without re-deriving a rule the
sim owns. A commander economy hook would therefore show up here as a residual
rather than hide. Within the turn the only spend is production, so
`funds_start − spent = funds_end` closes exactly, and the run fails if it ever
doesn't.

**`planning_ms` is the one wall-clock column.** Everything else in a timeline row
is a pure function of (map, seed, side specs) and reproduces byte for byte; this
one measures how long the planner thought and cannot. The determinism test
compares rows with it excluded.

### Kill and loss attribution (plan D3)

A unit leaving the board is not always a death. Removals are classified by **the
command that caused them**, never by blindly diffing the board:

| Cause | Recorded as |
|---|---|
| `AttackCommand`, target dies | the acting side's `killed` |
| `AttackCommand`, attacker dies to counter-fire | the acting side's `lost` |
| `EndTurnCommand`, an empty tank at the start-of-turn tick | the owner's `lost` |
| `JoinCommand`, the mover merges into its twin | `merged` — neither a kill nor a loss |
| `LoadCommand`, a passenger boards | **nothing** — it never left `state.units` |

Anything else that removes a unit is *unattributed*, and unattributed removals
fail the run. Every match is also reconciled against its own final board:

```
started + built − lost − killed-by-the-enemy − merged  =  units on the board
```

A miscount is a red build, not a quiet lie in the data someone then tunes
against. Each case is pinned by a test in `tests/unit/test_balance_recorder.gd`.

## How to read the judgement

`summary.json` and the HTML report apply the same bands as
`docs/commander_balance.md`, so a Balance Lab number is read against the
committed thresholds:

| Measure | Band | Meaning |
|---|---|---|
| Side-normalized win rate per swept value | **45–55%** | preferred |
| Same | **40–60%** | warning — investigate before merge |
| First-seat bias (games with a winner) | **≤ 5 pp** | map/seed fairness |
| Rejected AI commands, cap stalls | **0** | **hard** — the run exits 1 |

Only the hard invariants fail the run. Out-of-band win rates are review triggers,
per the standing rule: **do not balance to the AI leaderboard alone.**

The summary also emits *reading rules* as data, so they travel with the numbers
instead of living in a document nobody has open:

- **Low confidence.** Under 50% of a value's games resolved on the board (`rout`
  or `hq`); the rest were settled by the day-cap tiebreak, which
  `docs/difficulty_check.md` finding (a) showed can turn over on noise and score
  the known-weaker side. Probe with a longer `--days=` before believing the
  ordering. *"Resolved" and "decisive" are deliberately different words here:* a
  day-cap game **has** a winner and counts as decisive, but it was not resolved
  on the board.
- **AI-bounded.** The board can build hulls (today: `isthmus`, `the_straits`).
  The AI never plans a ferry, so a result there reflects what the AI can express
  on water, not what the board is worth to a human. A documented reading rule,
  not a fix — fixing it is AI work owned by the naval plan's standing R1. The
  flag is derived from `TerrainType.builds`, not a map name, so a board that
  gains a port is annotated the day it does and only then.
- **Mirror.** With both sides identical, the win-rate column is the *first
  seat's* rate and not a balance reading — which is exactly what a mirror sweep
  is for. Its answer lives in the bias table. (Mirror matchups play one seat per
  seed rather than two, because swapping the seats of a mirror replays the
  identical match.)

## Watching a match (BS3)

Any spec the Lab can score it can also **show**. `make balance-watch` boots the
real battle scene, windowed, with both sides AI-driven and the match RNG pinned:

```sh
make balance-watch SIM="--map=clash --red=viktor_draeg:hard --blue=cass_orlov:easy --seed=1138"
```

Nothing is recorded or streamed from the harness — the scene simply runs the same
deterministic pipeline, animated at whatever game speed this device is set to
(README's *Game speed*; `--speed=instant` skips the theatre for one run and is
the quickest way to watch a long match out). That works because the AI
plans from state alone (lookahead-free, RNG-free) and only `CombatResolver` draws
from the seeded `state.rng`; `BattleAiRunner`'s pacing delays are pure
presentation and touch no sim state.

The scene prints `watch: team N wins on day D` and exits when the match ends, so
the fidelity check is a diff against the `matches.csv` row, not someone watching
a window and remembering.

**Watch mode honours `--days=` too** (default 20, the Lab's default). Most rows
terminate `day_cap` — a rule-based AI rarely races to an HQ — and those are
scored on the same `BalanceMatchEngine.tiebreak` the harness uses, so a capped
row can be watched to the same line as a decisive one. The cap is watch mode's
alone: a hot-seat or player-versus-AI match still runs until somebody wins.

One alignment detail rides along: the scene's per-turn command cap and the
harness's now come from one constant (`BalanceMatchEngine.MAX_COMMANDS_PER_TURN`),
so neither can cut a game the other would let run.

## The extraction (plan D1)

`tools/run_commander_balance.gd` kept its CLI and both committed gates; the
shared loop moved to `tools/balance/`. The merge bar was a fixed-seed byte-diff of
both reports before and after:

| Gate | `matches.csv` | `summary.json` |
|---|---|---|
| `make commander-balance BAL="--commanders=alina_ward,cass_orlov,gideon_holt --seeds=2"` | identical | identical |
| `make difficulty-check DIFF="--seeds=2 --days=12"` | identical | identical bar `turn_ms` |

`turn_ms` is mean planning wall-clock and was never reproducible run to run —
that is why `docs/difficulty_check.md` already reports it and never gates on it.

The three balance fixtures moved out of that file into `maps/fixtures/`, so the
Lab can name one with `--map=` and the battle scene can boot one for watch mode.
That directory is deliberately *not* `maps/` itself: `MapCatalog.paths()` scans
only the top level, so a fixture stays out of the menu, the map lint and the
per-map AI soak, while `MapCatalog.resolve()` — the single answer to "which board
is this name?" — finds both.

## Does the instrument agree with the committed record?

A first calibration run, 200 matches, every commander against No Commander at
Normal on `clash`, 8 seeds, 25-day cap:

```sh
make balance-sim SIM="--map=clash --sweep=commanders --tier=normal --seeds=8 --days=25"
```

| Commander | Lab win rate | `docs/commander_balance.md` |
|---|---|---|
| Gideon Holt | 87.5% (highest) | named high ✅ |
| Cass Orlov | 25.0% (lowest) | named low ✅ |
| Tomas Reed | 62.5% | named high — directionally agrees ✅ |
| Rhea Sol | 50.0% | named low — **does not reproduce here** ❌ |

Three of the four known outliers point the way the committed record says, and the
two extremes are the two names it calls out. Rhea Sol does not, and that is worth
stating rather than rounding off: **this is not the same measurement.** The
committed record is the full commander-versus-commander matrix over three
fixtures; this is each commander against *no commander* on one board. A doctrine
that is weak against other doctrines but fine against a neutral opponent will
read differently here, which is exactly the case a vs-neutral sweep cannot see.
Use `make commander-balance` for the roster-against-itself question; the Lab's
commander sweep answers the power-level-against-baseline one.

The run also measured **+14.0 pp first-seat bias on `clash` alone**, against the
+14.9 pp the committed record measured across `clash` + `ridge` — independent
corroboration of the standing base-game bias debt, which
`docs/commander_balance.md` accepted as a deliberate trade of `save_up_turns`.
Note the confidence column: at a 25-day cap most of these games still ended on
the day-cap tiebreak, so the *ordering* between adjacent rows is soft even where
the extremes are not.

## Runtime

Measured on the vendored Godot 4.7.1, headless, on an Apple-silicon laptop:

| Run | Matches | Wall clock |
|---|---|---|
| One matchup, 2 seeds, 12-day cap | 4 | ~2 s |
| Neutral mirror across all 12 boards, 3 seeds, 15-day cap | 36 | ~20 s |
| One matchup, 6 seeds, 25-day cap | 12 | ~11 s |

Matches are tens to hundreds of milliseconds each; telemetry is reads and
appends and does not measurably change that — and `planning_ms` lands in every
row, so if the recorder ever *did* get expensive it would be visible in its own
output. `commands.jsonl` is the one large artifact: budget roughly 170 bytes per
command, so a 1 700-match batch is over 100 MB. Pass `--no-commands` for sweeps
you do not intend to step through.
