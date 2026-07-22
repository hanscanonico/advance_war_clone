extends SceneTree
## Paints placeholder art into the columns of assets/tiles/units_atlas.png that
## still have none — the units the CC0 PixVoxel pack does not cover and no hand
## authored sprite has replaced yet.
##
## Run it after tools/build_pixvoxel_atlases.sh (see the `tiles` target in the
## Makefile): it reads the atlas that step wrote, widens the canvas to whatever
## data/units/*.tres now asks for, and repaints only the columns PLACEHOLDER_IDS
## names. Every other column is copied across byte-identical. Idempotent — those
## columns are repainted from scratch, so running it twice is the same as once.
##
## The art is deliberately placeholder: flat 16px silhouettes in the team colour,
## drawn from the ASCII grids below so a shape can be read and edited in the
## source. They are here so a milestone is never blocked on art.
##
## Retiring a placeholder is one edit: drop the unit's id from PLACEHOLDER_IDS
## (and its grid from SPRITES) once real art occupies its column, and this script
## will preserve that column instead of overwriting it. Ownership is an explicit
## list rather than a "column N and up" watermark because the real air and naval
## art landed on columns 9-12 and 14-17, leaving missiles at 13 still a
## placeholder — a watermark cannot describe a hole.

const ATLAS_PATH := "res://assets/tiles/units_atlas.png"
## Columns tools/build_pixvoxel_atlases.sh writes: the length of its UNITS array.
## Only used to sanity-check the atlas we were handed is at least that wide.
const PIXVOXEL_COLS := 9
## The unit ids this script still draws. Everything else in the atlas is real art
## and is passed through untouched.
const PLACEHOLDER_IDS: Array[StringName] = [&"missiles"]
const TILE := 16
## Atlas cells are 4x the world grid, matching the PixVoxel columns beside them.
const SCALE := 4
const ROWS := 3  # 0 = neutral, 1 = red, 2 = blue
const TEAM_COLORS: Array[Color] = [Color("8a9099"), Color("d84a3c"), Color("3c64d8")]
const OUTLINE := Color("14171c")
const GLASS := Color("cfe4f5")
const WAKE := Color("9fd0f2")

## '#' body (team colour) · '-' its shaded half · '+' glass/warhead · 'o' outline
## '~' wake · '.' transparent. One 16x16 grid per unit id.
const SPRITES := {
	&"missiles":
	[
		"................",
		"...........oo...",
		"..........o++o..",
		".........o++o...",
		"........o++o....",
		".......o++o.....",
		"...oooo#oooo....",
		"..############..",
		".##############.",
		".##############.",
		".#------------#.",
		"..############..",
		"..o##o....o##o..",
		"...oo......oo...",
		"................",
		"................",
	],
}


func _init() -> void:
	var atlas := Image.load_from_file(ProjectSettings.globalize_path(ATLAS_PATH))
	if atlas == null:
		push_error("generate_unit_placeholders: cannot read %s — run `make sprites`" % ATLAS_PATH)
		quit(1)
		return
	var types := _placeholder_types()
	if types.is_empty():
		print("generate_unit_placeholders: every column has real art, nothing to draw")
		quit()
		return
	var columns := _atlas_columns()
	var painted := _paint(atlas, types, columns)
	if painted == null:
		quit(1)
		return
	painted.save_png(ATLAS_PATH)
	print(
		(
			"generate_unit_placeholders: wrote %d placeholder column(s), atlas now %dx%d"
			% [types.size(), painted.get_width(), painted.get_height()]
		)
	)
	quit()


## Units whose atlas column this script owns, in column order — the roster entries
## named by PLACEHOLDER_IDS. An id with no matching `.tres` is reported rather
## than skipped silently, since it means a unit was renamed out from under us.
func _placeholder_types() -> Array[UnitType]:
	var by_id := {}
	for unit_type in UnitDB.load_default().all():
		by_id[unit_type.id] = unit_type
	var types: Array[UnitType] = []
	for id in PLACEHOLDER_IDS:
		if not by_id.has(id):
			push_warning("generate_unit_placeholders: no unit '%s' in the roster" % id)
			continue
		types.append(by_id[id])
	types.sort_custom(func(a: UnitType, b: UnitType) -> bool: return a.atlas_col < b.atlas_col)
	return types


## How wide the finished atlas has to be, in cells: past the last column any unit
## actually asks for, a sprite would sample transparent pixels and vanish. Measured
## over the whole roster, not just our placeholders — sizing to the placeholders
## alone would crop away every real-art column beyond the last one we draw.
func _atlas_columns() -> int:
	var last := PIXVOXEL_COLS - 1
	for unit_type in UnitDB.load_default().all():
		last = maxi(last, unit_type.atlas_col)
	return last + 1


## Copies the existing atlas across unchanged and redraws only our columns over
## it. Returns null (having reported why) if the source atlas is not the size the
## PixVoxel step is documented to write.
func _paint(atlas: Image, types: Array[UnitType], columns: int) -> Image:
	var cell := TILE * SCALE
	if atlas.get_height() != ROWS * cell or atlas.get_width() < PIXVOXEL_COLS * cell:
		push_error(
			(
				"generate_unit_placeholders: %s is %dx%d; expected at least %dx%d"
				% [
					ATLAS_PATH,
					atlas.get_width(),
					atlas.get_height(),
					PIXVOXEL_COLS * cell,
					ROWS * cell
				]
			)
		)
		return null
	var painted := Image.create_empty(columns * cell, ROWS * cell, false, Image.FORMAT_RGBA8)
	# Everything the source atlas already holds, including real art in columns we
	# do not own. Clamped in case the atlas is wider than the roster now needs.
	var kept := Rect2i(0, 0, mini(atlas.get_width(), columns * cell), ROWS * cell)
	painted.blit_rect(atlas, kept, Vector2i.ZERO)
	for row in ROWS:
		for unit_type in types:
			var sprite := _render(unit_type, row, cell)
			painted.blit_rect(
				sprite, Rect2i(0, 0, cell, cell), Vector2i(unit_type.atlas_col * cell, row * cell)
			)
	return painted


## One unit in one team's colours, drawn at the world grid then scaled up with
## nearest neighbour so it stays hard-edged next to the 16px terrain.
func _render(unit_type: UnitType, row: int, cell: int) -> Image:
	var img := Image.create_empty(TILE, TILE, false, Image.FORMAT_RGBA8)
	var body: Color = TEAM_COLORS[row]
	var grid: Array = SPRITES.get(unit_type.id, [])
	if grid.is_empty():
		# A unit with no grid still gets a readable marker rather than an empty
		# cell, which would look like a rendering bug rather than missing art.
		push_warning("generate_unit_placeholders: no sprite grid for '%s'" % unit_type.id)
		img.fill_rect(Rect2i(3, 3, TILE - 6, TILE - 6), OUTLINE)
		img.fill_rect(Rect2i(4, 4, TILE - 8, TILE - 8), body)
	else:
		for y in grid.size():
			var line: String = grid[y]
			for x in line.length():
				var color := _color_for(line[x], body)
				if color.a > 0.0:
					img.set_pixel(x, y, color)
	img.resize(cell, cell, Image.INTERPOLATE_NEAREST)
	return img


func _color_for(glyph: String, body: Color) -> Color:
	match glyph:
		"#":
			return body
		"-":
			return body.darkened(0.28)
		"+":
			return GLASS
		"o":
			return OUTLINE
		"~":
			return WAKE
		_:
			return Color(0, 0, 0, 0)
