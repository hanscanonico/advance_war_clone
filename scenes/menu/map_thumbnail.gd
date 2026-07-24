class_name MapThumbnail
extends Control
## Draws a MapData as a miniature board by blitting the terrain atlas per cell —
## column from TerrainType.atlas_col, row from SideIdentity.atlas_row, the exact
## authorities BattleView paints the live board with (menu-revamp plan D5).
##
## No symbol table, no per-terrain colour list, no second opinion (plan R2): there
## is only one of it, so a new terrain lands here for free and the miniature can
## never drift from the board it launches — the range-overlay-vs-command bug,
## closed by construction. Owned properties draw in the resolved faction's row, so
## a thumbnail is a truthful miniature of day one.
##
## The same per-cell region logic serves two masters: `_draw` paints a live cell
## for the picker, and the static `bake()` renders the panning backdrop to an
## ImageTexture — one renderer, so the field behind the menu and the thumbnails in
## front of it agree by definition.

## Atlas cell size, mirroring BattleView.TERRAIN_PX and the art pipeline. The
## atlas is 14 columns x 5 rows of these; the row order is SideIdentity's.
const CELL := 64
const _ATLAS_PATH := "res://assets/tiles/terrain_atlas.png"

static var _atlas: Texture2D
static var _atlas_image: Image

var _map: MapData
var _identity: SideIdentity
var _tile := 4
var _origin := Vector2.ZERO


## Points the thumbnail at a board and fits it, centred, into `box` (canvas px).
## The tile size is the largest whole-pixel size that keeps the whole board inside
## the box, so different-shaped boards all sit in an identical cell.
func setup(map: MapData, identity: SideIdentity, box: Vector2) -> void:
	_map = map
	_identity = identity
	custom_minimum_size = box
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if map == null:
		queue_redraw()
		return
	_tile = maxi(1, floori(minf(box.x / map.width, box.y / map.height)))
	var drawn := Vector2(map.width * _tile, map.height * _tile)
	_origin = ((box - drawn) / 2.0).floor()
	queue_redraw()


func _draw() -> void:
	if _map == null:
		return
	var atlas := _atlas_texture()
	for y in _map.height:
		for x in _map.width:
			var cell := Vector2i(x, y)
			var terrain := _map.terrain_at(cell)
			var src := _region(terrain.atlas_col, _row_for(_map, _identity, terrain, cell))
			var dst := Rect2(_origin + Vector2(x * _tile, y * _tile), Vector2(_tile, _tile))
			draw_texture_rect_region(atlas, dst, src)


# --- the one renderer, shared by the live draw and the baked backdrop ---------


## Bakes a board to an ImageTexture at `tile` px per cell: paints it at full atlas
## resolution, then resizes down with nearest-neighbour so it stays crisp. This is
## the panning field behind the menu (plan MN2), and it is the same per-cell
## region logic `_draw` uses, so the backdrop cannot disagree with a thumbnail.
static func bake(map: MapData, identity: SideIdentity, tile: int) -> ImageTexture:
	var atlas := _atlas_source_image()
	var full := Image.create(map.width * CELL, map.height * CELL, false, Image.FORMAT_RGBA8)
	for y in map.height:
		for x in map.width:
			var cell := Vector2i(x, y)
			var terrain := map.terrain_at(cell)
			var region := _region(terrain.atlas_col, _row_for(map, identity, terrain, cell))
			full.blit_rect(
				atlas, Rect2i(region.position, region.size), Vector2i(x * CELL, y * CELL)
			)
	full.resize(map.width * tile, map.height * tile, Image.INTERPOLATE_NEAREST)
	return ImageTexture.create_from_image(full)


## The atlas row a cell draws in: a team-tinted property takes its owner's
## resolved faction row, everything else the neutral row 0 — SideIdentity's call,
## never the owner int (BattleView's exact rule).
static func _row_for(
	map: MapData, identity: SideIdentity, terrain: TerrainType, cell: Vector2i
) -> int:
	if terrain.team_tinted and identity != null:
		return identity.atlas_row(map.owner_at(cell))
	return 0


static func _region(col: int, row: int) -> Rect2:
	return Rect2(col * CELL, row * CELL, CELL, CELL)


static func _atlas_texture() -> Texture2D:
	if _atlas == null:
		_atlas = load(_ATLAS_PATH)
	return _atlas


## The atlas as a mutable RGBA8 Image, decompressed once for `bake`'s blits.
static func _atlas_source_image() -> Image:
	if _atlas_image == null:
		_atlas_image = _atlas_texture().get_image()
		if _atlas_image.get_format() != Image.FORMAT_RGBA8:
			_atlas_image.convert(Image.FORMAT_RGBA8)
	return _atlas_image
