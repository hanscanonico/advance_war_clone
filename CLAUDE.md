# CLAUDE.md

Guidance for AI agents (and humans) working in this repository.

## Project

An **Advance Wars-style turn-based tactics game** built in **Godot 4.4+** with **GDScript**.
Grid maps, terrain that shapes movement and defense, a rock-paper-scissors unit roster across
three movement domains (land, air, sea), property capture and income, and a computer opponent.

- **Status:** eight designs of record, all worth reading before an architectural decision.
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
├─ data/        # .tres resources: units/, terrain/, commanders/, ai/, difficulty/, damage_chart
├─ scenes/
│  ├─ battle/   # battle.tscn, cursor, unit_sprite
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
  exception without a matching decision in the plan. A submerged submarine is hidden through the
  same hook and is the one rule there that holds **with fog off** — being under the water is not a
  question of how far anyone can see.

## Commits

- Small, focused commits scoped to one milestone task.
- Present-tense, imperative subject (`Add Dijkstra movement range`).
- Don't commit generated import caches or engine temp files (`.godot/` is ignored).
