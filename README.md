# Grid Commander (working title)

A turn-based tactics game in the style of Advance Wars, built with Godot 4.7 and
typed GDScript. Three plans ship with it: `.lavish/advance-wars-clone-plan.html` for the base
game (architecture, mechanics, milestones M0–M7), `.lavish/commanders-plan.html` for
Commanders and Command Powers (milestones C1–C4), and `.lavish/difficulty-modes-plan.html`
for the Easy/Normal/Difficult tiers (milestones DF1–DF4).

## Running

The engine binary is vendored (gitignored) at `bin/Godot.app`. To set it up:

```sh
mkdir -p bin && curl -sL -o /tmp/godot.zip \
  https://github.com/godotengine/godot-builds/releases/download/4.7.1-stable/Godot_v4.7.1-stable_macos.universal.zip \
  && unzip -q /tmp/godot.zip -d bin/
```

`make lint` and `make format` additionally need [gdtoolkit](https://github.com/Scony/godot-gdscript-toolkit)
(`pipx install "gdtoolkit==4.*"`). Everything else runs off the vendored engine alone.

Working in a `git worktree`? `bin/` is gitignored, so a new worktree has no engine and every
target fails with "Godot binary not found". Symlink the one you already have:
`ln -s /path/to/main/checkout/bin bin`.

Then:

```sh
make run             # boot the game — the menu (map, difficulty, commanders, fog, 1P / 2P / Continue)
make hotseat         # skip the menu: straight into a two-player hot-seat match (no AI)
make verify          # the merge gate: check + lint + format-check + test, in one command
make smoke           # drive the battle scene's demo scenarios; prove each still renders
make test            # run the GUT unit test suite (headless)
make check           # parse + type check every .gd file (fast; no scene tree)
make lint            # gdlint — style and smells (config: gdlintrc)
make format          # gdformat — reformat in place; format-check only reports
make tiles           # rebuild the art: generated ground tiles + PixVoxel units/buildings, then import
make unit-placeholders    # redraw the aircraft/fleet sprites the PixVoxel pack has no art for
make sprites-check   # verify the atlas build inputs without writing anything
make sfx             # regenerate the placeholder sound effects (headless)
make portraits       # regenerate the placeholder commander portraits + faction emblems
make import          # (re)import assets headless
make screenshot      # boot the battle scene, save screenshot.png, quit
make menu-screenshot # the same, for the main menu
make gallery-screenshot   # render all thirteen commander cards (the G1 gate)
make commander-balance    # offline AI-vs-AI balance matrix -> reports/ (a release task)
make difficulty-check     # AI-vs-AI difficulty ladder gate -> reports/ (a release task)
```

`make verify` is the one command to run before merging: it parse-checks, lints, checks formatting,
and runs the suite, cheapest step first. Every headless run ends with `ObjectDB instances were
leaked at exit` and `resources still in use` — that is the engine failing to tear down a *script*
reference cycle (`AttackCommand.validate()` referring to its sibling `MoveCommand` pins the core
script graph), reproducible in twelve lines with no GUT involved. No gameplay object leaks, so the
gate reads exit status and ignores it.

`make smoke` covers what unit tests deliberately do not: GUT is limited to the Node-free `core/`
and `ai/`, so the battle scene is verified by driving it. Each demo scenario runs the same handlers
a player's input reaches and must still produce a frame. It renders, so it needs a display — it is
a local gate, not a headless-CI one. Narrow it with `make smoke MODES="attack capture"`, and keep
the captures to look at with `SMOKE_KEEP=1 make smoke`.

A mode may carry a `+fog` suffix (`make smoke MODES="victory+fog"`) to rerun that scenario with fog
of war on. Fog is the only setting under which the scene hides units rather than just drawing them,
so two scenarios run both ways by default.

Run a single scene directly: `bin/Godot.app/Contents/MacOS/Godot --path . scenes/battle/battle.tscn`.

Seven maps ship. The main menu lists them smallest board first — `scrimmage`, `timberline`,
`riverline`, `isthmus`, `crossfire`, `first_steps`, `ironworks` — so it opens on `scrimmage`, the
quick match, and shows each one's size, property count and a one-line pitch as a tooltip.
Command-line flags still override the menu so demos and tools can skip it: `--map=crossfire`,
`--hotseat`, `--fog`, `--difficulty=hard`, and `--co=alina_ward,viktor_draeg` (red first, blue
second; either side may be left blank for no commander) — e.g.
`bin/Godot.app/Contents/MacOS/Godot --path . scenes/battle/battle.tscn -- --map=crossfire --fog`.

Adding a map is dropping a `.txt` in `maps/` — the menu auto-discovers it and `tests/unit/`
holds it to the playability invariants (one HQ and a base per side, reachable HQs, a claimed
`# symmetric` tag that actually mirrors) and plays an AI-vs-AI match on it. See the format at the
top of `core/map_data.gd`; the first comment line is the tooltip description.

Any Godot 4.7+ works too — open the project folder in the editor.

## Main menu

The game boots to the menu: pick a map and a **Difficulty**, toggle **Fog of war**, then start a
**1 Player** match against the Blue AI or a **2 Player** hot-seat game. Either opens the
**commander selection page**; **Continue** appears only when a save exists and skips selection,
resuming the save with its own map, fog setting, difficulty, commanders, and AI sides. **Quit**
exits.

On the selection page you edit **Red**, confirm, then edit **Blue**, confirm. Four faction tabs and
three peer portraits let you browse; one focused card shows the highlighted general's doctrine and
Command Power in full (no hover tooltips), and a deliberate **No Commander** plays the plain rules.
Mouse, keyboard, and controller all navigate it, and **Back** returns to the menu without discarding
the map or fog choice. Nothing is committed until both sides are locked.

In battle each side's commander gets a portrait HUD chip with a charge meter (charging / ready /
active), a faction-tinted activation card when a power fires, a both-sides reference sheet from the
map menu, and a portrait on the victory screen.

## Controls

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
  refills every friendly unit within the APC's supply reach — normally the adjacent tiles, further
  under a commander who says so
- Moving spends fuel equal to the terrain cost of each step, discounted by any doctrine that makes
  that step cheaper, so you are never billed more than the range overlay showed; attacking spends
  one ammo, and so does each counter-attack, so a dry unit can neither fire nor counter. At the
  start of your turn every unit standing on one of your properties or in reach of one of your APCs
  is refilled
- Confirm on one of your empty bases: the build menu lists units cheapest first, each row drawing
  the unit's artwork in your team's colours beside its name and cost; rows you can't afford are
  greyed out. A bought unit spawns exhausted and acts next turn
- Confirm on an empty tile: the map menu opens with **End Turn**, which hands play to the other
  team (the day counter advances when the rotation wraps back to Red), and **Save**, which writes
  the whole match — map, day, funds, ownership, every unit, both commanders, and the RNG stream —
  over the single save slot. Resume it later with **Continue** on the main menu. When your Command
  Power is charged the menu lists it first, so it is reachable from the keyboard as well as from
  the HUD button
- The HUD shows the current day, team, and funds — plus, for a side playing a commander, that
  side's charge meter and a **Power** button (see Commanders below); the corner panel leads with
  the unit on the hovered tile, if any: its sprite, name, army, `HP x/10`, fuel and ammo out of
  their maximums (no ammo row for units that need none), its range when it is an indirect,
  `Carrying …` when it is a loaded transport, and a `Waited` badge — dimming the card — once it
  has acted this turn. Below that sits a compact terrain card: the tile's artwork, name, defense
  stars, the move cost for the occupant's movement class (all four classes when the tile is
  empty), and the owner, with `capture: N left` while a capture is in progress
- Taking the enemy HQ or destroying every enemy unit ends the match on a victory screen naming
  the winner and the day, with **Rematch** (same map, fog, commanders, and sides) and **Main Menu**

## Commanders

Each side may field a general whose *doctrine* bends the rules for their whole army — attack and
defence, movement, vision, supply, capture — and who charges toward one **Command Power** that
bends them further for a turn.

Twelve ship, three to each of four factions (Meridian Coalition, Iron Dominion, Aurora Compact,
Verdant League). `data/commanders/` is the roster: one `.tres` per general, carrying their
doctrine line, power name and description, and every balance number. Read it — or the selection
page's card, which binds the same fields — rather than a list here, so the numbers have one home.

Picking **No Commander** on either side gives that side no doctrine, no meter and no power: a
match with neither plays exactly as the game did before commanders existed.

**Charging.** Both sides bank charge from HP destroyed, valued at the victim's cost prorated by
the damage — halving a 7 000 Tank is worth 3 500 points. The side that *loses* the HP banks all
of it; the side that dealt it banks half, so winning the field does not run away with the meter
as well. The meter is capped at what that general's power costs, so it never holds a second
power's worth.

**Firing.** When the meter fills, the HUD **Power** button lights up and the map menu (confirm on
an empty tile) lists the power as its first entry. Firing spends the whole cost and raises the
power immediately. Most powers last until you end that turn; a few — Hold the Line, Vanish,
Signal Jam — exist to bother the opponent and so survive their turn, ending as yours begins.

The AI charges and fires powers too, on its own commander's judgement of the right moment. Its
meter is shown while it plays, but the button stays disabled — it is not yours to press.

## Fog of war

Off by default; turn it on in the menu or with `--fog`. Fogged cells are darkened and the units
in them are hidden — you can neither target nor inspect an enemy you cannot see. You see through
your own units (each unit type has its own vision range) and out to two tiles around every
property you own. Woods only give themselves up from an adjacent tile, and units riding a
transport see nothing. A commander can bend all of that: lengthen their own units' sight, see
into woods at range, jam the enemy's sight shorter, or hide their units outright on a tile you
can otherwise see. Vision is recomputed after each committed action and turn change, not as the
cursor moves.

The view is always *your* team's, including while the AI plays. The AI itself sees the whole
board — an openly cheating opponent, not a guessing one — with one deliberate exception: a unit a
doctrine has hidden is hidden from it too, so an invisibility power is not inert against it.
In a fogged hot-seat match a handoff
screen blanks the board between turns so the incoming player never sees the outgoing one's
vision.

## Difficulty

Pick **Easy**, **Normal** or **Difficult** in the menu, or pass `--difficulty=easy|normal|hard`.
It steers exactly one thing: which `AIProfile` the computer plans with. **No tier is handed an
advantage** — income, dice, the damage formula, and what the AI is allowed to see (the standing
board-wide sight described under Fog of war) are identical at Easy and at Difficult, so a harder
opponent is only ever a better-judging one. It is inert in a 2-Player hot-seat, and a save
records the tier it was played at.

- **Easy** — timid. It over-weights danger, retreats early, refuses good trades, passes up
  marginal plays, and never fields an md tank. It loses on judgement, so beating it teaches the
  real game.
- **Normal** — the shipped AI, bit for bit. A test pins its profile to the planner's own defaults,
  so a same-seed replay of an old match still plays out identically.
- **Difficult** — the same economy and the same dice, with more on its mind. It builds a **threat
  map** each turn (what could shoot each cell next turn, forecast through the same combat resolver
  you see in the damage preview) and weighs it two ways: a shot is discounted by what the firing
  cell invites in return, scaled against the unit's own cost, and a unit that is only advancing
  will give up tiles of progress rather than end its move in a kill zone. It also **counter-builds**
  against your actual roster instead of a fixed shopping list. Whether all that actually *beats*
  Normal is unconfirmed — the AI-vs-AI ladder has not separated the two; `docs/difficulty_check.md`
  carries the standing numbers.

Each tier is a `.tres` under `data/difficulty/` pointing at a profile in `data/ai/`, so retuning
one is a data edit. `make difficulty-check` plays the tiers against each other headless and
reports whether the ladder actually orders — see `docs/difficulty_check.md` for the standing
result, including one capability that measured *negative* and ships switched off.

## Architecture

- `core/` — pure simulation code. **Nothing here may reference a Node or a scene.**
  All rules are unit-testable and the AI simulates through the same code.
- `ai/` — the computer opponent (`AIController`). Also pure simulation: it plans one `Command`
  at a time, the exact same command objects player input produces, and the battle scene applies
  and animates them.
- `data/` — game data as `Resource` files (terrain, units, the damage chart, the commander
  roster in `data/commanders/`, the AI profiles in `data/ai/` — every weight the opponent scores
  with, so tuning its behaviour is a data edit rather than a code change — and the difficulty
  tiers in `data/difficulty/`, each of which is just a label plus one of those profiles).
- `maps/` — plain-text maps: an ASCII terrain grid, a *starting* property-ownership section, and
  a starting-units section. `MapData` (core) is authoritative for terrain and is never mutated by
  play; runtime ownership, funds, and turn state live in `GameState`. The TileMapLayer is just paint.
- `scenes/` — presentation: main menu, battle scene, cursor, UI panels.
- `autoload/` — singletons: the event bus, the match setup the menu hands to the battle scene,
  and the sound-effect player.
- `tools/` — the art and sound build scripts: the headless ground-tile, sound, and portrait
  generators, plus the PixVoxel atlas builder (see Assets below); and the offline AI-vs-AI runner,
  which serves both the commander-balance matrix (`docs/commander_balance.md`) and the difficulty
  ladder gate (`docs/difficulty_check.md`).
- `tests/` — GUT tests, targeting the pure-simulation layers (`core/` and `ai/`) only.
- `addons/gut/` — vendored [GUT](https://github.com/bitwes/Gut) 9.6.1 (MIT).

## Assets

Ground units and the city/base/hq buildings come from the CC0 [PixVoxel Revised Wargame
Sprites](https://opengameart.org/content/pixvoxel-revised-isometric-wargame-sprites); the ground
tiles, the airport, and the aircraft are generated programmer art. The commander portraits and
faction emblems are generated placeholder art too (`make portraits`) — project-original, no
third-party pixels — until the final portrait pass. All sound is generated placeholder chiptune
(`make sfx`). There is no music yet — it needs licensed tracks. Third-party asset licenses must be
tracked in `assets/LICENSES.md`. No Nintendo assets or names may ever be used.

`make tiles` rebuilds the art in five ordered steps: `sprites-check` verifies the build inputs,
`ground` draws the terrain headless, `sprites` composites the PixVoxel art over it,
`unit-placeholders` draws the units that pack has no sprite for, and `import` reimports the result
— Godot caches image imports by size, so skipping the last step after a rebuild that changes atlas
dimensions renders a blank map. The check runs first because `ground` is destructive: it replaces
the committed building art with bare lots that only `sprites` can finish painting, so a failure has
to happen while the tree is still clean.

The pack has no aircraft and no ships, so those columns of the units atlas are flat 16px
silhouettes drawn by `tools/generate_unit_placeholders.gd` from ASCII grids in its own source — a
shape you can read and edit in place. They are deliberately placeholder, so that no milestone is
ever blocked on art; the step widens the atlas to whatever `data/units/*.tres` asks for and leaves
the PixVoxel columns untouched.

The only external requirement is ImageMagick 7 (`brew install imagemagick`). The 36 CC0 source
sprites are vendored under `assets/sprites/pixvoxel_src`, so a fresh clone rebuilds with no
download. To build from a full extracted pack instead, override the default:
`make tiles PIXVOXEL=/path/to/Revised_PixVoxel_Wargame/standing_frames`.
