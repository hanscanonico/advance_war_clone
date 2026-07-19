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

`make lint` and `make format` additionally need [gdtoolkit](https://github.com/Scony/godot-gdscript-toolkit)
(`pipx install "gdtoolkit==4.*"`). Everything else runs off the vendored engine alone.

Then:

```sh
make run             # boot the game — the main menu (map, fog, 1P / 2P / Continue)
make hotseat         # skip the menu: straight into a two-player hot-seat match (no AI)
make test            # run the GUT unit test suite (headless)
make check           # parse + type check every .gd file (fast; no scene tree)
make lint            # gdlint — style and smells (config: gdlintrc)
make format          # gdformat — reformat in place; format-check only reports
make tiles           # rebuild the art: generated ground tiles + PixVoxel units/buildings, then import
make sprites-check   # verify the atlas build inputs without writing anything
make sfx             # regenerate the placeholder sound effects (headless)
make import          # (re)import assets headless
make screenshot      # boot the battle scene, save screenshot.png, quit
make menu-screenshot # the same, for the main menu
```

Run a single scene directly: `bin/Godot.app/Contents/MacOS/Godot --path . scenes/battle/battle.tscn`.

Two maps ship: `first_steps` (the default) and `crossfire`. The main menu lists every map in
`maps/`, but command-line flags still override the menu so demos and tools can skip it:
`--map=crossfire`, `--hotseat`, and `--fog` — e.g.
`bin/Godot.app/Contents/MacOS/Godot --path . scenes/battle/battle.tscn -- --map=crossfire --fog`.

Any Godot 4.7+ works too — open the project folder in the editor.

## Main menu

The game boots to the menu: pick a map, toggle **Fog of war**, then start a **1 Player** match
against the Blue AI or a **2 Player** hot-seat game. **Continue** appears only when a save exists
and resumes it (with the save's own map, fog setting, and AI sides). **Quit** exits.

## Controls (M7)

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
- Confirm on one of your empty bases: the build menu lists units cheapest first, each row drawing
  the unit's artwork in your team's colours beside its name and cost; rows you can't afford are
  greyed out. A bought unit spawns exhausted and acts next turn
- Confirm on an empty tile: the map menu opens with **End Turn**, which hands play to the other
  team (the day counter advances when the rotation wraps back to Red), and **Save**, which writes
  the whole match — map, day, funds, ownership, every unit, and the RNG stream — over the single
  save slot. Resume it later with **Continue** on the main menu
- The HUD shows the current day, team, and funds; the corner panel shows the hovered tile's
  terrain, defense stars, move costs, owner (with `capture: N left` while a capture is in
  progress), and the unit standing there, if any — with its fuel, its ammo when the unit needs
  any, and `[+Infantry]` when it is carrying a passenger
- Taking the enemy HQ or destroying every enemy unit ends the match on a victory screen naming
  the winner and the day, with **Rematch** (same map, fog, and sides) and **Main Menu**

## Fog of war

Off by default; turn it on in the menu or with `--fog`. Fogged cells are darkened and the units
in them are hidden — you can neither target nor inspect an enemy you cannot see. You see through
your own units (each unit type has its own vision range) and out to two tiles around every
property you own. Woods only give themselves up from an adjacent tile, and units riding a
transport see nothing. Vision is recomputed after each committed action and turn change, not as
the cursor moves.

The view is always *your* team's, including while the AI plays. The AI itself sees the whole
board — an openly cheating opponent, not a guessing one. In a fogged hot-seat match a handoff
screen blanks the board between turns so the incoming player never sees the outgoing one's
vision.

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
- `scenes/` — presentation: main menu, battle scene, cursor, UI panels.
- `autoload/` — singletons: the event bus, the match setup the menu hands to the battle scene,
  and the sound-effect player.
- `tools/` — the art and sound build scripts: the headless ground-tile and sound generators, plus
  the PixVoxel atlas builder (see Assets below).
- `tests/` — GUT tests, targeting the pure-simulation layers (`core/` and `ai/`) only.
- `addons/gut/` — vendored [GUT](https://github.com/bitwes/Gut) 9.6.1 (MIT).

## Assets

Units and the city/base/hq buildings come from the CC0 [PixVoxel Revised Wargame
Sprites](https://opengameart.org/content/pixvoxel-revised-isometric-wargame-sprites); the ground
tiles are still generated programmer art. All sound is generated placeholder chiptune (`make sfx`).
There is no music yet — it needs licensed tracks. Third-party asset licenses must be tracked in
`assets/LICENSES.md`. No Nintendo assets or names may ever be used.

`make tiles` rebuilds the art in four ordered steps: `sprites-check` verifies the build inputs,
`ground` draws the terrain headless, `sprites` composites the PixVoxel art over it, and `import`
reimports the result — Godot caches image imports by size, so skipping the last step after a
rebuild that changes atlas dimensions renders a blank map. The check runs first because `ground`
is destructive: it replaces the committed building art with bare lots that only `sprites` can
finish painting, so a failure has to happen while the tree is still clean.

The only external requirement is ImageMagick 7 (`brew install imagemagick`). The 36 CC0 source
sprites are vendored under `assets/sprites/pixvoxel_src`, so a fresh clone rebuilds with no
download. To build from a full extracted pack instead, override the default:
`make tiles PIXVOXEL=/path/to/Revised_PixVoxel_Wargame/standing_frames`.
