class_name SaveMenu
extends Control
## The save menu (from Unity's SaveMenu; Esc when nothing else is open, and the game pauses while it's up): a new
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
	if SaveGame.testing() and Shots.arg("window") != "saves":
		return
	visible = true
	move_to_front()
	get_tree().paused = true
	_confirming = ""
	_renaming = ""
	_build()


func close() -> void:
	visible = false
	get_tree().paused = false


func _process(_delta: float) -> void:
	if not visible:
		return
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
	head.add_child(HudStyle.label("Game", 18, "pixel", HudStyle.color("accentLight")))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(gap)
	head.add_child(HudStyle.label("Esc  resume  ·  F5 quick save  ·  F8 quick load", 11, "bold", HudStyle.color("faint")))
	box.add_child(head)
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
	# New game, resume.
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
		var name := HudStyle.label(str(s.get("name", slot)), 14, "bold", HudStyle.color("accentLight") if slot in [SaveSystem.AUTO, SaveSystem.QUICK] else HudStyle.color("text"))
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(name)
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
