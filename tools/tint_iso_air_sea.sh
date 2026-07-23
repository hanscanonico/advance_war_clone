#!/usr/bin/env bash
#
# Derives the Iron and Verdant team rows of the hand-authored air/naval sprites
# from the committed red row, and vendors them beside it under
# assets/sprites/iso_air_sea/ as build inputs for tools/paste_unit_sprites.gd.
# The airport and port building sprites under assets/sprites/iso_buildings/ are
# the same class of art (three hand-authored rows, no palette master), so they
# get their faction rows here too — one recipe, one pair of tint constants, for
# every hand-authored sprite family.
#
# The PixVoxel land units get their extra faction rows from a palette tweak of
# the white masters (see tools/build_pixvoxel_atlases.sh ROW_PALETTE); the eight
# air/naval units have no such master, only three hand-painted rows. This script
# is their equivalent: an HSB rotation of the saturated red row onto each new
# faction's hue, applied *only* to the team-coloured pixels.
#
# "Team-coloured" is defined exactly, not guessed: a pixel is team paint iff the
# red row differs from the neutral row there. Every other pixel — the black
# outline, the navy cockpit shadow, the transparent background — is byte-identical
# across all three committed rows, so it is copied straight from red and the new
# rows share those pixels with the old ones by construction. Anti-aliased edges
# between team paint and shadow differ from neutral too, so they rotate with the
# rest of the paint and stay clean.
#
# Reproducible: same red row in, same bytes out (metadata stripped, as the atlas
# builder does). Re-run it whenever the red sprites change; commit the results.
#
# Usage:  tools/tint_iso_air_sea.sh
# Requires ImageMagick 7 (`brew install imagemagick`).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UNIT_DIR="$ROOT/assets/sprites/iso_air_sea"
BLDG_DIR="$ROOT/assets/sprites/iso_buildings"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

command -v magick >/dev/null || { echo "error: ImageMagick 7 (magick) not found" >&2; exit 1; }

# Same PNG-reproducibility strip the atlas builder uses: drop the tIME and
# date chunks so an unchanged rebuild is byte-identical and never dirties the tree.
NO_TIME=(-strip -define png:exclude-chunk=time)

# HSB rotations of the red row (red hue = 0deg), as ImageMagick -modulate
# brightness,saturation,hue triples. Hue is on a 0..200 scale where 100 = no
# shift and each 100/180 step is one degree.
#   iron    slate  #4a5258 — cool and desaturated: rotate toward blue, drop
#                            saturation hard, darken a touch.
#   verdant green  #2c8636 — rotate +120deg onto green, keep the vivid ramp.
IRON_MOD=(-modulate 66,17,20)
VERDANT_MOD=(-modulate 84,96,167)

UNITS=(fighter bomber b_copter t_copter battleship cruiser sub lander)
BUILDINGS=(airport port)

tint_one() {
	local dir="$1" id="$2" row="$3"; shift 3
	local mod=("$@")
	local red="$dir/${id}_red.png" neutral="$dir/${id}_neutral.png"
	[ -f "$red" ] || { echo "error: missing $red" >&2; exit 1; }
	[ -f "$neutral" ] || { echo "error: missing $neutral" >&2; exit 1; }
	# White wherever the red row diverges from neutral: exactly the team paint.
	# Difference on the RGB channels, then collapse to one channel and threshold
	# so any non-zero difference reads as fully white.
	magick "$red" "$neutral" -alpha off -compose Difference -composite \
		-separate -evaluate-sequence Max -threshold 0 "$WORK/mask.png"
	# Rotate every pixel, then keep the rotation only under the mask; red's own
	# pixels (and its alpha) survive everywhere else, so shadow/outline/background
	# stay byte-identical to the red row.
	magick "$red" \
		\( "$red" "${mod[@]}" \) \
		"$WORK/mask.png" \
		-compose over -composite \
		"${NO_TIME[@]}" "$dir/${id}_${row}.png"
}

echo "tinting ${#UNITS[@]} air/naval units -> iron, verdant"
for id in "${UNITS[@]}"; do
	tint_one "$UNIT_DIR" "$id" iron "${IRON_MOD[@]}"
	tint_one "$UNIT_DIR" "$id" verdant "${VERDANT_MOD[@]}"
done
echo "wrote $(( ${#UNITS[@]} * 2 )) sprites into $UNIT_DIR"

echo "tinting ${#BUILDINGS[@]} property buildings -> iron, verdant"
for id in "${BUILDINGS[@]}"; do
	tint_one "$BLDG_DIR" "$id" iron "${IRON_MOD[@]}"
	tint_one "$BLDG_DIR" "$id" verdant "${VERDANT_MOD[@]}"
done
echo "wrote $(( ${#BUILDINGS[@]} * 2 )) sprites into $BLDG_DIR"
