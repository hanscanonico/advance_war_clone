# Grid Commander (working title)

A turn-based tactics game in the style of Advance Wars, built with Godot 4.7 and
typed GDScript. See `.lavish/advance-wars-clone-plan.html` for the full implementation
plan (architecture, mechanics, milestones M0–M7).

## Running

The engine binary is vendored (gitignored) at `bin/Godot.app`. To set it up:

```sh
mkdir -p bin && curl -sL -o /tmp/godot.zip \
  https://github.com/godotengine/godot-builds/releases/download/4.7.1-stable/Godot_v4.7.1-stable_macos.universal.zip \
  && unzip -q /tmp/godot.zip -d bin/
```

Then:

```sh
make run          # play against the computer (Blue is the AI)
make hotseat      # play two-player hot-seat instead (no AI)
make test         # run the GUT unit test suite (headless)
make tiles        # regenerate the placeholder art — tiles, unit sprites, overlay (headless)
make import       # (re)import assets headless
make screenshot   # boot the game, save screenshot.png, quit
```

Run a single scene directly: `bin/Godot.app/Contents/MacOS/Godot --path . scenes/battle/battle.tscn`.

Two maps ship: `first_steps` (the default) and `crossfire`. Pick one on the command line with
`bin/Godot.app/Contents/MacOS/Godot --path . -- --map=crossfire`; an in-game map select arrives
with M7.

Any Godot 4.7+ works too — open the project folder in the editor.

## Controls (M6)

You play Red; Blue is the computer. Blue's turn plays itself — input is blocked while the AI
moves, attacks, captures, and builds, and the cursor follows each of its actions so you can
watch. `make hotseat` drops the AI and lets two players share the keyboard instead.

Either way, only the team whose day it is can act; a banner announces each turn and the cursor
jumps to that team's first property.

- Arrow keys / mouse hover: move the grid cursor
- Mouse wheel or `+` / `-`: zoom
- Confirm (`Enter` / `Space` / `Z`) or left-click on one of *your* units: select it and highlight
  its movement range; move the cursor within range to preview the path, then confirm a destination
  to move there. Remaining fuel caps that range, so a dry unit is stranded where it stands
- Cancel (`Esc` / `X` / `Backspace`): deselect, or undo an uncommitted move
- After a move, the action menu opens: **Fire** (offered only when an enemy is in weapon range
  from the destination and the unit still has ammo), **Capture** (offered when a capture-capable
  unit ends on a property you don't own), **Drop** and **Supply** (see transports below),
  **Wait** (commit the move), or **Cancel** (revert it)
- Choosing Fire enters targeting: attackable enemies get a red overlay and a panel previews the
  attack and counter damage; confirm on a target to resolve combat, or cancel back to the menu
- Confirming onto a reachable cell held by one of *your* units offers **Load** (board a transport
  with room) or **Join** (merge into a damaged unit of the same type, adding up HP, fuel, and
  ammo). Cancel snaps the mover back, as with any uncommitted move
- A loaded APC offers **Drop**, which enters a cell picker: the legal unload cells get the blue
  overlay, and confirming on one puts the passenger out there, exhausted for the turn. **Supply**
  refills every friendly unit standing next to the APC
- Moving spends fuel equal to the terrain cost of each step; attacking spends one ammo, and so
  does each counter-attack, so a dry unit can neither fire nor counter. At the start of your turn
  every unit standing on one of your properties or next to one of your APCs is refilled
- Confirm on one of your empty bases: the build menu lists units cheapest first; rows you can't
  afford are greyed out. A bought unit spawns exhausted and acts next turn
- Confirm on an empty tile: the map menu opens with **End Turn**, which hands play to the other
  team (the day counter advances when the rotation wraps back to Red)
- The HUD shows the current day, team, and funds; the corner panel shows the hovered tile's
  terrain, defense stars, move costs, owner (with `capture: N left` while a capture is in
  progress), and the unit standing there, if any — with its fuel, its ammo when the unit needs
  any, and `[+Infantry]` when it is carrying a passenger
- Taking the enemy HQ or destroying every enemy unit ends the match with a victory banner and
  no further input

## Architecture

- `core/` — pure simulation code. **Nothing here may reference a Node or a scene.**
  All rules are unit-testable and the AI simulates through the same code.
- `ai/` — the computer opponent (`AIController`). Also pure simulation: it plans one `Command`
  at a time, the exact same command objects player input produces, and the battle scene applies
  and animates them.
- `data/` — game data as `Resource` files (terrain, units, and the damage chart).
- `maps/` — plain-text maps: an ASCII terrain grid, a *starting* property-ownership section, and
  a starting-units section. `MapData` (core) is authoritative for terrain and is never mutated by
  play; runtime ownership, funds, and turn state live in `GameState`. The TileMapLayer is just paint.
- `scenes/` — presentation: battle scene, cursor, UI panels.
- `tools/` — headless scripts (placeholder art generator).
- `tests/` — GUT tests, targeting the pure-simulation layers (`core/` and `ai/`) only.
- `addons/gut/` — vendored [GUT](https://github.com/bitwes/Gut) 9.6.1 (MIT).

## Assets

All art is generated placeholder programmer art (`make tiles`), pending the free
asset pack pass planned in the art decision. Third-party asset licenses must be
tracked in `assets/LICENSES.md`. No Nintendo assets or names may ever be used.
