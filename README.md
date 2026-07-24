# Grid Commander (working title)

A turn-based tactics game in the style of Advance Wars, built with Godot 4.7 and
typed GDScript. Nine designs of record ship with it under `.lavish/`; `CLAUDE.md` lists them and
which decisions each one owns.

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
make run             # boot the game — the menu (map, difficulty, speed, commanders, fog, 1P / 2P / Continue)
make hotseat         # skip the menu: straight into a two-player hot-seat match (no AI)
make verify          # the merge gate: check + lint + format-check + test, in one command
make smoke           # drive the battle scene's demo scenarios; prove each still renders
make test            # run the GUT unit test suite (headless)
make check           # parse + type check every .gd file (fast; no scene tree)
make lint            # gdlint — style and smells (config: gdlintrc)
make format          # gdformat — reformat in place; format-check only reports
make tiles           # rebuild the art: ground tiles, PixVoxel + iso air/sea units, placeholders, import
make unit-sprites    # re-paste the hand-authored iso air/sea sprites into the units atlas
make unit-placeholders    # redraw the placeholder sprites real art has not replaced (just Missiles)
make sprites-check   # verify the PixVoxel build inputs without writing anything
make unit-sprites-check   # verify the iso air/sea sources without writing anything
make sfx             # regenerate the placeholder sound effects (headless)
make portraits       # regenerate the placeholder commander portraits + faction emblems
make import          # (re)import assets headless
make screenshot      # boot the battle scene, save screenshot.png, quit
make menu-screenshot # the same, for the main menu
make gallery-screenshot   # render all thirteen commander cards (the G1 gate)
make commander-balance    # offline AI-vs-AI balance matrix -> reports/ (a release task)
make difficulty-check     # AI-vs-AI difficulty ladder gate -> reports/ (a release task)
make balance-sim          # the Balance Lab: any board, any commanders, any tiers, full telemetry
make balance-watch        # watch a Balance Lab match play out live, both sides AI
```

`make verify` is the one command to run before merging: it parse-checks, lints, checks formatting,
and runs the suite, cheapest step first. Every headless run ends with `ObjectDB instances were
leaked at exit` and `resources still in use` — that is the engine failing to tear down a *script*
reference cycle (`AttackCommand.validate()` referring to its sibling `MoveCommand` pins the core
script graph), reproducible in twelve lines with no GUT involved. No gameplay object leaks, so the
gate reads exit status and ignores it.

`make smoke` covers what unit tests deliberately do not: GUT is limited to the Node-free layers
(see Architecture below), so the battle scene is verified by driving it. Each demo scenario runs
the same handlers a player's input reaches and must still produce a frame. It renders, so it needs
a display — it is a local gate, not a headless-CI one. Narrow it with
`make smoke MODES="attack capture"`, and keep the captures to look at with `SMOKE_KEEP=1 make smoke`.

A mode may carry a `+fog` suffix (`make smoke MODES="victory+fog"`) to rerun that scenario with fog
of war on. Fog is the only setting under which the scene hides units rather than just drawing them,
so two scenarios run both ways by default.

The cut-ins — combat and its capture sibling — have their own family of modes, because they are
deliberately suppressed while capturing — a mid-animation frame is what would make two identical
captures differ. These pose the overlay at a fixed moment of its own clock instead, and the combat
modes carry the matchup in the name:

```sh
make smoke MODES="cutin"                      # the frontline tanks, defender survives
make smoke MODES="cutin_ko"                   # the same pair, defender routed
make smoke MODES="cutin:bomber:tank"          # any matchup, staged wherever it fits the board
make smoke MODES="cutin_skip"                 # walks a skip across every beat; must never hang
make smoke MODES="capture_cutin"              # a completing capture, late in its banner
make smoke MODES="capture_cutin_partial"      # an occupying capture, the property not yet flipped
make smoke MODES="capture_cutin_skip"         # the same skip walk over the capture cut-in
```

`cutin_skip` and `capture_cutin_skip` are the ones that are tests rather than pictures: each plays
the same cut-in ten times, skipping one frame later each time, and fails unless every run finishes
exactly once. Both call sites hold the whole interaction flow on that, so a cut-in that ever failed
to finish would freeze input for the rest of the session.

`--no-battle-anim` forces the cut-ins off for one run without touching the saved preference, which
is how "with the animation off, the match plays out identically" is checked against the offline
harness.

Run a single scene directly: `bin/Godot.app/Contents/MacOS/Godot --path . scenes/battle/battle.tscn`.

Twelve maps ship. The main menu lists them smallest board first — `scrimmage`, `forge`,
`timberline`, `arsenal`, `riverline`, `isthmus`, `jet_stream`, `crossfire`, `first_steps`,
`the_straits`, `ironworks`, `steelworks` — so it opens on `scrimmage`, the quick match, and shows
each one's size, property count and a one-line pitch as a tooltip. `jet_stream` and `the_straits`
are the boards air and naval units were added for: the first puts an airfield behind each front, the
second a port on each coast of one shared channel. Three of the older boards have since been
retrofitted with the domains that suit them — `isthmus` gained a port and a landing beach per side,
`ironworks` and `crossfire` an airfield each — while `first_steps`, `scrimmage`, `timberline` and
`riverline` deliberately stay land-only, because each is built on a barrier that wings or hulls
would simply erase.

`forge`, `arsenal` and `steelworks` are the production boards, and the only ones that hand out **no
starting units at all**: what you get instead is factories — two to four bases a side where the rest
of the roster tops out at two, an owned airport a side on the larger two, and neutral bases and
airports to expand production itself. The opening is a build order rather than a march, and
`steelworks` at 26×18 is the largest board in the game. An empty day 1 is legal without any rules
change: defeat is only ever checked when a unit dies, and the AI's planner already falls through to
production when it has nothing to move.

Command-line flags still override the menu so demos and tools can skip it: `--map=crossfire`,
`--hotseat`, `--fog`, `--difficulty=hard`, `--speed=slow`, and `--co=alina_ward,viktor_draeg` (red
first, blue second; either side may be left blank for no commander) — e.g.
`bin/Godot.app/Contents/MacOS/Godot --path . scenes/battle/battle.tscn -- --map=crossfire --fog`.

Adding a map is dropping a `.txt` in `maps/` — the menu auto-discovers it and `tests/unit/`
holds it to the playability invariants (one HQ and a base per side, reachable HQs, a claimed
`# symmetric` tag that actually mirrors) and plays an AI-vs-AI match on it. Boards that use the
water get four more: every port opens onto sailable sea, all of a map's ports share one body of it
(the AI cannot ferry, so a fleet it cannot sail to is a fleet it can never fight), every beach is
reachable by a lander, and no beach chain quietly joins two landmasses — a shoal costs every land
class exactly what road does, so a careless one is a bridge. See the format at the top of
`core/map_data.gd`; the first comment line is the tooltip description.

Any Godot 4.7+ works too — open the project folder in the editor.

## Main menu

The game boots to the menu: pick a map, a **Difficulty** and a **Speed**, toggle **Fog of war**
and **Battle animations** (the full-screen combat and capture cut-ins — a saved preference, on by
default),
then start a **1 Player** match against the AI or a **2 Player** hot-seat game. Either opens the
**commander selection page**; **Continue** skips selection and resumes the save with its own map,
fog setting, difficulty, commanders, and AI sides — it is greyed out (disabled, not hidden) when no
save exists. **Quit** exits.

On the selection page you pick **side 1**'s commander, confirm, then **side 2**'s, confirm — the
turn chips preview each side's faction name and colour as you browse, mirror rule included. Four
faction tabs and three peer portraits let you browse; one focused card shows the highlighted
general's doctrine and Command Power in full (no hover tooltips), and a deliberate **No Commander**
plays the plain rules.
Mouse, keyboard, and controller all navigate it, and **Back** returns to the menu without discarding
the map or fog choice. Nothing is committed until both sides are locked.

In battle each side's commander gets a portrait HUD chip with a charge meter (charging / ready /
active), a faction-tinted activation card when a power fires, a both-sides reference sheet from the
map menu, and a portrait on the victory screen.

## Controls

You play the first side; the computer plays the second. Its turn plays itself — input is blocked
while the AI moves, attacks, captures, and builds, and the cursor follows each of its actions so
you can watch. `make hotseat` drops the AI and lets two players share the keyboard instead.

Either way, only the team whose day it is can act; a banner announces each turn and the cursor
jumps to that team's first property.

- Arrow keys / mouse hover: move the grid cursor
- Mouse wheel or `+` / `-`: zoom
- Confirm (`Enter` / `Space` / `Z`) or left-click on one of *your* units: select it and highlight
  its movement range; move the cursor within range to preview the path, then confirm a destination
  to move there. Remaining fuel caps that range, so a dry unit is stranded where it stands
- Cancel (`Esc` / `X` / `Backspace`): deselect, or undo an uncommitted move
- Confirm or left-click on a unit you *cannot* command — an enemy, or one of yours that has
  already acted — previews where it could move, in the same blue overlay. Clicking another
  visible unit moves the preview there (a ready unit of your own still just selects), and cancel
  or a click on an empty tile dismisses it. It is a look, not an order, and fog applies: a unit
  you cannot see cannot be inspected
- `R`, while any unit's movement range is on screen — selected or previewed — toggles a red
  overlay of every cell that unit could bring under fire this turn: a direct unit firing from
  anywhere it could stop, an indirect only from where it stands, since it cannot move and shoot.
  It shows what the weapon *reaches* — a unit out of ammo still shows its ring, one resupply from
  meaning it — and it paints over the blue until pressed again
- After a move, the action menu opens: **Fire** (offered only when an enemy is in weapon range
  from the destination and the unit still has ammo), **Capture** (offered when a capture-capable
  unit ends on a property you don't own), **Drop** and **Supply** (see transports below),
  **Wait** (commit the move), or **Cancel** (revert it)
- Choosing Fire enters targeting: attackable enemies get a red overlay and a panel previews the
  attack and counter damage; confirm on a target to resolve combat, or cancel back to the menu
- Confirming onto a reachable cell held by one of *your* units offers **Load** (board a transport
  with room) or **Join** (merge into a damaged unit of the same type, adding up HP, fuel, and
  ammo). Cancel snaps the mover back, as with any uncommitted move
- A loaded transport offers **Drop** — one row per passenger with somewhere legal to step off, so
  a Lander carrying two shows a row naming each. Choosing one enters a cell picker: that
  passenger's legal unload cells get the blue overlay, and confirming on one puts it out there,
  exhausted for the turn. What a
  transport carries is its own: an APC or a T-Copter takes infantry, a Lander takes two of anything
  that drives — and unloads only onto a shoal or a port, since a landing craft cannot tip a tank
  over the side mid-channel. **Supply** refills every friendly unit within the APC's supply reach —
  normally the adjacent tiles, further under a commander who says so
- Moving spends fuel equal to the terrain cost of each step, discounted by any doctrine that makes
  that step cheaper, so you are never billed more than the range overlay showed; attacking spends
  one ammo, and so does each counter-attack, so a dry unit can neither fire nor counter. At the
  start of your turn every unit standing on a property that services it, or in reach of one of your
  APCs, is refilled — and a transport tops up every unit riding aboard it. Which property services
  what is the point: a city refits vehicles, an airport
  aircraft, a port hulls, and none of them does another's job
- A submarine adds one row of its own: **Dive** takes it under, **Surface** brings
  it back. Submerged, only a Cruiser or another Sub can engage it, and it is
  invisible to the other side unless one of their units is standing right next to
  it — with or without fog, since being under the water is not a question of how
  far anyone can see. It does not shoot back while hiding, and staying under costs
  it five times the fuel, so a dive is a decision rather than a default
- Aircraft and ships burn fuel simply by existing — a few points every turn, before anything
  refills them — and are **destroyed** when the tank runs dry. A warning badge appears on any unit
  inside its last turn's worth of fuel. Ground units have no upkeep: an empty tank strands them and
  nothing worse. That is what makes airfields and ports worth taking rather than decoration
- Confirm on one of your empty production properties — a base, an airport or a port: the build menu
  lists what *that* facility makes, cheapest first, each row drawing the unit's artwork in your
  team's colours beside its name and cost; rows you can't afford are greyed out. A bought unit
  spawns exhausted and acts next turn
- Confirm on an empty tile: the map menu opens with **End Turn**, which hands play to the other
  team (the day counter advances when the rotation wraps back to the first side), and **Save**, which writes
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
  stars, the move cost for the occupant's movement class (every class that can enter, when the
  tile is empty), and the owner, with `capture: N left` while a capture is in progress
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

**Colours and names.** A side wears its commander's faction: pick Verdant League and your army is
green and called *Verdant League* everywhere — the board, the day banner, the terrain panel, the
victory screen. When both sides pick the same faction, the first keeps the faction colour and the
second borrows a distinct one (Aurora blue, else Meridian red) while both keep the faction name;
the side number and commander tell them apart. A side with **No Commander** is *First*/*Second
Army* in the classic red and blue, so a commander-less match looks exactly as it always did.
("Red"/"Blue" survive only as developer slot names — the Balance Lab's `--red`/`--blue` flags and
its reports — never on a screen a player sees.)

Picking **No Commander** on either side gives that side no doctrine, no meter and no power: a
match with neither plays exactly as the game did before commanders existed.

**Charging.** Both sides bank charge from HP destroyed, valued at the victim's cost prorated by
the damage — halving a 7 000 Tank is worth 3 500 points. The side that *loses* the HP banks all
of it; the side that dealt it banks half, so winning the field does not run away with the meter
as well. The meter is capped at what that general's power costs, so it never holds a second
power's worth. And a side whose power is *running* banks nothing, dealt or lost, until it comes
down — every power is re-earned from empty, not refilled by the fighting it enables.

**Firing.** When the meter fills, the HUD **Power** button lights up and the map menu (confirm on
an empty tile) lists the power as its first entry. Firing spends the whole cost and raises the
power immediately. Most powers last until you end that turn; a few — Hold the Line, Vanish,
Signal Jam — exist to bother the opponent and so survive their turn, ending as yours begins.

The AI charges and fires powers too, on its own commander's judgement of the right moment. Its
meter is shown while it plays, but the button stays disabled — it is not yours to press.

**Quotes.** A power's activation card opens with the general speaking — a short in-character
line above the power's name, beside their portrait. The lines are data like everything else
about a general: `power_quotes` on their `.tres`, rotated in order across the match (never
randomly, so a replay speaks the same words), each capped at 60 characters so it stays a spoken
beat — `tests/unit/test_commander_quotes.gd` enforces both. The selection card shows the first
line as the general's signature. The AI's generals speak through the same banner.

## Fog of war

Off by default; turn it on in the menu or with `--fog`. Fogged cells are darkened and the units
in them are hidden — you can neither target nor inspect an enemy you cannot see. You see through
your own units (each unit type has its own vision range) and out to two tiles around every
property you own. Concealing terrain — woods, and reefs at sea — only gives itself up from an
adjacent tile, and units riding a transport see nothing. A commander can bend all of that:
lengthen their own units' sight, see into cover at range, jam the enemy's sight shorter, or hide
their units outright on a tile you can otherwise see. Vision is recomputed after each committed
action and turn change, not as the cursor moves.

A hidden enemy can also **ambush** a move: paths are planned with the mover's own vision, so a
committed move that runs onto or through an enemy you could not see stops your unit at the last
free cell short of it under an "Ambush!" banner — fuel is spent only for the steps actually
walked, and whatever the move was bound to (an attack, a capture, a drop) is called off.

A submerged submarine is the one thing hidden with fog switched off entirely —
see Dive above (it springs the same ambush). Everything else here needs fog to be on.

The view is always *your* team's, including while the AI plays — a computer move made entirely
inside your fog is applied silently, with no cursor, camera pan or footsteps to give it away. The
AI itself sees the whole board — an openly cheating opponent, not a guessing one — with two
deliberate exceptions: a unit a doctrine has hidden is hidden from it too, so an invisibility
power is not inert against it; and it plans and walks its moves with only its own vision, so a
unit it cannot see can ambush it exactly as one can ambush you.
In a fogged hot-seat match a handoff
screen blanks the board between turns so the incoming player never sees the outgoing one's
vision.

## Game speed

Pick **Slow**, **Normal**, **Quick** or **Instant** in the menu, or from the `Speed:` row on the
in-battle map menu (the one that opens on empty ground), which cycles through the four and takes
effect on the very next animation. It scales how fast moves and battles *play out on screen* and
nothing else: **no outcome, save, replay or seeded roll can change with it**, because no file under
`core/` or `ai/` is ever handed the setting.

- **Slow** — 0.18 s a tile; every step of a path is individually readable.
- **Normal** — 0.12 s a tile. The default.
- **Quick** — 0.06 s a tile, the pacing the game shipped with before the setting existed.
- **Instant** — no tweens. Units appear at their destinations, casualties vanish, sounds still fire,
  banners tighten to half a second, and the AI runs one command per frame so the board still
  repaints. For grinding out the late game.

It is a **device preference**, not match state: it lives in `user://settings.cfg` (beside the save's
`user://save.json`), never enters `MatchConfig` or a save file, and both sides of a hot-seat share
it. `--speed=<tier>` overrides it for one launch without writing anything, and outranks even the
tier captures pin themselves to — which is how you photograph a tier you are tuning. Every number
lives in one table at the top of `scenes/common/game_speed.gd`.

Battle captures and `make smoke` pin **Instant**: a frame must not depend on which machine took it,
and scenarios wait on the scene's state machine rather than a frame count, so skipping the theatre
cannot change what is photographed. It is also four times faster on the scenario that plays a whole
AI turn, for a byte-identical frame. `make menu-screenshot` pins **Normal** instead — the menu
animates nothing, so the pin's only effect there is the dropdown's text, and that should read as
the tier a fresh install ships with.

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
  an optional starting-units section. `MapData` (core) is authoritative for terrain and is never
  mutated by play; runtime ownership, funds, and turn state live in `GameState`. The TileMapLayer is just paint.
- `scenes/` — presentation: main menu, battle scene, cursor, UI panels.
- `autoload/` — singletons: the event bus, the match setup the menu hands to the battle scene,
  the device preferences this machine keeps between launches (`Settings` — the game speed above
  and whether battles play the full-screen cut-ins), and the sound-effect player.
- `tools/` — the art and sound build scripts: the headless ground-tile, unit-placeholder, sound,
  and portrait generators, the air/naval sprite paste step, plus the PixVoxel atlas builder (see
  Assets below); and the offline balance
  toolchain under `tools/balance/`, whose shared match engine serves the commander-balance matrix
  (`docs/commander_balance.md`), the difficulty ladder gate (`docs/difficulty_check.md`) and the
  Balance Lab (`docs/balance_sim.md`) alike.
- `tests/` — GUT tests, targeting the pure-simulation layers (`core/` and `ai/`) plus the Node-free
  offline balance harness under `tools/balance/`, which is written that way for exactly this reason.
- `addons/gut/` — vendored [GUT](https://github.com/bitwes/Gut) 9.6.1 (MIT).

## Assets

Ground units and the city/base/hq buildings come from the CC0 [PixVoxel Revised Wargame
Sprites](https://opengameart.org/content/pixvoxel-revised-isometric-wargame-sprites); the ground
tiles are generated programmer art. The aircraft and the fleet are original hand-authored isometric
sprites, vendored under `assets/sprites/iso_air_sea`, and the airport and port buildings are the
same class of art, vendored under `assets/sprites/iso_buildings`; only Missiles is still a
generated placeholder. The commander portraits and faction emblems are generated
placeholder art too (`make portraits`) — project-original, no third-party pixels — until the final
portrait pass. All sound is generated placeholder chiptune (`make sfx`). There is no music yet — it
needs licensed tracks. Third-party asset licenses must be tracked in `assets/LICENSES.md`. No
Nintendo assets or names may ever be used.

`make tiles` rebuilds the art in seven ordered steps: `sprites-check` and `unit-sprites-check`
verify the build inputs, `ground` draws the terrain headless, `sprites` composites the PixVoxel art
and the airport/port buildings over it, `unit-sprites` re-pastes the hand-authored air and naval
sprites, `unit-placeholders` draws the units still lacking real art, and `import` reimports the
result — Godot caches image imports by size, so skipping the last step after a rebuild that changes
atlas dimensions renders a blank map. The checks run first because `ground` is destructive: it replaces the committed building
art with bare grounds that only `sprites` can finish painting, so a failure has to happen while the
tree is still clean.

The pack has no aircraft and no ships. Those columns of the units atlas hold the original isometric
air and naval art, re-pasted from its vendored 64×64 sources by `tools/paste_unit_sprites.gd` on
every rebuild — except Missiles, still a flat 16px silhouette drawn by
`tools/generate_unit_placeholders.gd` from an ASCII grid in its own source, deliberately
placeholder so that no milestone is ever blocked on art. Both steps widen the atlas to whatever
`data/units/*.tres` asks for and leave the PixVoxel columns untouched.

The only external requirement is ImageMagick 7 (`brew install imagemagick`). The 36 CC0 source
sprites are vendored under `assets/sprites/pixvoxel_src`, so a fresh clone rebuilds with no
download. To build from a full extracted pack instead, override the default:
`make tiles PIXVOXEL=/path/to/Revised_PixVoxel_Wargame/standing_frames`.

### The menu design system

The main menu and the commander-select page are dressed by the **Grid Commander Design System** — a
handoff bundle (`handoff/main-menu/`: a spec, a mockup, five token sheets, three reference
components, and a set of terrain sprites) whose palette was lifted pixel-for-pixel from this game's
own tile and unit atlases, so adopting it was alignment, not invention. The numbers it defines live
in one place, **`scenes/common/ui_theme.gd` (`UiTheme`)**: the shell palette (the slates, neutrals
and capture green the game had no authority for), the stylebox recipes (cream/dark panels, the hard
offset shadow, the faction/cream/ghost button and its states, the segmented control, the checkbox,
the focus ring), and the font loaders. Colours that already had an authority are re-exported, never
re-declared — faction hues stay `CommanderVisuals`', cream and ink stay
`CommanderVisuals.PAPER / PAPER_INK / HARD_BORDER` — so there is still exactly one value per colour.
It is built in code, not a `.tres` Theme, because that is the one form the repo can review in a diff.

The map picker draws live board miniatures (`scenes/menu/map_thumbnail.gd`) by blitting the terrain
atlas per cell — column from `TerrainType.atlas_col`, row from `SideIdentity.atlas_row`, the same
authorities the battle board paints with — and the same renderer bakes the slow-panning terrain
field behind the menu, so a thumbnail can never drift from the board it launches.

Two fonts are vendored under `assets/fonts/`, both SIL OFL 1.1 from Google Fonts and recorded in
`assets/LICENSES.md`: **Pixelify Sans** (display and UI chrome) and **Silkscreen** (micro-labels,
numerals, badges). The design-system handoff named them "chosen substitutes" because the repo shipped
no UI font; the substitution ends there — they are the game's faces now, rasterised with antialiasing
off so they sit on the same pixel grid as the art. The battle HUD keeps its current dress; aligning it
to `UiTheme` is a deliberate future step, not a rider on the menu work.
