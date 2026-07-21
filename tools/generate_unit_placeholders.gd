extends SceneTree
## Paints placeholder art for every unit the CC0 PixVoxel pack has no sprite for
## — the aircraft and the fleet — into the columns of assets/tiles/units_atlas.png
## past the ones tools/build_pixvoxel_atlases.sh owns.
##
## Run it after that script (see the `tiles` target in the Makefile): it reads the
## atlas that step wrote, widens the canvas to whatever data/units/*.tres now asks
## for, and leaves the PixVoxel columns byte-identical. Idempotent — every column
## from PIXVOXEL_COLS up is repainted from scratch, so running it twice is the
## same as running it once.
##
## The art is deliberately placeholder: flat 16px silhouettes in the team colour,
## drawn from the ASCII grids below so a shape can be read and edited in the
## source. They are here so a milestone is never blocked on art; swapping in real
## sprites means extending the PixVoxel roster and shrinking PIXVOXEL_COLS' reach,
## not touching any rule.

const ATLAS_PATH := "res://assets/tiles/units_atlas.png"
## Columns tools/build_pixvoxel_atlases.sh writes: the length of its UNITS array.
## Everything at or past this column is ours.
const PIXVOXEL_COLS := 9
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
	&"fighter":
	[
		"................",
		".......##.......",
		"......o##o......",
		"......####......",
		"......#++#......",
		"......####......",
		".##############.",
		".##############.",
		"..o##########o..",
		"......####......",
		"......####......",
		"....########....",
		"....########....",
		"....o##..##o....",
		"................",
		"................",
	],
	&"bomber":
	[
		"................",
		"......o##o......",
		"......####......",
		"......#++#......",
		"......####......",
		"......####......",
		"################",
		"################",
		"..--..----..--..",
		"......####......",
		"......####......",
		"......####......",
		"...##########...",
		"...##########...",
		"...o##....##o...",
		"................",
	],
	&"b_copter":
	[
		"................",
		"oooooooooooooooo",
		".......##.......",
		"......o##o......",
		"...##########...",
		"..############..",
		".##++##########o",
		".##++###########",
		".##############o",
		"..############..",
		"...##########...",
		"....o.....o.....",
		"..oooooooooooo..",
		"................",
		"................",
		"................",
	],
	&"t_copter":
	[
		"................",
		"oooooooooooooooo",
		".......##.......",
		"......o##o......",
		"..############..",
		".##############.",
		".##++######++##o",
		".##++######++###",
		".##############o",
		".##############.",
		"..############..",
		"....o.....o.....",
		"..oooooooooooo..",
		"................",
		"................",
		"................",
	],
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
		print("generate_unit_placeholders: nothing past column %d to draw" % PIXVOXEL_COLS)
		quit()
		return
	var columns := _atlas_columns(types)
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


## Units whose atlas column this script owns, in column order. Read from the unit
## database rather than listed here, so adding a `.tres` is the only step.
func _placeholder_types() -> Array[UnitType]:
	var types: Array[UnitType] = []
	for unit_type in UnitDB.load_default().all():
		if unit_type.atlas_col >= PIXVOXEL_COLS:
			types.append(unit_type)
	types.sort_custom(func(a: UnitType, b: UnitType) -> bool: return a.atlas_col < b.atlas_col)
	return types


## How wide the finished atlas has to be, in cells: past the last column any unit
## actually asks for, a sprite would sample transparent pixels and vanish.
func _atlas_columns(types: Array[UnitType]) -> int:
	var last := PIXVOXEL_COLS - 1
	for unit_type in types:
		last = maxi(last, unit_type.atlas_col)
	return last + 1


## Copies the PixVoxel columns across unchanged and draws ours beside them.
## Returns null (having reported why) if the source atlas is not the size the
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
	var kept := Rect2i(0, 0, PIXVOXEL_COLS * cell, ROWS * cell)
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
