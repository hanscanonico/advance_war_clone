extends SceneTree
## Pastes the hand-authored air and naval sprites into assets/tiles/units_atlas.png.
##
## tools/build_pixvoxel_atlases.sh writes that atlas *outright*, at the width of
## the PixVoxel roster — the nine land units. Everything past those columns is art
## that pack does not contain, so it has to be re-applied on every rebuild or a
## `make tiles` silently drops it. That is this script's whole job: run it after
## `sprites` (see the `tiles` target in the Makefile), and the columns below are
## restored from the vendored PNGs under SPRITE_DIR.
##
## It widens the canvas to whatever data/units/*.tres now asks for, so the later
## unit-placeholders step finds a full-width atlas and only has to fill the
## columns still lacking real art. Idempotent: each column is overwritten from its
## source PNG, so running it twice is the same as running it once.
##
## Sources are `<unit id>_<team>.png`, 64x64 RGBA, one per team row — build inputs
## rather than runtime resources, which is why a `.gdignore` sits beside them.
## Adding real art for another unit means dropping three PNGs in that directory
## and naming the unit here; nothing else in the pipeline changes.

const ATLAS_PATH := "res://assets/tiles/units_atlas.png"
const SPRITE_DIR := "res://assets/sprites/iso_air_sea"
const TILE := 16
## Atlas cells are 4x the world grid, matching the PixVoxel columns beside them.
const SCALE := 4
## Row order is the team index the battle scene samples with: see
## scenes/battle/unit_sprite.gd, which regions the atlas at `team * SPRITE_PX`.
const TEAM_ROWS: Array[String] = ["neutral", "red", "blue"]
## The units this script supplies art for, by `UnitType.id`.
const SPRITE_IDS: Array[StringName] = [
	&"fighter",
	&"bomber",
	&"b_copter",
	&"t_copter",
	&"battleship",
	&"cruiser",
	&"sub",
	&"lander",
]


func _init() -> void:
	var atlas := Image.load_from_file(ProjectSettings.globalize_path(ATLAS_PATH))
	if atlas == null:
		push_error("paste_unit_sprites: cannot read %s — run `make sprites`" % ATLAS_PATH)
		quit(1)
		return
	var columns := _atlas_columns()
	var painted := _paste(atlas, columns)
	if painted == null:
		quit(1)
		return
	painted.save_png(ATLAS_PATH)
	print(
		(
			"paste_unit_sprites: pasted %d column(s), atlas now %dx%d"
			% [SPRITE_IDS.size(), painted.get_width(), painted.get_height()]
		)
	)
	quit()


## How wide the finished atlas has to be, in cells. Measured over the whole roster,
## not just our columns: past the last column any unit actually asks for, a sprite
## would sample transparent pixels and vanish.
func _atlas_columns() -> int:
	var last := 0
	for unit_type in UnitDB.load_default().all():
		last = maxi(last, unit_type.atlas_col)
	return last + 1


## Copies the source atlas across and lays our columns over it. Returns null,
## having reported why, if a source PNG is missing or the wrong size — a silently
## skipped sprite would show up as an invisible unit at run time, which is a far
## more expensive way to find the same problem.
func _paste(atlas: Image, columns: int) -> Image:
	var cell := TILE * SCALE
	if atlas.get_height() != len(TEAM_ROWS) * cell:
		push_error(
			(
				"paste_unit_sprites: %s is %dx%d; expected %d rows of %dpx"
				% [
					ATLAS_PATH,
					atlas.get_width(),
					atlas.get_height(),
					len(TEAM_ROWS),
					cell,
				]
			)
		)
		return null
	var by_id := {}
	for unit_type in UnitDB.load_default().all():
		by_id[unit_type.id] = unit_type

	var painted := Image.create_empty(
		columns * cell, len(TEAM_ROWS) * cell, false, Image.FORMAT_RGBA8
	)
	var kept := Rect2i(0, 0, mini(atlas.get_width(), columns * cell), len(TEAM_ROWS) * cell)
	painted.blit_rect(atlas, kept, Vector2i.ZERO)

	for id in SPRITE_IDS:
		if not by_id.has(id):
			push_error("paste_unit_sprites: no unit '%s' in the roster" % id)
			return null
		var unit_type: UnitType = by_id[id]
		for row in len(TEAM_ROWS):
			var path := "%s/%s_%s.png" % [SPRITE_DIR, id, TEAM_ROWS[row]]
			var sprite := Image.load_from_file(ProjectSettings.globalize_path(path))
			if sprite == null:
				push_error("paste_unit_sprites: cannot read %s" % path)
				return null
			if sprite.get_width() != cell or sprite.get_height() != cell:
				push_error(
					(
						"paste_unit_sprites: %s is %dx%d; expected %dx%d"
						% [path, sprite.get_width(), sprite.get_height(), cell, cell]
					)
				)
				return null
			# Straight copy, alpha included: these are pixel art authored at the
			# atlas cell size, so there is nothing to blend against and nothing
			# to resample.
			sprite.convert(Image.FORMAT_RGBA8)
			painted.blit_rect(
				sprite, Rect2i(0, 0, cell, cell), Vector2i(unit_type.atlas_col * cell, row * cell)
			)
	return painted
