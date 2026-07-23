extends SceneTree
## Generates the ground terrain atlas (9 terrain columns x 5 team rows), the
## range overlay, the grid cursor sprite, and the project icon.
##
## Unit art and the city/base/hq buildings are deliberately NOT drawn here: they
## come from the CC0 PixVoxel pack via tools/build_pixvoxel_atlases.sh, which
## paints the property columns this script leaves as bare paved lots. Running
## this alone would blank those buildings, so run the pair:  make tiles
##
## Tiles are drawn at 16px — the world grid — then scaled 4x on save, because
## the atlas cell is 64px to give the PixVoxel art room.

const TILE := 16
## Atlas cells are 4x the world grid. Nearest-neighbour, so the 16px art is
## pixel-identical on screen at the battle scene's default zoom.
const SCALE := 4
## road, plains, woods, mountain, river, city, base, hq, sea, airport, port,
## shoal, bridge, reef
## Keep TERRAIN_COLS in tools/build_pixvoxel_atlases.sh in step: that script
## checks the atlas it paints buildings into is exactly this wide.
const COLS := 14
## 0 neutral, 1 meridian(red), 2 aurora(blue), 3 iron, 4 verdant — the
## faction-identity atlas order (plan FI1). Rows 0-2 render byte-for-byte as
## before; the two faction rows are inert until the FI2 resolver samples them.
## Keep TERRAIN_ROWS in tools/build_pixvoxel_atlases.sh in step: it checks the
## atlas it paints buildings into is exactly this many rows tall.
const ROWS := 5

const GRASS := Color("78c850")
const GRASS_DARK := Color("5aa63c")
const ROAD := Color("c9b884")
const ROAD_DARK := Color("a89868")
const WATER := Color("3f8fdc")
const WATER_DARK := Color("2a6fbf")
const WATER_LIGHT := Color("7cc4f0")
const TREE := Color("2e7d32")
const TREE_DARK := Color("1b5e20")
const TRUNK := Color("6d4c41")
const ROCK := Color("9e9e9e")
const ROCK_DARK := Color("757575")
const SNOW := Color("eeeeee")
const PAVE := Color("cfcfcf")
const ASPHALT := Color("6f747c")
const ASPHALT_DARK := Color("585d64")
const MARKING := Color("e4e7eb")
const SAND := Color("e0d3a4")
const SAND_DARK := Color("c4b585")
# Neutral, then one hue per faction row. Rows 0-2 are the shipped values and must
# not change (byte-identical proof). The iron and verdant entries are
# CommanderVisuals' own faction colours, so the airport tower and port warehouse
# a faction owns match the colour that faction wears everywhere else in the UI.
const TEAM_COLORS: Array[Color] = [
	Color("8a9099"), Color("d84a3c"), Color("3c64d8"), Color("4a5258"), Color("2c8636")
]

var img: Image


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/tiles"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/ui"))
	_generate_atlas()
	_generate_overlay()
	_generate_cursor()
	_generate_icon()
	print("generate_tiles: wrote terrain_atlas.png, overlay.png, cursor.png, icon.png")
	quit()


func _generate_atlas() -> void:
	img = Image.create_empty(COLS * TILE, ROWS * TILE, false, Image.FORMAT_RGBA8)
	for row in ROWS:
		_draw_road(_at(0, row))
		_draw_plains(_at(1, row))
		_draw_woods(_at(2, row))
		_draw_mountain(_at(3, row))
		_draw_river(_at(4, row))
		# city, base, hq: bare lots. build_pixvoxel_atlases.sh paints the
		# team-coloured building on top, per row.
		_ground(_at(5, row), PAVE)
		_ground(_at(6, row), PAVE)
		_ground(_at(7, row), PAVE)
		_draw_sea(_at(8, row))
		# The airport and port are drawn whole here, buildings included, rather
		# than left as lots for the PixVoxel step: that pack has no hangar and no
		# quay, and at 16px a runway and a jetty read more clearly anyway.
		_draw_airport(_at(9, row), row)
		_draw_port(_at(10, row), row)
		_draw_shoal(_at(11, row))
		_draw_bridge(_at(12, row))
		_draw_reef(_at(13, row))
	img.resize(COLS * TILE * SCALE, ROWS * TILE * SCALE, Image.INTERPOLATE_NEAREST)
	img.save_png("res://assets/tiles/terrain_atlas.png")


func _at(col: int, row: int) -> Vector2i:
	return Vector2i(col * TILE, row * TILE)


func _fill(o: Vector2i, x: int, y: int, w: int, h: int, c: Color) -> void:
	img.fill_rect(Rect2i(o.x + x, o.y + y, w, h), c)


## Base color + subtle darker 1px outline so the grid stays readable.
func _ground(o: Vector2i, c: Color) -> void:
	_fill(o, 0, 0, TILE, TILE, c.darkened(0.12))
	_fill(o, 1, 1, TILE - 2, TILE - 2, c)


func _draw_road(o: Vector2i) -> void:
	_ground(o, ROAD)
	_fill(o, 3, 7, 3, 2, ROAD_DARK)
	_fill(o, 10, 7, 3, 2, ROAD_DARK)


func _draw_plains(o: Vector2i) -> void:
	_ground(o, GRASS)
	for p: Vector2i in [
		Vector2i(3, 4),
		Vector2i(9, 2),
		Vector2i(12, 7),
		Vector2i(5, 11),
		Vector2i(10, 13),
		Vector2i(14, 10),
		Vector2i(2, 9),
		Vector2i(7, 7),
	]:
		_fill(o, p.x, p.y, 1, 1, GRASS_DARK)


func _draw_woods(o: Vector2i) -> void:
	_ground(o, GRASS)
	# two simple trees
	_fill(o, 3, 3, 5, 4, TREE)
	_fill(o, 3, 6, 5, 1, TREE_DARK)
	_fill(o, 5, 7, 1, 2, TRUNK)
	_fill(o, 9, 7, 5, 4, TREE)
	_fill(o, 9, 10, 5, 1, TREE_DARK)
	_fill(o, 11, 11, 1, 2, TRUNK)


func _draw_mountain(o: Vector2i) -> void:
	_ground(o, GRASS)
	for y in range(3, 14):
		var t := float(y - 3) / 10.0
		var half := int(round(1.0 + t * 6.0))
		var color := SNOW if y <= 5 else ROCK
		_fill(o, 8 - half, y, half * 2, 1, color)
		_fill(o, 8 - half, y, 1, 1, ROCK_DARK)


func _draw_river(o: Vector2i) -> void:
	_ground(o, WATER)
	_fill(o, 2, 4, 4, 1, WATER_LIGHT)
	_fill(o, 9, 5, 4, 1, WATER_LIGHT)
	_fill(o, 4, 10, 4, 1, WATER_LIGHT)
	_fill(o, 11, 11, 3, 1, WATER_LIGHT)


func _draw_sea(o: Vector2i) -> void:
	_ground(o, WATER_DARK)
	_fill(o, 2, 4, 4, 1, WATER)
	_fill(o, 9, 6, 4, 1, WATER)
	_fill(o, 4, 11, 4, 1, WATER)
	_fill(o, 12, 12, 2, 1, SNOW)


## Runway with centre dashes and a team-coloured control tower, so who owns the
## airfield reads from the tile itself the way a city's roof does.
func _draw_airport(o: Vector2i, row: int) -> void:
	_ground(o, ASPHALT)
	_fill(o, 1, 6, 14, 5, ASPHALT_DARK)
	for x: int in [2, 6, 10]:
		_fill(o, x, 8, 3, 1, MARKING)
	_fill(o, 9, 1, 5, 4, TEAM_COLORS[row].darkened(0.25))
	_fill(o, 10, 2, 3, 2, MARKING)
	_fill(o, 2, 12, 4, 2, TEAM_COLORS[row])


## Deep water with a team-coloured warehouse on a quay: the naval factory, and
## the only place hulls repair.
func _draw_port(o: Vector2i, row: int) -> void:
	_ground(o, WATER_DARK)
	_fill(o, 0, 0, TILE, 7, PAVE.darkened(0.12))
	_fill(o, 1, 1, TILE - 2, 5, PAVE)
	_fill(o, 2, 1, 6, 5, TEAM_COLORS[row].darkened(0.2))
	_fill(o, 3, 2, 4, 2, MARKING)
	_fill(o, 10, 2, 4, 4, ASPHALT)
	_fill(o, 7, 7, 3, 6, ASPHALT_DARK)  # the jetty, running out into the water
	_fill(o, 2, 10, 4, 1, WATER)
	_fill(o, 11, 12, 3, 1, WATER)


## Sand meeting water: the beach a lander puts vehicles ashore on.
func _draw_shoal(o: Vector2i) -> void:
	_ground(o, SAND)
	_fill(o, 0, 10, TILE, 6, WATER)
	_fill(o, 0, 10, TILE, 1, SAND_DARK)
	for p: Vector2i in [Vector2i(3, 3), Vector2i(9, 5), Vector2i(6, 8), Vector2i(12, 2)]:
		_fill(o, p.x, p.y, 1, 1, SAND_DARK)
	_fill(o, 3, 13, 5, 1, WATER_LIGHT)


## A road carried over the water. Ground crosses it; hulls do not fit under it,
## which is what makes a bridge a naval chokepoint as well as a land one.
func _draw_bridge(o: Vector2i) -> void:
	_ground(o, WATER)
	_fill(o, 0, 3, TILE, 10, ROAD)
	_fill(o, 0, 3, TILE, 1, ROAD_DARK)
	_fill(o, 0, 12, TILE, 1, ROAD_DARK)
	_fill(o, 3, 7, 3, 2, ROAD_DARK)
	_fill(o, 10, 7, 3, 2, ROAD_DARK)


## Shallow rock: passable to hulls at a price, and cover in fog the way woods are.
func _draw_reef(o: Vector2i) -> void:
	_ground(o, WATER_DARK)
	for p: Vector2i in [Vector2i(3, 4), Vector2i(9, 3), Vector2i(5, 9), Vector2i(11, 10)]:
		_fill(o, p.x, p.y, 3, 2, ROCK)
		_fill(o, p.x, p.y + 2, 3, 1, ROCK_DARK)
	_fill(o, 2, 12, 4, 1, WATER)
	_fill(o, 10, 1, 3, 1, WATER)


## Semi-transparent white tile; the scene modulates it (blue = move range).
func _generate_overlay() -> void:
	img = Image.create_empty(TILE, TILE, false, Image.FORMAT_RGBA8)
	img.fill_rect(Rect2i(0, 0, TILE, TILE), Color(1, 1, 1, 0.5))
	img.fill_rect(Rect2i(1, 1, TILE - 2, TILE - 2), Color(1, 1, 1, 0.34))
	img.save_png("res://assets/tiles/overlay.png")


func _generate_cursor() -> void:
	img = Image.create_empty(TILE, TILE, false, Image.FORMAT_RGBA8)
	var shadow := Color(0.05, 0.05, 0.05, 0.9)
	# corner brackets: shadow offset (1,1), then white on top
	for offset: Vector2i in [Vector2i(1, 1), Vector2i.ZERO]:
		var c := Color.WHITE if offset == Vector2i.ZERO else shadow
		for corner: Array in [
			[0, 0, 1, 1],
			[TILE - 6, 0, -1, 1],
			[0, TILE - 6, 1, -1],
			[TILE - 6, TILE - 6, -1, -1],
		]:
			var x: int = corner[0]
			var y: int = corner[1]
			var hx := x if corner[2] > 0 else x
			var hy := y if corner[3] > 0 else y + 4
			var vx := x if corner[2] > 0 else x + 4
			var vy := y if corner[3] > 0 else y
			_safe_fill(hx + offset.x, hy + offset.y, 6, 2, c)
			_safe_fill(vx + offset.x, vy + offset.y, 2, 6, c)
	img.save_png("res://assets/ui/cursor.png")


func _safe_fill(x: int, y: int, w: int, h: int, c: Color) -> void:
	var rect := Rect2i(x, y, w, h).intersection(Rect2i(0, 0, img.get_width(), img.get_height()))
	if rect.has_area():
		img.fill_rect(rect, c)


func _generate_icon() -> void:
	img = Image.create_empty(128, 128, false, Image.FORMAT_RGBA8)
	img.fill(GRASS)
	img.fill_rect(Rect2i(56, 0, 16, 128), ROAD)
	img.fill_rect(Rect2i(0, 56, 128, 16), ROAD)
	img.fill_rect(Rect2i(14, 14, 28, 28), TEAM_COLORS[1])
	img.fill_rect(Rect2i(86, 86, 28, 28), TEAM_COLORS[2])
	img.save_png("res://assets/icon.png")
