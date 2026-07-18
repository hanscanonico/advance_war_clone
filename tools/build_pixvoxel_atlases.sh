#!/usr/bin/env bash
#
# Composes the battle scene's unit art and property-building art from the CC0
# PixVoxel "Revised Wargame Sprites" pack by Tommy Ettinger.
#
#   source: https://opengameart.org/content/pixvoxel-revised-isometric-wargame-sprites
#   pack:   Revised_PixVoxel_Wargame_1.7z  ->  Revised_PixVoxel_Wargame/standing_frames/
#
# Usage:  tools/build_pixvoxel_atlases.sh <path-to-standing_frames>
#
# Writes assets/tiles/units_atlas.png outright, and repaints the city/base/hq
# columns of assets/tiles/terrain_atlas.png (which tools/generate_tiles.gd
# leaves as bare paved lots). Run it after `make tiles`; see the `sprites`
# target in the Makefile. Both steps are idempotent — the building columns are
# rebuilt from a freshly drawn base rather than composited onto themselves.
#
# Requires ImageMagick 7 (`brew install imagemagick`).

set -euo pipefail

SRC="${1:?usage: build_pixvoxel_atlases.sh <path to Revised_PixVoxel_Wargame/standing_frames>}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TILES="$ROOT/assets/tiles"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

CELL=64          # atlas cell: 4x the 16px world grid, so art is texel-exact at 1x zoom
FRAME="Large_face0_0"  # one standing frame, one facing, for every sprite

# Team rows: 0 neutral, 1 red, 2 blue — matching GameState.TEAMS / MapData.NEUTRAL.
# PixVoxel colour1 is white and gets desaturated to grey, so a neutral property
# never reads as a team. colour0 (dark) is unusable here: its red trim looks red-team.
ROW_PALETTE=(color1 color2 color6)
ROW_TWEAK=("-modulate 100,0,100" "" "")

# One crop box shared by every unit and one by every building. A single uniform
# scale then preserves both relative size (infantry stays smaller than a tank)
# and a common ground line, which per-sprite trimming would destroy.
UNIT_CROP="68x86+15+15"
BLDG_CROP="81x91+6+12"

# Column order is atlas_col from data/units/*.tres.
UNITS=(Infantry Infantry_T Supply_T Tank Tank_P Artillery_S Artillery Artillery_T Supply)
# Columns 5, 6, 7 of the terrain atlas: city, base, hq.
BUILDINGS=(City Factory Castle)
BLDG_COLS=(5 6 7)

# Paved lot under a building, matching _ground(o, PAVE) in tools/generate_tiles.gd:
# PAVE with a 1px (4px at this scale) PAVE.darkened(0.12) edge so the grid reads.
PAVE="#cfcfcf"
PAVE_EDGE="#b6b6b6"

command -v magick >/dev/null || { echo "error: ImageMagick 7 (magick) not found" >&2; exit 1; }
[ -d "$SRC" ] || { echo "error: no such directory: $SRC" >&2; exit 1; }

# Scale a source sprite into one transparent CELL x CELL atlas cell. Nearest
# neighbour only: these sit next to 16px art and must stay hard-edged.
render_cell() {
	local src="$1" crop="$2" tweak="$3" out="$4"
	[ -f "$src" ] || { echo "error: missing sprite $src" >&2; exit 1; }
	# shellcheck disable=SC2086 # $tweak is a deliberate multi-token option
	magick "$src" $tweak -crop "$crop" +repage \
		-filter point -resize ${CELL}x${CELL} \
		-background none -gravity center -extent ${CELL}x${CELL} \
		"$out"
}

echo "building units_atlas.png (${#UNITS[@]} cols x ${#ROW_PALETTE[@]} rows @ ${CELL}px)"
for row in "${!ROW_PALETTE[@]}"; do
	for col in "${!UNITS[@]}"; do
		render_cell "$SRC/${ROW_PALETTE[$row]}_${UNITS[$col]}_${FRAME}.png" \
			"$UNIT_CROP" "${ROW_TWEAK[$row]}" "$WORK/u_${row}_${col}.png"
	done
	magick "$WORK"/u_${row}_*.png +append "$WORK/urow_$row.png"
done
magick "$WORK"/urow_*.png -append "$TILES/units_atlas.png"

echo "painting city/base/hq into terrain_atlas.png"
[ -f "$TILES/terrain_atlas.png" ] || { echo "error: run 'make tiles' first" >&2; exit 1; }
# -type TrueColor is load-bearing: the lot is pure grey, so ImageMagick would
# otherwise write it in grayscale colorspace and desaturate the building
# composited onto it, leaving every team's property the same colour.
magick -size ${CELL}x${CELL} "xc:$PAVE_EDGE" \
	-fill "$PAVE" -draw "rectangle 4,4 $((CELL - 5)),$((CELL - 5))" \
	-type TrueColor PNG32:"$WORK/pave.png"

cp "$TILES/terrain_atlas.png" "$WORK/terrain.png"
for row in "${!ROW_PALETTE[@]}"; do
	for i in "${!BUILDINGS[@]}"; do
		render_cell "$SRC/${ROW_PALETTE[$row]}_${BUILDINGS[$i]}_${FRAME}.png" \
			"$BLDG_CROP" "${ROW_TWEAK[$row]}" "$WORK/b.png"
		magick "$WORK/pave.png" "$WORK/b.png" -composite "$WORK/tile.png"
		magick "$WORK/terrain.png" "$WORK/tile.png" \
			-geometry "+$((BLDG_COLS[i] * CELL))+$((row * CELL))" \
			-composite "$WORK/terrain.png"
	done
done
cp "$WORK/terrain.png" "$TILES/terrain_atlas.png"

magick identify "$TILES/units_atlas.png" "$TILES/terrain_atlas.png"
echo "done"
