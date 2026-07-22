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
## `--check` (after `--`) validates the sources and the roster mapping without
## writing anything — the `unit-sprites-check` preflight in `make tiles`, which
## has to fail before the destructive `ground` step dirties the tree. The atlas
## itself is deliberately not inspected then: `sprites` rewrites it before the
## paste runs.
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
	var sources := _load_sources()
	if sources.is_empty():
		quit(1)
		return
	if OS.get_cmdline_user_args().has("--check"):
		print(
			(
				"paste_unit_sprites: preflight ok — %d unit(s) x %d team row(s) under %s"
				% [SPRITE_IDS.size(), TEAM_ROWS.size(), SPRITE_DIR]
			)
		)
		quit()
		return
	var atlas := Image.load_from_file(ProjectSettings.globalize_path(ATLAS_PATH))
	if atlas == null:
		push_error("paste_unit_sprites: cannot read %s — run `make sprites`" % ATLAS_PATH)
		quit(1)
		return
	var painted := _paste(atlas, sources, _atlas_columns())
	if painted == null:
		quit(1)
		return
	var err := painted.save_png(ATLAS_PATH)
	if err != OK:
		push_error("paste_unit_sprites: cannot write %s: %s" % [ATLAS_PATH, error_string(err)])
		quit(1)
		return
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


## Loads and validates every source sprite, keyed by the atlas column it lands in
## (one Array[Image] per column, ordered by team row). Returns an empty
## Dictionary, having reported why, if a unit id is missing from the roster or a
## source PNG is absent or the wrong size — a silently skipped sprite would show
## up as an invisible unit at run time, which is a far more expensive way to find
## the same problem.
func _load_sources() -> Dictionary:
	var cell := TILE * SCALE
	var by_id := {}
	for unit_type in UnitDB.load_default().all():
		by_id[unit_type.id] = unit_type
	var sources := {}
	for id in SPRITE_IDS:
		if not by_id.has(id):
			push_error("paste_unit_sprites: no unit '%s' in the roster" % id)
			return {}
		var unit_type: UnitType = by_id[id]
		var rows: Array[Image] = []
		for row in len(TEAM_ROWS):
			var path := "%s/%s_%s.png" % [SPRITE_DIR, id, TEAM_ROWS[row]]
			var sprite := Image.load_from_file(ProjectSettings.globalize_path(path))
			if sprite == null:
				push_error("paste_unit_sprites: cannot read %s" % path)
				return {}
			if sprite.get_width() != cell or sprite.get_height() != cell:
				push_error(
					(
						"paste_unit_sprites: %s is %dx%d; expected %dx%d"
						% [path, sprite.get_width(), sprite.get_height(), cell, cell]
					)
				)
				return {}
			sprite.convert(Image.FORMAT_RGBA8)
			rows.append(sprite)
		sources[unit_type.atlas_col] = rows
	return sources


## Copies the source atlas across and lays our columns over it. Returns null,
## having reported why, if the atlas is not the height the sprites step writes.
func _paste(atlas: Image, sources: Dictionary, columns: int) -> Image:
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
	var painted := Image.create_empty(
		columns * cell, len(TEAM_ROWS) * cell, false, Image.FORMAT_RGBA8
	)
	var kept := Rect2i(0, 0, mini(atlas.get_width(), columns * cell), len(TEAM_ROWS) * cell)
	painted.blit_rect(atlas, kept, Vector2i.ZERO)

	# Straight copy, alpha included: these are pixel art authored at the
	# atlas cell size, so there is nothing to blend against and nothing
	# to resample.
	for col in sources:
		var rows: Array[Image] = sources[col]
		for row in len(TEAM_ROWS):
			painted.blit_rect(rows[row], Rect2i(0, 0, cell, cell), Vector2i(col * cell, row * cell))
	return painted
