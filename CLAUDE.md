# CLAUDE.md

Guidance for AI agents (and humans) working in this repository.

## Project

An **Advance Wars-style turn-based tactics game** built in **Godot 4.4+** with **GDScript**.
Grid maps, terrain that shapes movement and defense, a rock-paper-scissors unit roster,
property capture and income, and a computer opponent.

- **Status:** the design of record is `.lavish/advance-wars-clone-plan.html` — milestones M0–M7
  and which of them are done, mechanics reference, damage formula. Read it before making
  architectural decisions.
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
   base-damage matrix.
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
├─ core/        # sim: game_state.gd, commands/, rules/  (NO Node references)
├─ data/        # .tres resources: units/, terrain/, ai/, damage_chart
├─ scenes/
│  ├─ battle/   # battle.tscn, cursor, unit_sprite
│  ├─ menu/     # main_menu.tscn — map select, match options
│  ├─ common/   # helpers shared by both scenes
│  └─ ui/       # menus, panels, damage preview
├─ autoload/    # singletons: EventBus, MatchConfig, Sfx
├─ ai/          # ai_controller.gd — plans Commands; ai_profile.gd — its weights
│              (NO Node references)
├─ maps/        # map scenes / map resources
├─ assets/      # sprites, audio, fonts  (+ LICENSES.md)
└─ tests/       # GUT tests — target core/ and ai/ only
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
- **Test the pure-simulation layers exclusively** — `core/`, plus `ai/`, which is Node-free for
  exactly this reason. That's where the rules live and where bugs hurt. Movement range, path
  math, the combat resolver, capture points, turn/economy logic, and AI planning all get unit
  tests. Presentation is verified by playing the scene, not by unit tests.
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
  forward — the plan artifact tracks which milestones are done and what each one owes.
  Scope creep is the named top risk.
- **Balance numbers live in `data/`.** Don't hardcode stats you could put in a `.tres`.
- **Don't hand-edit** `.import` files or the binary/UID bits of `.tscn`/`.tres` unless you know
  exactly what you're doing — let Godot regenerate them. Do read `.tscn`/`.tres` to understand a
  scene, and prefer editing resource *data* over scene graph plumbing.
- **`project.godot`, autoloads, and the input map** are edited through the editor when practical;
  if editing by hand, keep changes minimal and reviewable.
- Keep the vision/fog boundary clean: `core/rules/vision.gd` is the single authority for "what can
  this player see?" — ask it, never re-derive visibility. Fog is enforced in the presentation layer
  (the sim stays permissive, the UI refuses to target or inspect what the viewer cannot see), and
  the AI deliberately sees everything **except** units a doctrine hides — it asks
  `Vision.is_hidden_from` for that one case, so an invisibility power is not inert against it.
  Terrain, range and property sight stay invisible to the AI's omniscience; don't widen the
  exception without a matching decision in the plan.

## Commits

- Small, focused commits scoped to one milestone task.
- Present-tense, imperative subject (`Add Dijkstra movement range`).
- Don't commit generated import caches or engine temp files (`.godot/` is ignored).
