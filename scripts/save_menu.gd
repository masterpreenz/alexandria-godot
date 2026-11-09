class_name SaveMenu
extends Control
## Settings (Esc when nothing else is open; the game pauses while it's up), with two tabs. Display: the window's
## resolution, borderless fullscreen, the UI's size and the FPS meter. Saves (from Unity's SaveMenu): a new
## named save at the top; below it every save, the autosave and quick save first, each with what it was (season, day,
## time, level, place), when it was made and how long was played, and Load, Save over, Rename and Delete. Loading,
## saving over, deleting and starting a new game ask once more ("Sure?") before they happen.

const W := 520.0

var saving: SaveGame
var _panel: PanelContainer
var _list: VBoxContainer
var _name: LineEdit
var _confirming := ""       ## "load:slot", "save:slot", "delete:slot" or "new" awaiting a second click
var _confirm_until := 0.0
var _renaming := ""
var tab := "Saves"


func setup(s: SaveGame) -> void:
	saving = s
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.03, 0.03, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", HudStyle.piece("panelStrong"))
	_panel.custom_minimum_size.x = W * HudStyle.SCALE
	add_child(_panel)
	# Esc is heard last of all (first in the scene), so the windows it closes get it first.
	var ear := Ear.new()
	ear.menu = self
	ear.process_mode = Node.PROCESS_MODE_ALWAYS
	s.game.add_child(ear)
	s.game.move_child(ear, 0)


func _k(v: float) -> float:
	return v * HudStyle.SCALE


func open() -> void:
	visible = true
	move_to_front()
	get_tree().paused = true
	_confirming = ""
	_renaming = ""
	_build()


func close() -> void:
	visible = false
	get_tree().paused = false


func _process(delta: float) -> void:
	var __t := Time.get_ticks_usec()
	_process_timed(delta)
	Perf.add(&"save_menu.process", __t)


func _process_timed(_delta: float) -> void:
	if not visible:
		return
	position = Vector2.ZERO
	size = get_viewport_rect().size
	_panel.reset_size()
	_panel.position = ((get_viewport_rect().size - _panel.size) / 2.0).round()
	if _confirming != "" and Time.get_ticks_msec() / 1000.0 > _confirm_until:
		_confirming = ""
		_build()


func _build() -> void:
	for ch in _panel.get_children():
		_panel.remove_child(ch)
		ch.queue_free()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(_k(8)))
	_panel.add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", int(_k(8)))
	head.add_child(HudStyle.label("Settings", 18, "pixel", HudStyle.color("accentLight")))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(gap)
	for t in ["Saves", "Display", "Sound"]:
		var b := _button(t, t == tab)
		b.pressed.connect(_set_tab.bind(t))
		head.add_child(b)
	box.add_child(head)
	box.add_child(HudStyle.label("Esc  resume  ·  F5 quick save  ·  F8 quick load", 11, "bold", HudStyle.color("faint")))
	if tab == "Display":
		_display(box)
		_footer(box)
		return
	if tab == "Sound":
		_sound(box)
		_footer(box)
		return
	# A new named save.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(_k(6)))
	_name = LineEdit.new()
	_name.placeholder_text = "Name a new save (optional)"
	_name.max_length = 32
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name.custom_minimum_size.y = _k(30)
	_name.add_theme_stylebox_override("normal", HudStyle.piece("well"))
	_name.add_theme_stylebox_override("focus", HudStyle.piece("well"))
	_name.add_theme_font_size_override("font_size", roundi(_k(12)))
	_name.text_submitted.connect(func(_t): _new_save())
	row.add_child(_name)
	var save := _button("Save", true)
	save.pressed.connect(_new_save)
	row.add_child(save)
	box.add_child(row)
	# Every save.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = _k(360)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", int(_k(6)))
	scroll.add_child(_list)
	box.add_child(scroll)
	var saves := SaveSystem.list()
	if saves.is_empty():
		_list.add_child(HudStyle.label("No saves yet.", 12, "body", HudStyle.color("muted")))
	for e in saves:
		_list.add_child(_save_row(e[0], e[1]))
	_footer(box)


func _set_tab(t: String) -> void:
	tab = t
	_confirming = ""
	_renaming = ""
	_build()


# New game, save and quit, resume.
func _footer(box: VBoxContainer) -> void:
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", int(_k(8)))
	var fresh := _button("Sure? New game" if _confirming == "new" else "New game", false, _confirming == "new")
	fresh.pressed.connect(func(): _confirm("new", func(): saving.new_game()))
	foot.add_child(fresh)
	var g2 := Control.new()
	g2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(g2)
	var quit := _button("Save and quit", false)
	quit.pressed.connect(func():
		saving.save(SaveSystem.AUTO, true)
		get_tree().quit())
	foot.add_child(quit)
	var resume := _button("Resume", true)
	resume.pressed.connect(close)
	foot.add_child(resume)
	box.add_child(foot)


func _button(text: String, main: bool, warn := false) -> Button:
	@warning_ignore("incompatible_ternary")
	var b := HudStyle.button(text, 12, "barFill" if main or warn else "pill", HudStyle.color("ink") if main or warn else null)
	if main:
		b.add_theme_stylebox_override("normal", HudStyle.piece("barFill", HudStyle.color("accent")))
		b.add_theme_stylebox_override("hover", HudStyle.piece("barFill", HudStyle.color("accentLight")))
	if warn:
		b.add_theme_stylebox_override("normal", HudStyle.piece("barFill", HudStyle.color("coral")))
		b.add_theme_stylebox_override("hover", HudStyle.piece("barFill", HudStyle.color("coral")))
	b.custom_minimum_size.y = _k(28)
	return b


static func _played(seconds: float) -> String:
	var m := int(seconds / 60.0)
	@warning_ignore("integer_division")
	return "%dh %02dm played" % [m / 60, m % 60] if m >= 60 else "%dm played" % m


# When it was saved, in the player's own time.
static func _when(iso: String) -> String:
	if iso.length() < 19:
		return ""
	var unix := Time.get_unix_time_from_datetime_string(iso.left(19))
	unix += Time.get_time_zone_from_system().bias * 60
	var d := Time.get_datetime_dict_from_unix_time(int(unix))
	var months := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	return "%d %s, %02d:%02d" % [d.day, months[d.month - 1], d.hour, d.minute]


func _save_row(slot: String, s: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", HudStyle.piece("well"))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", int(_k(2)))
	card.add_child(col)
	var top := HBoxContainer.new()
	if _renaming == slot:
		var field := LineEdit.new()
		field.text = str(s.get("name", ""))
		field.max_length = 32
		field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		field.add_theme_font_size_override("font_size", roundi(_k(13)))
		field.text_submitted.connect(func(t: String):
			SaveSystem.rename(slot, t)
			_renaming = ""
			_build())
		top.add_child(field)
		field.call_deferred("grab_focus")
	else:
		var nm := HudStyle.label(str(s.get("name", slot)), 14, "bold", HudStyle.color("accentLight") if slot in [SaveSystem.AUTO, SaveSystem.QUICK] else HudStyle.color("text"))
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(nm)
	top.add_child(HudStyle.label(_when(str(s.get("savedAt", ""))), 11, "bold", HudStyle.color("faint")))
	col.add_child(top)
	col.add_child(HudStyle.label("%s, day %d · %s · Lv %d · %s · %s" % [s.get("season", ""), int(s.get("day", 1)), s.get("time", ""), int(s.get("level", 1)),
		s.get("place", ""), _played(float(s.get("playSeconds", 0.0)))], 11, "bold", HudStyle.color("muted")))
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", int(_k(6)))
	for act in [["load", "Load"], ["save", "Save over"], ["rename", "Rename"], ["delete", "Delete"]]:
		var key: String = act[0] + ":" + slot
		var sure := _confirming == key
		var b := _button("Sure?" if sure else act[1], act[0] == "load" and not sure, sure)
		b.pressed.connect(_act.bind(act[0], slot))
		buttons.add_child(b)
	col.add_child(buttons)
	return card


func _confirm(key: String, then: Callable) -> void:
	if _confirming == key:
		_confirming = ""
		then.call()
		return
	_confirming = key
	_confirm_until = Time.get_ticks_msec() / 1000.0 + 3.0
	_build()


func _act(what: String, slot: String) -> void:
	match what:
		"load": _confirm("load:" + slot, func(): saving.load_slot(slot))
		"save": _confirm("save:" + slot, func():
			saving.save(slot)
			_build())
		"delete": _confirm("delete:" + slot, func():
			SaveSystem.delete(slot)
			_build())
		"rename":
			_renaming = slot
			_build()


func _new_save() -> void:
	if saving.save(SaveSystem.new_slot(), false, _name.text):
		_name.text = ""
		_build()


# ---- Display ----

func _display(box: VBoxContainer) -> void:
	var well := PanelContainer.new()
	well.add_theme_stylebox_override("panel", HudStyle.piece("well"))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", int(_k(12)))
	well.add_child(col)
	box.add_child(well)
	# Window: windowed at a size, or borderless fullscreen.
	var r := _row("Window")
	r.add_child(_choice("Windowed", not Settings.borderless, _set_borderless.bind(false)))
	r.add_child(_choice("Borderless fullscreen", Settings.borderless, _set_borderless.bind(true)))
	col.add_child(r)
	r = _row("Resolution")
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", int(_k(6)))
	flow.add_theme_constant_override("v_separation", int(_k(6)))
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for res in Settings.resolutions():
		flow.add_child(_choice("%d × %d" % [res.x, res.y], Settings.resolution == res and not Settings.borderless, _set_resolution.bind(res)))
	r.add_child(flow)
	col.add_child(r)
	r = _row("UI size")
	for s in Settings.UI_SIZES:
		r.add_child(_choice("%d%%" % roundi(s * 100), is_equal_approx(Settings.ui_size, s), _set_ui_size.bind(s)))
	col.add_child(r)
	r = _row("Picture")
	r.add_child(_choice("Soft", Settings.soft_picture, _set_picture.bind(true)))
	r.add_child(_choice("Vivid", not Settings.soft_picture, _set_picture.bind(false)))
	col.add_child(r)
	r = _row("FPS meter")
	r.add_child(_choice("Show", Settings.show_fps, _set_fps.bind(true)))
	r.add_child(_choice("Hide", not Settings.show_fps, _set_fps.bind(false)))
	col.add_child(r)
	col.add_child(HudStyle.label("Changing the UI size picks the game up again from where it is.", 11, "body", HudStyle.color("faint")))


func _set_borderless(on: bool) -> void:
	Settings.borderless = on
	_apply()


func _set_resolution(res: Vector2i) -> void:
	Settings.resolution = res
	Settings.borderless = false
	_apply()


func _set_picture(soft: bool) -> void:
	Settings.soft_picture = soft
	Settings.apply_picture()
	Settings.save_settings()
	_build()


func _set_fps(on: bool) -> void:
	Settings.show_fps = on
	Settings.save_settings()
	_build()


# The HUD is laid out at its size as the game starts: carried on from here (an autosave), at the new size.
func _set_ui_size(s: float) -> void:
	if is_equal_approx(Settings.ui_size, s):
		return
	Settings.ui_size = s
	Settings.save_settings()
	close()
	var saved := saving.save(SaveSystem.AUTO, true)
	saving.restart(SaveSystem.AUTO if saved or SaveSystem.exists(SaveSystem.AUTO) else SaveSystem.loaded_slot)


# ---- Sound ----

func _sound(box: VBoxContainer) -> void:
	var well := PanelContainer.new()
	well.add_theme_stylebox_override("panel", HudStyle.piece("well"))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", int(_k(14)))
	well.add_child(col)
	box.add_child(well)
	for v in [["Master", "master"], ["Sound effects", "sfx"], ["Music", "bgm"]]:
		var r := _row(v[0])
		var slider := HSlider.new()
		slider.min_value = 0
		slider.max_value = 100
		slider.step = 5
		slider.value = roundi(Settings.volume(v[1]) * 100.0)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slider.custom_minimum_size.x = _k(240)
		var value := HudStyle.label("%d%%" % roundi(slider.value), 12, "pixel")
		value.custom_minimum_size.x = _k(48)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		slider.value_changed.connect(_set_volume.bind(v[1], value))
		r.add_child(slider)
		r.add_child(value)
		col.add_child(r)
	col.add_child(HudStyle.label("There's no music yet: its volume is kept for when there is.", 11, "body", HudStyle.color("faint")))


func _set_volume(v: float, which: String, value: Label) -> void:
	Settings.set_volume(which, v / 100.0)
	value.text = "%d%%" % roundi(v)


func _row(title: String) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", int(_k(6)))
	var l := HudStyle.label(title, 13, "bold", HudStyle.color("muted"))
	l.custom_minimum_size.x = _k(110)
	r.add_child(l)
	return r


func _choice(text: String, on: bool, act: Callable) -> Button:
	var b := _button(text, on)
	b.custom_minimum_size.y = _k(28)
	b.pressed.connect(act)
	return b


func _apply() -> void:
	Settings.save_settings()
	Settings.apply_window()
	_build()


## Hears Esc after everything else (it stands first in the scene): opens or closes the menu.
class Ear extends Node:
	var menu: SaveMenu

	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
			if menu.visible:
				if menu._renaming != "":
					menu._renaming = ""
					menu._build()
				else:
					menu.close()
			elif not BuildMode.is_open() and not CharacterPanel.up():
				menu.open()
			get_viewport().set_input_as_handled()
