class_name CommanderSelectPanel
extends Control
## The dedicated commander selection page (readiness plan G2). Shown over the
## main menu without tearing it down, so the map, fog, and mode choices behind it
## survive a Back. The player edits Red, confirms, edits Blue, confirms, and only
## then are both ids handed back for the match — nothing reaches MatchConfig until
## both sides are locked.
##
## One focused CommanderCard carries the full doctrine and power copy; four
## faction tabs and three peer portraits let the player browse, and a deliberate
## "No Commander" stays reachable. Every widget is a focusable Control, so mouse,
## keyboard, and controller all drive it through Godot's own focus navigation:
## Left/Right across a row, Up/Down between the tab, portrait, and button rows.
## No information hides behind hover, and none behind colour alone — the emblem
## and faction name back every tint.
##
## Pure presentation: it reads CommanderDB to list the roster and emits the two
## chosen ids. It never starts the battle or touches core/.

signal confirmed(red_id: StringName, blue_id: StringName)
signal cancelled

enum Side { RED, BLUE }

const _TITLE_SIZE := 15
const _MINI_H := 82
## The selection accent, kept through the alignment pass (menu-revamp D6): gold is
## this page's own signal for "locked", distinct from the faction fills.
const GOLD := Color(0.957, 0.745, 0.196)
## The private slate/muted palette swaps for the shared UiTheme tokens it already
## sat a shade from, so the select page and the menu speak one grey (plan MN3).
const _INACTIVE := UiTheme.SLATE_800
const _MUTED := UiTheme.NEUTRAL_LIGHT

var _db: CommanderDB
## faction key -> Array[CommanderType], the three members in name order.
var _by_faction: Dictionary = {}
var _faction_keys: Array[StringName] = []

var _one_player := true
var _side := Side.RED
var _red_id: StringName = CommanderType.NEUTRAL_ID
var _blue_id: StringName = CommanderType.NEUTRAL_ID
## The commander currently previewed (not yet locked) for the active side.
var _current: CommanderType
var _faction_index := 0

var _card: CommanderCard
var _red_chip: PanelContainer
var _red_chip_label: Label
var _blue_chip: PanelContainer
var _blue_chip_label: Label
var _tab_buttons: Array[Button] = []
var _mini_buttons: Array[Button] = []
var _mini_marks: Array[ColorRect] = []
var _summary_label: Label
var _confirm_button: Button
var _back_button: Button
var _no_co_button: Button


func _ready() -> void:
	_db = CommanderDB.load_default()
	_group_roster()
	_build()
	hide()


## Groups every non-neutral commander under its faction key, keeping CommanderDB's
## faction-then-name order so the tabs and peer rows are stable.
func _group_roster() -> void:
	for theme: CommanderVisuals.FactionTheme in CommanderVisuals.faction_themes():
		_faction_keys.append(theme.key)
		_by_faction[theme.key] = [] as Array[CommanderType]
	for commander in _db.all():
		if commander.id == CommanderType.NEUTRAL_ID:
			continue
		var key := CommanderVisuals.key_for_faction(commander.faction)
		if _by_faction.has(key):
			_by_faction[key].append(commander)


## Opens the page for a fresh pair of picks. `one_player` only changes how the
## opponent slot is labelled (CPU vs Player 2); both sides are chosen here.
func begin(one_player: bool) -> void:
	_one_player = one_player
	_side = Side.RED
	_red_id = CommanderType.NEUTRAL_ID
	_blue_id = CommanderType.NEUTRAL_ID
	show()
	_refresh_chips()
	_set_faction(0)
	_grab_first_mini()


## Dev capture only: locks the current Red preview and advances to the Blue slot,
## so a screenshot can prove the confirm → Blue transition and the chip/summary
## update. Drives the same _confirm the Confirm button does. Not on any play path.
func debug_advance_to_blue() -> void:
	_confirm()


# --- build -------------------------------------------------------------------


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(UiTheme.SLATE_900.r, UiTheme.SLATE_900.g, UiTheme.SLATE_900.b, 0.985)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 10)
	add_child(margin)

	var main := VBoxContainer.new()
	main.add_theme_constant_override("separation", 6)
	margin.add_child(main)

	main.add_child(_build_topbar())

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_child(body)

	_card = CommanderCard.new()
	_card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	body.add_child(_card)

	body.add_child(_build_right_column())

	# The control legend in Silkscreen — a key-hint badge is the textbook home for
	# the design system's stat face, and it brings the second font onto the page.
	var footer := Label.new()
	footer.add_theme_font_override("font", UiTheme.stat())
	footer.add_theme_font_size_override("font_size", 8)
	footer.add_theme_color_override("font_color", UiTheme.NEUTRAL_LIGHT)
	footer.text = "ARROWS / TAB  BROWSE      ENTER  CONFIRM      ESC  BACK      MOUSE OK"
	main.add_child(footer)


func _build_topbar() -> HBoxContainer:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)

	var title := Label.new()
	title.text = "SELECT COMMANDER"
	title.add_theme_font_override("font", UiTheme.display(true))
	title.add_theme_font_size_override("font_size", _TITLE_SIZE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(title)

	_red_chip = PanelContainer.new()
	_red_chip_label = _small_label(9)
	_red_chip.add_child(_pad(_red_chip_label, 7, 3))
	bar.add_child(_red_chip)

	_blue_chip = PanelContainer.new()
	_blue_chip_label = _small_label(9)
	_blue_chip.add_child(_pad(_blue_chip_label, 7, 3))
	bar.add_child(_blue_chip)
	return bar


func _build_right_column() -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	for i in _faction_keys.size():
		var theme := CommanderVisuals.theme_for_key(_faction_keys[i])
		var tab := Button.new()
		tab.text = String(theme.key).capitalize()
		tab.add_theme_font_override("font", UiTheme.display())
		tab.add_theme_font_size_override("font_size", 10)
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.focus_entered.connect(_set_faction.bind(i))
		tab.pressed.connect(_focus_faction.bind(i))
		tabs.add_child(tab)
		_tab_buttons.append(tab)
	col.add_child(tabs)

	var mini_row := HBoxContainer.new()
	mini_row.name = "MiniRow"
	mini_row.add_theme_constant_override("separation", 6)
	mini_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(mini_row)

	var summary := PanelContainer.new()
	summary.add_theme_stylebox_override("panel", _flat(Color(0.145, 0.165, 0.180)))
	summary.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_summary_label = _small_label(10)
	_summary_label.add_theme_color_override("font_color", Color(0.741, 0.765, 0.780))
	_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.add_child(_pad(_summary_label, 8, 6))
	col.add_child(summary)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	_no_co_button = _action_button("No Commander")
	_no_co_button.focus_entered.connect(_preview_neutral)
	_no_co_button.pressed.connect(_lock_neutral)
	actions.add_child(_no_co_button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(spacer)
	_back_button = _action_button("Back")
	_back_button.pressed.connect(_back)
	actions.add_child(_back_button)
	_confirm_button = _action_button("Confirm Pick")
	_confirm_button.pressed.connect(_confirm)
	actions.add_child(_confirm_button)
	col.add_child(actions)
	return col


## The three footer actions wear the shared cream button — hard shadow, press-down,
## hover brighten, all from UiTheme's one implementation, so a press feels the same
## here as on the menu (plan MN3).
func _action_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	UiTheme.apply_button(button, UiTheme.ButtonVariant.SECONDARY, null, 10)
	return button


# --- roster navigation -------------------------------------------------------


## Switches the active faction and previews its first member. Does not move focus,
## so arrowing Left/Right across the tab row browses factions cleanly.
func _set_faction(index: int) -> void:
	_faction_index = index
	for i in _tab_buttons.size():
		_style_tab(_tab_buttons[i], i == index)
	_rebuild_minis()
	if not _members().is_empty():
		_preview(_members()[0])


## A mouse click on a tab switches faction and drops focus onto the first peer,
## so the click lands somewhere sensible for the keyboard to continue from.
func _focus_faction(index: int) -> void:
	_set_faction(index)
	_grab_first_mini()


func _members() -> Array:
	return _by_faction.get(_faction_keys[_faction_index], [])


## Deferred: freshly-created buttons are not in the focus system until the frame
## settles, so an immediate grab_focus is a no-op and the viewport falls back to
## focusing the first tab. Deferring lands focus on the portrait, as intended.
func _grab(button: Control) -> void:
	if button != null:
		button.grab_focus.call_deferred()


func _grab_first_mini() -> void:
	if not _mini_buttons.is_empty():
		_grab(_mini_buttons[0])


func _rebuild_minis() -> void:
	var row := _mini_buttons[0].get_parent() if not _mini_buttons.is_empty() else _find_mini_row()
	for button in _mini_buttons:
		button.free()  # immediate, never called from a mini's own callback
	_mini_buttons.clear()
	_mini_marks.clear()
	for commander: CommanderType in _members():
		var mini := _make_mini(commander, row)
		_mini_buttons.append(mini)


func _find_mini_row() -> HBoxContainer:
	return find_child("MiniRow", true, false) as HBoxContainer


func _make_mini(commander: CommanderType, row: HBoxContainer) -> Button:
	var theme := CommanderVisuals.theme_for(commander)
	var button := Button.new()
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(0, _MINI_H)
	button.clip_contents = true
	button.add_theme_stylebox_override("normal", _hard(theme.color_dark, 2))
	button.add_theme_stylebox_override("hover", _hard(theme.color, 2))
	button.add_theme_stylebox_override("focus", _hard(GOLD, 2))
	button.add_theme_stylebox_override("pressed", _hard(GOLD, 2))
	row.add_child(button)

	var content := VBoxContainer.new()
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.add_theme_constant_override("separation", 0)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(content)

	var stage := Panel.new()
	stage.add_theme_stylebox_override("panel", _flat(theme.color))
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.clip_contents = true
	content.add_child(stage)
	var portrait := TextureRect.new()
	portrait.texture = CommanderVisuals.portrait_for(commander)
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait.set_anchors_preset(Control.PRESET_FULL_RECT)
	stage.add_child(portrait)

	var name_label := _small_label(8)
	name_label.text = commander.display_name
	name_label.add_theme_color_override("font_color", theme.ink)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var name_wrap := PanelContainer.new()
	name_wrap.add_theme_stylebox_override("panel", _flat(theme.color_dark))
	name_wrap.add_child(_pad(name_label, 2, 1))
	content.add_child(name_wrap)

	var mark := ColorRect.new()
	mark.color = GOLD
	mark.anchor_left = 1.0
	mark.anchor_right = 1.0
	mark.offset_left = -13.0
	mark.offset_top = 3.0
	mark.offset_right = -3.0
	mark.offset_bottom = 13.0
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.visible = false
	button.add_child(mark)
	_mini_marks.append(mark)

	button.focus_entered.connect(_preview.bind(commander))
	button.pressed.connect(_preview.bind(commander))
	return button


func _preview(commander: CommanderType) -> void:
	_current = commander
	_card.bind(commander)
	for i in _mini_buttons.size():
		_mini_marks[i].visible = _members()[i].id == commander.id
	_refresh_summary()
	_refresh_chips()  # the active side's chip tracks the browse, mirror fallback and all


func _preview_neutral() -> void:
	_preview(CommanderType.neutral())


# --- confirm / back ----------------------------------------------------------


func _confirm() -> void:
	if _current == null:
		return
	if _side == Side.RED:
		_red_id = _current.id
		_side = Side.BLUE
		_refresh_chips()
		_set_faction(0)
		_grab_first_mini()
	else:
		_blue_id = _current.id
		confirmed.emit(_red_id, _blue_id)


## The "No Commander" shortcut: locks neutral for the active side straight away —
## the same as previewing it and pressing Confirm.
func _lock_neutral() -> void:
	_preview_neutral()
	_confirm()


func _back() -> void:
	if _side == Side.BLUE:
		_side = Side.RED  # return to editing Red, restoring the locked pick
		_refresh_chips()
		_focus_commander(_red_id)
	else:
		hide()
		cancelled.emit()


func _shortcut_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		_back()
		accept_event()


## Moves the tab/preview/focus to a specific commander id (used when Back restores
## the Red pick). Neutral falls through to the first faction's first member.
func _focus_commander(id: StringName) -> void:
	var commander := _db.by_id(id)
	if commander.id == CommanderType.NEUTRAL_ID:
		_set_faction(0)
		_grab_first_mini()
		return
	var key := CommanderVisuals.key_for_faction(commander.faction)
	var index := _faction_keys.find(key)
	_set_faction(index if index >= 0 else 0)
	for i in _members().size():
		if _members()[i].id == id and i < _mini_buttons.size():
			_grab(_mini_buttons[i])
			return
	_grab_first_mini()


# --- chrome refresh ----------------------------------------------------------


## The two turn chips, live from the picks as they stand. Side 1 is always
## relevant — being edited or already locked — so it stays filled and shows its
## faction; side 2 fills only while it is the side in hand, and the moment both
## land on one faction it shows the borrowed classic (D3), not a day-1 surprise.
func _refresh_chips() -> void:
	var identity := _preview_identity()
	_paint_chip(
		_red_chip, _red_chip_label, "1 · %s — You" % identity.display_name(1), identity.theme(1)
	)
	var opponent := "CPU" if _one_player else "Player 2"
	if _side == Side.BLUE:
		var label := "2 · %s — %s" % [identity.display_name(2), opponent]
		_paint_chip(_blue_chip, _blue_chip_label, label, identity.theme(2))
	else:
		_paint_chip(_blue_chip, _blue_chip_label, "2 · %s" % opponent, null)


## The identity the current picks would produce: the locked or previewed side 1,
## and the previewed side 2 once it is being edited. Resolving the whole thing
## rather than each chip alone is what lets the mirror fallback show live.
func _preview_identity() -> SideIdentity:
	var one: CommanderType = _current if _side == Side.RED else _db.by_id(_red_id)
	var two: CommanderType = _current if _side == Side.BLUE else null
	return SideIdentity.resolve({1: one, 2: two})


## Fills a chip in a side's theme, or greys it (theme null) when the side is not
## yet in hand.
func _paint_chip(
	chip: PanelContainer, label: Label, text: String, theme: CommanderVisuals.FactionTheme
) -> void:
	chip.add_theme_stylebox_override("panel", _flat(theme.color if theme != null else _INACTIVE))
	label.add_theme_color_override("font_color", theme.ink if theme != null else _MUTED)
	label.text = text


func _refresh_summary() -> void:
	var slot := "Side 1" if _side == Side.RED else "Side 2"
	var text := "%s — browse a faction, then Confirm." % slot
	if _current != null:
		var theme := CommanderVisuals.theme_for(_current)
		text = "%s · %s\nSelected: %s." % [slot, theme.display, _current.display_name]
	if _side == Side.BLUE:
		text += "  Side 1 is locked in %s." % _db.by_id(_red_id).display_name
	_summary_label.text = text


func _style_tab(tab: Button, active: bool) -> void:
	var theme := CommanderVisuals.theme_for_key(_faction_keys[_tab_buttons.find(tab)])
	tab.add_theme_stylebox_override("normal", _hard(theme.color if active else _INACTIVE, 2))
	tab.add_theme_stylebox_override("hover", _hard(theme.color_light if active else theme.color, 2))
	tab.add_theme_stylebox_override("focus", _hard(GOLD, 2))
	tab.add_theme_stylebox_override("pressed", _hard(theme.color, 2))
	tab.add_theme_color_override(
		"font_color", Color.WHITE if active else Color(0.753, 0.776, 0.792)
	)


# --- style helpers -----------------------------------------------------------


func _small_label(size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_override("font", UiTheme.display())
	label.add_theme_font_size_override("font_size", size)
	return label


func _pad(child: Control, h: int, v: int) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", h)
	margin.add_theme_constant_override("margin_right", h)
	margin.add_theme_constant_override("margin_top", v)
	margin.add_theme_constant_override("margin_bottom", v)
	margin.add_child(child)
	return margin


func _flat(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	return box


func _hard(border: Color, width: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = _INACTIVE
	box.border_color = border
	box.set_border_width_all(width)
	box.content_margin_left = 4
	box.content_margin_right = 4
	box.content_margin_top = 2
	box.content_margin_bottom = 2
	# The signature hard offset shadow, from the one authority (plan MN3).
	return UiTheme.hard_shadow(box)
