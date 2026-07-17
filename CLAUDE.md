# CLAUDE.md

Guidance for AI agents (and humans) working in this repository.

## Project

An **Advance Wars-style turn-based tactics game** built in **Godot 4.4+** with **GDScript**.
Grid maps, terrain that shapes movement and defense, a rock-paper-scissors unit roster,
property capture and income, and eventually a computer opponent.

- **Status:** greenfield. The design of record is `.lavish/advance-wars-clone-plan.html`
  (milestones M0–M7, mechanics reference, damage formula). Read it before making
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
3. **Command pattern for all actions.** `Move`, `Attack`, `Capture`, `Build`, `EndTurn` are
   command objects that are *validated* then *applied* to the sim, which emits typed events the
   scene layer animates. This gives us undo of uncommitted moves, an AI that issues the same
   commands as the player, and a serializable log for save/replay.
4. **Determinism.** RNG (combat luck) is **seeded**. Same seed + same commands ⇒ same result.
   Never call global `randf()`/`randi()` in `core/`; thread a seeded RNG through the sim.

Flow: `input → Command → sim validates & applies → typed events → scenes animate`.
The AI plugs in at the exact same point as player input.

## Project layout

```
res://
├─ core/        # sim: game_state.gd, commands/, rules/  (NO Node references)
├─ data/        # .tres resources: units/, terrain/, damage_chart
├─ scenes/
│  ├─ battle/   # battle.tscn, cursor, unit_sprite
│  └─ ui/       # menus, panels, damage preview
├─ ai/          # ai_controller.gd, scoring
├─ maps/        # map scenes / map resources
├─ assets/      # sprites, audio, fonts  (+ LICENSES.md)
└─ tests/       # GUT tests — target core/ only
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

- Tests use **GUT** (Godot Unit Test) and live in `tests/`, mirroring `core/`.
- **Test `core/` exclusively** — the sim is where the rules live and where bugs hurt.
  Movement range, path math, the combat resolver, capture points, and turn/economy logic all
  get unit tests. Presentation is verified by playing the scene, not by unit tests.
- Every bugfix in `core/` should come with a failing test that the fix makes pass.
- Keep tests deterministic: seed the RNG explicitly.

Run tests headless:

```sh
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

(or `-gconfig=.gutconfig.json` once configured).

## Running the game

```sh
godot --path .            # open in the editor
godot --path . scenes/battle/battle.tscn   # run a specific scene
```

Prefer the running game (or a GUT test) over reasoning alone when verifying a change.

## Working in this repo

- **Match the plan's milestones.** Ship something playable each milestone; don't pull scope
  forward. The game is complete and fun at M4 (hot-seat); AI (M5) and depth/polish (M6–M7)
  come after. Scope creep is the named top risk.
- **Balance numbers live in `data/`.** Don't hardcode stats you could put in a `.tres`.
- **Don't hand-edit** `.import` files or the binary/UID bits of `.tscn`/`.tres` unless you know
  exactly what you're doing — let Godot regenerate them. Do read `.tscn`/`.tres` to understand a
  scene, and prefer editing resource *data* over scene graph plumbing.
- **`project.godot`, autoloads, and the input map** are edited through the editor when practical;
  if editing by hand, keep changes minimal and reviewable.
- Keep the vision/fog boundary clean: route "what can this player see?" through one Vision API
  that returns "everything" until fog is implemented (M7), so the retrofit is contained.

## Commits

- Small, focused commits scoped to one milestone task.
- Present-tense, imperative subject (`Add Dijkstra movement range`).
- Don't commit generated import caches or engine temp files (`.godot/` is ignored).
