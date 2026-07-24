# CLAUDE.md

Guidance for AI agents (and humans) working in this repository.

## Project

An **Advance Wars-style turn-based tactics game** built in **Godot 4.4+** with **GDScript**.
Grid maps, terrain that shapes movement and defense, a rock-paper-scissors unit roster across
three movement domains (land, air, sea), property capture and income, and a computer opponent.

- **Status:** nine designs of record, all worth reading before an architectural decision.
  `.lavish/advance-wars-clone-plan.html` owns the base game — milestones M0–M7 and which of them
  are done, mechanics reference, damage formula. `.lavish/commanders-plan.html` owns Commanders
  and Command Powers — milestones C1–C4, the four locked decisions (D1 subclassed `CommanderType`,
  D2 asymmetric charge accrual, D3 what C1 ships, D4 Sable Wren's reworked Vanish) and the risk
  register R1–R6 that work was built against. `.lavish/difficulty-modes-plan.html` owns the
  difficulty tiers — milestones DF1–DF4 and the locked D2/D3: **the AI never cheats at any tier**,
  so difficulty may only change which `AIProfile` the planner weighs moves with, never income,
  vision, damage or luck. Its DF4 acceptance gate is currently **unmet** — read
  `docs/difficulty_check.md` before touching an AI weight or a tier `.tres`.
  `.lavish/naval-air-units-plan.html` owns the air and naval domains — milestones N1–N4, decisions
  D1–D6, and risks R1–R6, of which R1 is the standing one: the AI cannot plan a ferry, so it never
  builds transports and a naval map has to let fleets reach each other without one.
  `.lavish/map-retrofit-plan.html` owns which shipped boards carry a port or an airfield and which
  stay land-only on purpose, and it supersedes that plan's "the existing maps stay byte-identical"
  clause with the rule that replaced it: a map edit **converts** cells, never carves — land stays
  passable to every land class, no cell becomes sea and no coastline is redrawn — because a save
  stores its board by `map_path` and reloads the edited file from `res://`.
  `.lavish/production-maps-plan.html` owns the three production boards — `forge`, `arsenal`,
  `steelworks` — and its D1: **zero starting units is an omitted `[units]` section**, not a flag and
  not a parser change, which is why the trio shipped with no engine change at all. Its D3 keeps them
  land-only, deferring to the naval plan's standing R1.
  `.lavish/balance-simulator-plan.html` owns the offline balance instruments — milestones BS1–BS4,
  all shipped — and its D2: **the telemetry observes, it never instruments the sim.** Nothing under
  `core/` or `ai/` gained a signal, hook or field for it, so what the Lab measures is bit-for-bit
  what ships. Its D1 is the standing constraint on the toolchain: `tools/balance/match_engine.gd` is
  the one match loop, `make commander-balance` and `make difficulty-check` are byte-stable presets
  over it, and the merge bar for touching it is a fixed-seed byte-diff of both their reports — two
  committed documents rest on those numbers. `docs/balance_sim.md` is how to run and read it.
  `.lavish/game-speed-plan.html` owns the game-speed setting — milestones GS1–GS3 and the four
  locked decisions (D1 a device preference in `user://settings.cfg`, never `MatchConfig` and never
  a save, so a resumed match plays at the speed you like today; D2 the numbers as constants on the
  `GameSpeed` presentation class rather than a `.tres` under `data/`, deliberately breaking the
  difficulty tiers' symmetry; D3 Normal is the default at twice the movement duration, with Quick
  reproducing the old feel bit for bit; D4 Instant is an explicit branch, in the tradition of the
  animator's `capturing` flag, not an animation scale of zero). D2 exists to protect the standing
  invariant: **nothing under `core/` or `ai/` may import `GameSpeed` or read `Settings`**, which is
  what keeps pacing unable to move an outcome, a save or a replay. Its GS3 subjective retune is
  **not done** — the tier numbers are still the plan's starting values, characterized but not yet
  adjusted against a full match played at each tier by a human.
  `.lavish/faction-identity-plan.html` owns armies wearing their commander's faction — milestones
  FI1–FI3, all shipped — and its D1: **identity is presentation-only.** Nothing under `core/` or
  `ai/` learns a colour or a name; the sim keeps its team ints, and `scenes/common/side_identity.gd`
  (`SideIdentity`) resolves `team → {theme, display name, atlas row}` **once per match** from the
  commander picks, re-derived on load, never stored. It is the single authority every surface that
  once said "Red"/"Blue" now reads — the board, the day banner, the terrain panel, the winner line,
  the select chips, the info sheet — so ask it, never re-derive a side's colour or name. Its D3/D4
  fallbacks are load-bearing and total: a mirror match keeps the faction name and the later slot
  borrows the first hue-distinct classic (Aurora blue, else Meridian red); a commander-less side is
  "First/Second Army" in the classic red and blue, so a no-CO match is board-identical to before
  factions. The atlas-row order (`0 neutral, 1 meridian, 2 aurora, 3 iron, 4 verdant`) is a contract
  between `SideIdentity._ROW_FOR_KEY` and the art pipeline (`build_pixvoxel_atlases.sh` ROW_PALETTE,
  `generate_tiles.gd`); rows 0–2 are the shipped red/blue art byte-for-byte and must stay so. Its D5
  is the standing boundary: **"Red"/"Blue" survive only as developer slot vocabulary** — the Balance
  Lab's `--red`/`--blue` grammar and its byte-stable reports, code identifiers, comments — never on a
  screen a player sees; if a player can see it, it speaks faction.
  `.lavish/battle-animations-plan.html` owns the combat cut-in — milestones BA1–BA4, all shipped —
  and its D1: **the cut-in replays a snapshot, it computes nothing.** The only thing `core/` gained
  for it is `CombatResult.attacker_hp_before` / `defender_hp_before`, because the animation runs
  *after* the command applied and both units already hold post-combat HP. Its D5 is the standing
  rule on the other side of the line: how a weapon looks is a `BattleStyle` under
  `data/battle_anim/`, `UnitType.battle_style` is a presentation key exactly like `atlas_col`, and
  no gameplay number may ever appear in a style.
  `.lavish/capture-animation-plan.html` owns the capture cut-in — milestones CP1–CP3, all shipped —
  and it is the combat cut-in's sibling in every structural sense, sharing its D1: **the cut-in
  replays a snapshot, it computes nothing.** The only thing `core/` gained is a
  `CaptureCommand.result` snapshot (`points_before`, `points_after`, `owner_before`, `captured`),
  filled in `apply` exactly as `AttackCommand.result` is; the mash chips are a presentation split of
  `points_before − points_after`, never a call back into `capture_strength`. `BattleAnimator`
  gained one seam, `animate_capture`, behind the combat gate reused whole (`capturing`, Instant, and
  viewer visibility via the view and so `Vision` — one unit this time, since the capturer stands on
  the cell it takes), and the property flip is a `SideIdentity.atlas_row` swap so the cut-in's
  colours are the board's. It reads no `GameSpeed` accessor for its beat lengths — fixed constants
  on `CaptureCutscene` scaled by the animator's shared streak pacing, identical to the combat
  cut-in, deliberately not the plan's D5 tier-scaling, because the shipped combat sibling does not
  tier-scale and structural parity is the stronger rule. Its art prerequisite landed alongside: the
  hand-authored 64px airport and port buildings under `assets/sprites/iso_buildings`, composited
  into terrain-atlas columns 9–10 by `build_pixvoxel_atlases.sh` over the bare grounds
  `generate_tiles.gd` now draws for those cells (the PixVoxel pack has no hangar and no quay), with
  the iron/verdant rows derived by the same `tint_iso_air_sea.sh` recipe as the air/naval sprites —
  one tint authority for every hand-authored family. It deliberately retimes its handoff reference's
  4.6s choreography to ≈2.4s house tempo, because its R1 (ceremony fatigue — captures far outnumber
  kills) is the named top risk.
- **Engine:** Godot 4.4+ (`TileMapLayer`, custom `Resource` types).
- **Language:** GDScript, **typed everywhere** (`class_name`, typed vars, typed signatures).

> Legal: this is a *reimplementation of mechanics*, not a copy. No Nintendo sprites, music,
> unit-name trade dress, or the "Advance Wars" name. Use original or freely-licensed assets and
> a different title. Track every third-party license in `assets/LICENSES.md`.

## Architecture — the rules that matter most

1. **Simulation / presentation split.** The game state (map, units, funds, turn) lives in
   **pure GDScript classes with no `Node` dependency**. Scenes only render state and animate
   changes. This keeps rules unit-testable and lets the AI simulate moves cheaply.
   - **Nothing in `core/` may reference a `Node`, a scene, `get_node`, `SceneTree`, or anything
     under `scenes/`.** If you reach for a Node inside `core/`, you're in the wrong layer.
2. **Data-driven via Resources.** Unit stats, terrain properties, and the damage chart are
   `.tres` `Resource` files under `data/`, not constants in code. Balancing = editing data;
   adding a unit = adding a file. The damage chart is one resource holding the attacker × defender
   base-damage matrix. Commanders split the two: the doctrine is a `CommanderType` subclass in
   `core/commanders/`, every number it reads is `@export` on its `.tres` in `data/commanders/`.
3. **Command pattern for all actions.** Every player or AI action is a command object under
   `core/commands/` (`Move`, `Attack`, `Capture`, `Build`, `EndTurn`, …) that is *validated* then
   *applied* to the sim, which emits typed events the scene layer animates. This gives us undo of
   uncommitted moves, an AI that issues the same commands as the player, and a serializable log
   for save/replay.
4. **Determinism.** RNG (combat luck) is **seeded**. Same seed + same commands ⇒ same result.
   Never call global `randf()`/`randi()` in `core/`; thread a seeded RNG through the sim.

Flow: `input → Command → sim validates & applies → typed events → scenes animate`.
The AI plugs in at the exact same point as player input.

## Project layout

```
res://
├─ core/        # sim: game_state.gd, commands/, rules/, commanders/  (NO Node references)
├─ data/        # .tres resources: units/, terrain/, commanders/, ai/, difficulty/,
│              # battle_anim/ (weapon signatures), damage_chart
├─ scenes/
│  ├─ battle/   # battle.tscn, cursor, unit_sprite
│  │  └─ cutscene/  # the combat cut-in and the BattleStyle class it reads
│  ├─ menu/     # main_menu.tscn — map and commander select, match options
│  ├─ common/   # helpers shared by both scenes
│  └─ ui/       # menus, panels, damage preview
├─ autoload/    # singletons: EventBus, MatchConfig, Settings, Sfx
├─ ai/          # ai_controller.gd — plans Commands; ai_profile.gd — its weights
│              (NO Node references)
├─ maps/        # map scenes / map resources
├─ assets/      # sprites, audio, fonts  (+ LICENSES.md)
└─ tests/       # GUT tests — target the Node-free layers only (see Testing)
```

## GDScript conventions

Follow the official Godot GDScript style guide. Key points:

- **Indentation: tabs**, not spaces (Godot standard).
- **Typed GDScript everywhere.** `var hp: int = 10`, `func attack(target: Unit) -> void:`.
  Prefer explicit types over inferred `:=` when it aids readability.
- **Naming:** `snake_case` for files, variables, and functions; `PascalCase` for `class_name`
  and node names; `CONSTANT_CASE` for constants and enum values.
- **One `class_name` per file**, matching the file name (`game_state.gd` → `class_name GameState`).
- **Private** members and methods are prefixed with `_` (`_recalculate_range()`).
- **Signals** are named in past tense (`unit_moved`, `unit_damaged`, `turn_ended`) and declared
  with typed parameters. Emit domain events from the sim; the presentation layer subscribes.
- Prefer **composition and small resolvers** (`MovementResolver`, `CombatResolver`, `CaptureRules`)
  over god-objects.
- Use `@export` for inspector-editable fields on Resources/Nodes; validate in code, don't trust it.
- Don't `preload`/`load` scene or Node types inside `core/`.

## Testing

- Tests use **GUT** (Godot Unit Test) and live in `tests/`, mirroring `core/` and `ai/`.
- **Test the pure-simulation layers exclusively** — `core/`, plus `ai/` and the offline balance
  harness in `tools/balance/`, all of which are Node-free for exactly this reason. That's where the
  rules live and where bugs hurt. Movement range, path math, the combat resolver, capture points,
  turn/economy logic, AI planning, and the balance engine's determinism and telemetry attribution
  all get unit tests. Presentation is verified by playing the scene, not by unit tests — which is
  why watch mode announces its winner and day: it makes a presentation-layer claim (the watched
  match *is* the harness's match) checkable by diffing two lines instead of watching a window.
- Every bugfix in `core/` or `ai/` should come with a failing test that the fix makes pass.
- Keep tests deterministic: seed the RNG explicitly.

Run the suite with `make test` — it runs GUT headless against `tests/unit` via `.gutconfig.json`.
See README.md for engine setup and the other `make` targets.

## Running the game

Play with `make run` (boots the main menu); `make screenshot` boots the battle scene directly,
saves `screenshot.png`, and quits. See README.md for engine setup and the other `make` targets.

Prefer the running game (or a GUT test) over reasoning alone when verifying a change.

## Working in this repo

- **Match the plan's milestones.** Ship something playable each milestone; don't pull scope
  forward — the plan artifacts track which milestones are done and what each one owes.
  Scope creep is the named top risk.
- **Balance numbers live in `data/`.** Don't hardcode stats you could put in a `.tres`.
- **Don't hand-edit** `.import` files or the binary/UID bits of `.tscn`/`.tres` unless you know
  exactly what you're doing — let Godot regenerate them. Do read `.tscn`/`.tres` to understand a
  scene, and prefer editing resource *data* over scene graph plumbing.
- **`project.godot`, autoloads, and the input map** are edited through the editor when practical;
  if editing by hand, keep changes minimal and reviewable.
- **Doctrine hooks take an `Engagement`, not two `Unit`s.** `core/rules/engagement.gd` carries the
  effective values a shot is resolved with: the cell it is *actually* fired from and the HP the
  formula should use. A forecast fires from a cell the attacker has not moved to yet, and a
  forecast's counter uses projected post-attack HP — handing hooks the effective values is what
  keeps the damage preview and the resolved attack on identical numbers. The *defender's* cell is
  an effective value for the same reason: `CombatResolver.forecast_at` takes the cell to score the
  shot against, so the AI can ask "how hard am I hit if I stop here?" without standing a live unit
  somewhere to ask it. Forecasting is a pure read — if a query has to mutate the board, it is wrong.
- Two more single authorities, same rule as vision below — ask them, never re-derive:
  `core/rules/attack_range.gd` owns **who** a unit may shoot and **how far** — `can_engage` and
  `covers` — and `core/movement_resolver.gd` owns the movement budget and per-step terrain cost,
  **including inside `MoveCommand.validate`**. That last one is load-bearing: a fourth independent
  opinion on movement was a real bug here, and it made the range overlay offer cells the command
  then refused. `can_engage` exists for the same reason: the command, the planner and the targeting
  overlay each used to ask the damage chart directly, which was the whole answer only until a
  submarine could be under the water. Countering is the one deliberate exception on distance,
  documented on `CombatResolver._defender_can_counter`; it asks `can_engage` for the rest.
- **Movement domains are data, not code.** A move class is a key in each terrain's `move_costs`
  (`air` on every terrain, `ship`/`lander` on the water), which is the entire reason aircraft and
  hulls needed no change to `MovementResolver`. Which property builds and refits what is likewise
  `TerrainType.builds` / `services`, read by `BuildCommand`, the build menu and the AI's production
  alike — never a terrain id checked in three places, which is what those two lists replaced.
- Keep the vision/fog boundary clean: `core/rules/vision.gd` is the single authority for "what can
  this player see?" — ask it, never re-derive visibility. Fog is enforced in the presentation layer
  (the sim stays permissive, the UI refuses to target or inspect what the viewer cannot see), and
  the AI deliberately sees everything **except** units a doctrine hides — it asks
  `Vision.is_hidden_from` for that one case, so an invisibility power is not inert against it.
  Terrain, range and property sight stay invisible to the AI's omniscience; don't widen the
  exception without a matching decision in the plan. The one widening made with such a decision is
  **movement-obstacle detection**: a committed path is planned and walked with the mover's *own*
  visibility, so a unit hidden from the AI (a fogged enemy, or a dived sub it is not next to) can
  spring an ambush on its move exactly as one can on a human's — only the AI's *pathing* is
  fog-limited, its *targeting* stays omniscient-except-doctrine-hidden. A submerged submarine is
  hidden through the same hook and is the one rule there that holds **with fog off** — being under
  the water is not a question of how far anyone can see.
- **The battle cut-in replays; it never decides.** `BattleAnimator.animate_combat` is the one seam —
  both call sites `await` it, and it either plays the full-screen cut-in or falls through to the
  on-map hit, returning exactly once either way. Inside `scenes/battle/cutscene/`, everything is a
  pure function of one clock: skipping sets that clock to the end rather than cancelling tweens,
  which is what makes "any press, at any beat, lands on the right board" true by construction
  instead of by testing. Every number the cut-in shows was handed to it — the result's two HP
  snapshots and the units themselves — and none is recomputed from the damage chart or the RNG.
  Keep it that way: a second opinion on combat is the movement bug this repo already paid for once.
  Two consequences worth knowing before touching it. It is suppressed while `capturing`, like the
  shake and the pulse, so `make screenshot` stays byte-stable and a posed cut-in goes through
  `pose_at` instead; and it only plays when the *viewer* can see both combatants, which is asked of
  the view (and so of `Vision`), never re-derived.

## Commits

- Small, focused commits scoped to one milestone task.
- Present-tense, imperative subject (`Add Dijkstra movement range`).
- Don't commit generated import caches or engine temp files (`.godot/` is ignored).
