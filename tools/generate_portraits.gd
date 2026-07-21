extends SceneTree
## Generates placeholder commander portraits and faction emblems, one 256x256
## bust per general plus a neutral silhouette and four 64x64 emblems.
##
## These are deliberately *placeholders*: the readiness plan's D1 makes the
## supplied Claude card sheet the production source, but the plan is equally
## explicit that placeholder exports unblock the UI work so the final art pass
## never gates card, selection, or balance code. Everything here is generated
## from data (CC0, no third-party pixels), keyed to each commander's faction
## colour and to the mechanic-led visual cue the plan's roster table names — so a
## Meridian coordinator, an Iron veteran with an eyepatch, and an Aurora analyst
## in glasses stay distinguishable at HUD size until the real art lands.
##
## Faction colours are read from CommanderVisuals, the one authority on them, so
## the baked art and the UI that frames it can never disagree.  Run with:
##   make portraits    (headless, writes under assets/portraits/)

const PORTRAIT_PX := 256
const EMBLEM_PX := 64
const OUTLINE := Color(0.075, 0.094, 0.106)

## Mechanic-led accessory per commander (plan section 05). A small, honest nod to
## the production brief that also keeps the twelve busts apart at 24px.
const ACCESSORY := {
	&"alina_ward": &"none",
	&"gideon_holt": &"glasses",
	&"rhea_sol": &"goggles",
	&"cass_orlov": &"scar",
	&"mara_voss": &"collar",
	&"viktor_draeg": &"eyepatch",
	&"cassian_rook": &"none",
	&"lyra_quill": &"glasses",
	&"orin_flux": &"headset",
	&"nia_rowan": &"headband",
	&"sable_wren": &"hood",
	&"tomas_reed": &"none",
}

## Small skin and hair palettes; each commander draws a stable pair from its id
## hash so members of one faction still differ in more than their accessory.
const SKINS: Array[Color] = [
	Color(0.937, 0.741, 0.541),
	Color(0.855, 0.643, 0.463),
	Color(0.706, 0.502, 0.353),
	Color(0.549, 0.373, 0.259),
	Color(0.965, 0.816, 0.643),
]
const HAIRS: Array[Color] = [
	Color(0.180, 0.114, 0.075),
	Color(0.361, 0.220, 0.114),
	Color(0.106, 0.106, 0.118),
	Color(0.729, 0.678, 0.588),
	Color(0.545, 0.271, 0.176),
	Color(0.412, 0.412, 0.435),
]


func _init() -> void:
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(CommanderVisuals.PORTRAIT_DIR)
	)
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(CommanderVisuals.FACTION_DIR)
	)
	var db := CommanderDB.load_default()
	var count := 0
	for commander in db.all():
		var image := (
			_draw_neutral() if commander.id == CommanderType.NEUTRAL_ID else _draw_bust(commander)
		)
		var path := "%s/%s.png" % [CommanderVisuals.PORTRAIT_DIR, commander.id]
		image.save_png(ProjectSettings.globalize_path(path))
		count += 1
	for theme: CommanderVisuals.FactionTheme in CommanderVisuals.faction_themes():
		var emblem := _draw_emblem(theme)
		emblem.save_png(
			ProjectSettings.globalize_path("%s/%s.png" % [CommanderVisuals.FACTION_DIR, theme.key])
		)
	print("generate_portraits: wrote %d portraits and 4 emblems" % count)
	quit()


# --- portraits ---------------------------------------------------------------


func _draw_bust(commander: CommanderType) -> Image:
	var theme := CommanderVisuals.theme_for(commander)
	var seed_val := absi(hash(commander.id))
	var skin: Color = SKINS[seed_val % SKINS.size()]
	var hair: Color = HAIRS[(seed_val / 7) % HAIRS.size()]
	var accessory: StringName = ACCESSORY.get(commander.id, &"none")

	var img := Image.create(PORTRAIT_PX, PORTRAIT_PX, false, Image.FORMAT_RGBA8)
	_stripe_field(img, theme.color, theme.color_light)

	# Shoulders: a uniform-coloured mass rising from the bottom edge, dark contour
	# first so the fill reads as one silhouette.
	var uniform := theme.color_dark.lerp(Color.BLACK, 0.15)
	_disc(img, 128, 320, 118, 130, OUTLINE)
	_disc(img, 128, 322, 108, 122, uniform)
	if accessory == &"collar":
		_disc(img, 128, 236, 40, 46, uniform.lerp(Color.WHITE, 0.12))

	# Head + hair.
	_disc(img, 128, 104, 50, 58, OUTLINE)
	_disc(img, 128, 104, 45, 53, skin)
	_draw_hair(img, hair, accessory)

	# Eyes, then the identifying accessory over them.
	_disc(img, 110, 108, 6, 7, OUTLINE)
	_disc(img, 146, 108, 6, 7, OUTLINE)
	_draw_accessory(img, accessory, hair)

	_frame(img, theme.color_dark)
	return img


func _draw_hair(img: Image, hair: Color, accessory: StringName) -> void:
	if accessory == &"hood":
		return  # the hood covers the hairline; drawn as the accessory
	# A cap over the crown: a disc clipped to the top half of the head.
	for y in range(40, 108):
		for x in range(74, 182):
			var dx := (x - 128) / 58.0
			var dy := (y - 100) / 62.0
			if dx * dx + dy * dy <= 1.0 and y < 96:
				img.set_pixel(x, y, hair)
	if accessory == &"headband":
		_band(img, 60, 84, 136, 12, Color(0.831, 0.278, 0.243))


func _draw_accessory(img: Image, accessory: StringName, hair: Color) -> void:
	match accessory:
		&"glasses":
			_ring(img, 110, 108, 13, OUTLINE)
			_ring(img, 146, 108, 13, OUTLINE)
			_band(img, 123, 106, 10, 3, OUTLINE)
		&"goggles":
			_band(img, 78, 74, 100, 12, Color(0.235, 0.267, 0.290))
			_disc(img, 108, 80, 4, 4, Color(0.518, 0.780, 0.878))
			_disc(img, 148, 80, 4, 4, Color(0.518, 0.780, 0.878))
		&"headset":
			_band(img, 70, 60, 116, 8, Color(0.216, 0.235, 0.255))
			_disc(img, 74, 108, 12, 16, Color(0.216, 0.235, 0.255))
			_disc(img, 74, 108, 7, 10, Color(0.443, 0.478, 0.510))
		&"eyepatch":
			_disc(img, 146, 108, 13, 14, OUTLINE)
			_band(img, 90, 92, 84, 5, OUTLINE)
		&"scar":
			for i in 14:
				img.set_pixel(101 + i, 92 + i, Color(0.639, 0.302, 0.263))
		&"hood":
			_draw_hood(img, hair.lerp(OUTLINE, 0.5))


func _draw_hood(img: Image, cloth: Color) -> void:
	# A darker cowl framing the face: a disc behind the head, cut away where the
	# face shows.
	for y in range(30, 190):
		for x in range(58, 198):
			var dx := (x - 128) / 74.0
			var dy := (y - 110) / 84.0
			if dx * dx + dy * dy > 1.0:
				continue
			var fx := (x - 128) / 52.0
			var fy := (y - 104) / 58.0
			if fx * fx + fy * fy <= 1.0:
				continue  # keep the face clear
			img.set_pixel(x, y, cloth)


func _draw_neutral() -> Image:
	var theme := CommanderVisuals.theme_for_key(CommanderVisuals.NEUTRAL_KEY)
	var img := Image.create(PORTRAIT_PX, PORTRAIT_PX, false, Image.FORMAT_RGBA8)
	_stripe_field(img, theme.color, theme.color_light)
	var silhouette := theme.color_dark
	_disc(img, 128, 320, 112, 124, silhouette)
	_disc(img, 128, 104, 48, 56, silhouette)
	_frame(img, theme.color_dark.lerp(Color.BLACK, 0.2))
	return img


# --- emblems -----------------------------------------------------------------


func _draw_emblem(theme: CommanderVisuals.FactionTheme) -> Image:
	var img := Image.create(EMBLEM_PX, EMBLEM_PX, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := 32
	match theme.key:
		&"meridian":  # hollow diamond
			_diamond(img, c, c, 26, OUTLINE)
			_diamond(img, c, c, 21, theme.color)
			_diamond(img, c, c, 11, OUTLINE)
		&"iron":  # solid diamond
			_diamond(img, c, c, 26, OUTLINE)
			_diamond(img, c, c, 21, theme.color)
		&"aurora":  # four-point star
			_diamond(img, c, c, 27, OUTLINE)
			_diamond(img, c, c, 22, theme.color)
			_band(img, c - 3, 6, 6, 52, theme.color)
			_band(img, 6, c - 3, 52, 6, theme.color)
		&"verdant":  # pennant
			_band(img, 18, 8, 6, 48, OUTLINE)
			for y in range(10, 40):
				for x in range(24, 54):
					if (x - 24) < (54 - 24) - absi(y - 22) * 1:
						img.set_pixel(x, y, theme.color)
	return img


# --- primitives --------------------------------------------------------------


func _stripe_field(img: Image, a: Color, b: Color) -> void:
	for y in PORTRAIT_PX:
		for x in PORTRAIT_PX:
			img.set_pixel(x, y, a if ((x + y) / 14) % 2 == 0 else b)


## Fills the ellipse centred at (cx, cy) with radii (rx, ry), clipped to canvas.
func _disc(img: Image, cx: int, cy: int, rx: int, ry: int, color: Color) -> void:
	var w := img.get_width()
	var h := img.get_height()
	for y in range(maxi(0, cy - ry), mini(h, cy + ry + 1)):
		for x in range(maxi(0, cx - rx), mini(w, cx + rx + 1)):
			var dx := float(x - cx) / float(rx)
			var dy := float(y - cy) / float(ry)
			if dx * dx + dy * dy <= 1.0:
				img.set_pixel(x, y, color)


## A hollow ring of the given radius (for glasses).
func _ring(img: Image, cx: int, cy: int, r: int, color: Color) -> void:
	var w := img.get_width()
	var h := img.get_height()
	for y in range(maxi(0, cy - r), mini(h, cy + r + 1)):
		for x in range(maxi(0, cx - r), mini(w, cx + r + 1)):
			var d := Vector2(x - cx, y - cy).length()
			if d <= r and d >= r - 3:
				img.set_pixel(x, y, color)


func _band(img: Image, x: int, y: int, w: int, h: int, color: Color) -> void:
	var rect := Rect2i(x, y, w, h).intersection(Rect2i(0, 0, img.get_width(), img.get_height()))
	if rect.has_area():
		img.fill_rect(rect, color)


func _diamond(img: Image, cx: int, cy: int, r: int, color: Color) -> void:
	for y in range(maxi(0, cy - r), mini(img.get_height(), cy + r + 1)):
		for x in range(maxi(0, cx - r), mini(img.get_width(), cx + r + 1)):
			if absi(x - cx) + absi(y - cy) <= r:
				img.set_pixel(x, y, color)


## A 3px hard border in the faction's dark shade, echoing the card's chunky edge.
func _frame(img: Image, color: Color) -> void:
	var w := img.get_width()
	var h := img.get_height()
	for t in 3:
		for x in w:
			img.set_pixel(x, t, color)
			img.set_pixel(x, h - 1 - t, color)
		for y in h:
			img.set_pixel(t, y, color)
			img.set_pixel(w - 1 - t, y, color)
