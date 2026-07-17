extends SceneTree
## Generates all placeholder art: the 16x16 terrain atlas (9 terrain columns x
## 3 team rows), the grid cursor sprite, and the project icon.
## Reproducible programmer art, meant to be replaced by a real tileset later.
##
## Run with:  make tiles

const TILE := 16
const COLS := 9  # road, plains, woods, mountain, river, city, base, hq, sea
const ROWS := 3  # 0 = neutral, 1 = red, 2 = blue

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
const WALL := Color("e8e0d0")
const DOOR := Color("37474f")
const TEAM_COLORS: Array[Color] = [Color("8a9099"), Color("d84a3c"), Color("3c64d8")]

var img: Image


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/tiles"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/ui"))
	_generate_atlas()
	_generate_cursor()
	_generate_icon()
	print("generate_tiles: wrote terrain_atlas.png, cursor.png, icon.png")
	quit()


func _generate_atlas() -> void:
	img = Image.create_empty(COLS * TILE, ROWS * TILE, false, Image.FORMAT_RGBA8)
	for row in ROWS:
		var team: Color = TEAM_COLORS[row]
		_draw_road(_at(0, row))
		_draw_plains(_at(1, row))
		_draw_woods(_at(2, row))
		_draw_mountain(_at(3, row))
		_draw_river(_at(4, row))
		_draw_city(_at(5, row), team)
		_draw_base(_at(6, row), team)
		_draw_hq(_at(7, row), team)
		_draw_sea(_at(8, row))
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
		Vector2i(3, 4), Vector2i(9, 2), Vector2i(12, 7), Vector2i(5, 11),
		Vector2i(10, 13), Vector2i(14, 10), Vector2i(2, 9), Vector2i(7, 7),
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


func _draw_city(o: Vector2i, team: Color) -> void:
	_ground(o, PAVE)
	_fill(o, 3, 5, 10, 8, WALL)
	_fill(o, 2, 2, 12, 3, team)
	_fill(o, 5, 7, 2, 2, DOOR)
	_fill(o, 9, 7, 2, 2, DOOR)
	_fill(o, 7, 10, 2, 3, DOOR)


func _draw_base(o: Vector2i, team: Color) -> void:
	_ground(o, PAVE)
	_fill(o, 11, 2, 2, 4, ROCK_DARK)  # chimney
	_fill(o, 2, 6, 12, 7, WALL)
	_fill(o, 2, 4, 12, 3, team)
	_fill(o, 6, 9, 4, 4, DOOR)


func _draw_hq(o: Vector2i, team: Color) -> void:
	_ground(o, PAVE)
	_fill(o, 12, 1, 1, 6, ROCK_DARK)  # flag pole
	_fill(o, 9, 1, 3, 3, team)        # flag
	_fill(o, 3, 6, 10, 7, WALL)
	_fill(o, 2, 4, 12, 3, team)
	_fill(o, 5, 8, 2, 2, DOOR)
	_fill(o, 9, 8, 2, 2, DOOR)
	_fill(o, 7, 10, 2, 3, DOOR)


func _generate_cursor() -> void:
	img = Image.create_empty(TILE, TILE, false, Image.FORMAT_RGBA8)
	var shadow := Color(0.05, 0.05, 0.05, 0.9)
	# corner brackets: shadow offset (1,1), then white on top
	for offset: Vector2i in [Vector2i(1, 1), Vector2i.ZERO]:
		var c := Color.WHITE if offset == Vector2i.ZERO else shadow
		for corner: Array in [
			[0, 0, 1, 1], [TILE - 6, 0, -1, 1],
			[0, TILE - 6, 1, -1], [TILE - 6, TILE - 6, -1, -1],
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
