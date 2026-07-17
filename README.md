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
make run          # play
make test         # run the GUT unit test suite (headless)
make tiles        # regenerate the placeholder art — tiles, unit sprites, overlay (headless)
make import       # (re)import assets headless
make screenshot   # boot the game, save screenshot.png, quit
```

Any Godot 4.7+ works too — open the project folder in the editor.

## Controls (M2)

- Arrow keys / mouse hover: move the grid cursor
- Mouse wheel or `+` / `-`: zoom
- Confirm (`Enter` / `Space` / `Z`) or left-click on a unit: select it and highlight its
  movement range; move the cursor within range to preview the path, then confirm a destination
  to move there
- Cancel (`Esc` / `X` / `Backspace`): deselect, or undo an uncommitted move
- After a move, the Wait/Cancel menu commits the move (Wait) or reverts it (Cancel)
- The corner panel shows the hovered tile's terrain, defense stars, move costs, and the unit
  standing there, if any

## Architecture

- `core/` — pure simulation code. **Nothing here may reference a Node or a scene.**
  All rules are unit-testable and the future AI simulates through the same code.
- `data/` — game data as `Resource` files (terrain and units now; the damage chart at M3).
- `maps/` — plain-text maps: an ASCII terrain grid, a property-ownership section, and a
  starting-units section. `MapData` (core) is authoritative; the TileMapLayer is just paint.
- `scenes/` — presentation: battle scene, cursor, UI panels.
- `tools/` — headless scripts (placeholder art generator).
- `tests/` — GUT tests, targeting `core/` only.
- `addons/gut/` — vendored [GUT](https://github.com/bitwes/Gut) 9.6.1 (MIT).

## Assets

All art is generated placeholder programmer art (`make tiles`), pending the free
asset pack pass planned in the art decision. Third-party asset licenses must be
tracked in `assets/LICENSES.md`. No Nintendo assets or names may ever be used.
