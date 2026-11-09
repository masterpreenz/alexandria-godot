class_name Hotbar
extends Control
## The hotbar at the bottom of the screen (from Unity's Hotbar), in the dark-ink HUD: rows of eight slots (one to three,
## set with the + and − on its left) and beside it the Bag (I) and Character (C) buttons. Row one is on keys 1-8, row
## two Shift+1-8, row three Ctrl+1-8. A slot holds a skill (it aims, or casts on oneself) or something to eat or drink
## (pressing it eats one; the slot shows how many are carried). Clicking a slot opens a picker of every known skill and
## every food and drink to choose what goes there, or to empty it. Skill slots show their mana cost, darken with a
## sweep while cooling down, grey out without enough mana and ring amber while being aimed; hovering one tells about
## it. A newly known skill drops into the first free slot, and one no longer known is taken off.

const CELL := 46.0
const GAP := 6.0
const PAD := 8.0
const COLUMNS := 8
const MAX_ROWS := 3

var world: World
var caster: SpellCaster
var bag: Bag
var stats: CharacterStats
var panel: CharacterPanel
var slots: Array = []    ## "spell:Name", "food:Resource" or ""
var rows := 1
var picking := -1
var hovered := -1
var _offered := {}
var _bar: PanelContainer
var _grid: GridContainer
var _cells: Array = []
var _side: VBoxContainer
var _picker: PanelContainer
var _tip: PanelContainer
var _tip_text: RichTextLabel
var _known_key := ""


func _k(v: float) -> float:
	return v * HudStyle.SCALE


func setup(w: World, c: SpellCaster, b: Bag, st: CharacterStats) -> void:
	world = w
	caster = c
	bag = b
	stats = st
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	slots.resize(COLUMNS * MAX_ROWS)
	slots.fill("")
	var row := HBoxContainer.new()
	row.name = "Row"
	row.add_theme_constant_override("separation", int(_k(6)))
	add_child(row)
	# The rows' + and −.
	_side = VBoxContainer.new()
	_side.alignment = BoxContainer.ALIGNMENT_END
	for t in ["+", "−"]:
		var btn := HudStyle.button(t, 13, "pill")
		btn.custom_minimum_size = Vector2(_k(30), _k(26))
		btn.pressed.connect(_rows_by.bind(1 if t == "+" else -1))
		_side.add_child(btn)
	row.add_child(_side)
	_bar = PanelContainer.new()
	_bar.add_theme_stylebox_override("panel", HudStyle.piece("panel"))
	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", int(_k(GAP)))
	_grid.add_theme_constant_override("v_separation", int(_k(GAP)))
	_bar.add_child(_grid)
	row.add_child(_bar)
	for i in COLUMNS * MAX_ROWS:
		var cell := HotCell.new()
		cell.bar = self
		cell.index = i
		cell.custom_minimum_size = Vector2(_k(CELL), _k(CELL))
		_grid.add_child(cell)
		_cells.append(cell)
	# Bag and Character.
	# Build, Bag and Character: a slot each, its icon and its key in the corner.
	var quick := PanelContainer.new()
	quick.add_theme_stylebox_override("panel", HudStyle.piece("panel"))
	quick.size_flags_vertical = Control.SIZE_SHRINK_END
	var qrow := HBoxContainer.new()
	qrow.add_theme_constant_override("separation", int(_k(GAP)))
	for q in [["build", "B", "Build"], ["bagButton", "I", "Bag"], ["characterButton", "C", "Character"]]:
		var qb := QuickButton.new()
		qb.icon_name = q[0]
		qb.key = q[1]
		qb.tooltip_text = "%s  (%s)" % [q[2], q[1]]
		qb.custom_minimum_size = Vector2(_k(CELL), _k(CELL))
		qb.pressed.connect(_toggle_build if q[0] == "build" else _toggle_panel)
		qrow.add_child(qb)
	quick.add_child(qrow)
	row.add_child(quick)
	_picker = PanelContainer.new()
	_picker.add_theme_stylebox_override("panel", HudStyle.piece("panelStrong"))
	_picker.visible = false
	add_child(_picker)
	_tip = PanelContainer.new()
	_tip.add_theme_stylebox_override("panel", HudStyle.piece("panelStrong"))
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip_text = RichTextLabel.new()
	_tip_text.bbcode_enabled = true
	_tip_text.fit_content = true
	_tip_text.scroll_active = false
	_tip_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip_text.custom_minimum_size.x = _k(250)
	_tip_text.add_theme_font_override("normal_font", HudStyle.font("bold"))
	_tip_text.add_theme_font_size_override("normal_font_size", roundi(_k(13)))
	_tip_text.add_theme_color_override("default_color", HudStyle.color("text"))
	_tip.add_child(_tip_text)
	_tip.visible = false
	add_child(_tip)
	_show_rows()


## The saved bar (Unity's player.hotbar: rows, and each slot's contents).
func from_json(json: String) -> void:
	var d: Dictionary = JSON.parse_string(json)
	rows = clampi(int(d.get("rows", 1)), 1, MAX_ROWS)
	var saved: Array = d.get("slots", [])
	for i in mini(saved.size(), slots.size()):
		slots[i] = saved[i] if saved[i] != null else ""
		if str(slots[i]).begins_with("spell:"):
			_offered[slots[i].substr(6)] = true
	_show_rows()


func to_json() -> String:
	return JSON.stringify({"rows": rows, "slots": slots})


func _toggle_build() -> void:
	if BuildMode.active != null:
		BuildMode.active.toggle()


func _toggle_panel() -> void:
	if panel != null:
		panel.toggle()


func _rows_by(by: int) -> void:
	rows = clampi(rows + by, 1, MAX_ROWS)
	_close_picker()
	_show_rows()


func _show_rows() -> void:
	for i in _cells.size():
		_cells[i].visible = i < rows * COLUMNS


static func key_name(i: int) -> String:
	var n := i % COLUMNS + 1
	return [str(n), "S" + str(n), "C" + str(n)][i / COLUMNS]


static func key_long(i: int) -> String:
	var n := i % COLUMNS + 1
	return [str(n), "Shift+" + str(n), "Ctrl+" + str(n)][i / COLUMNS]


## The key [param spell] is on as shown ("1", "S3"...), or "" when it isn't on the bar.
func key_name_of(spell: String) -> String:
	var at := slots.find("spell:" + spell)
	return key_name(at) if at >= 0 and at < rows * COLUMNS else ""


func _free(i: int) -> bool:
	return slots[i] == ""


## Puts [param spell] in the first free slot shown; true if it's on the bar (already, or now).
func assign(spell: String) -> bool:
	if slots.has("spell:" + spell):
		return true
	for i in rows * COLUMNS:
		if _free(i):
			slots[i] = "spell:" + spell
			_offered[spell] = true
			return true
	return false


## Puts [param what] ("spell:..." / "food:..." / "") on slot [param i]; one already elsewhere on the bar swaps places.
func put(i: int, what: String) -> void:
	var was := slots.find(what) if what != "" else -1
	if was >= 0:
		slots[was] = slots[i]
	slots[i] = what
	if what.begins_with("spell:"):
		_offered[what.substr(6)] = true


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k: int = event.keycode - KEY_1
		if k < 0 or k >= COLUMNS:
			return
		var row := 2 if event.ctrl_pressed else (1 if event.shift_pressed else 0)
		if row >= rows:
			return
		use(row * COLUMNS + k)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and _picker.visible:
		# A click anywhere else closes the picker.
		_close_picker()


## Pressing slot [param i]: aims (or casts) its skill, or eats one of its food.
func use(i: int) -> void:
	var s: String = slots[i]
	if s.begins_with("spell:"):
		var spell := s.substr(6)
		if stats.known_spells().has(spell):
			caster.toggle_aiming(spell)
	elif s.begins_with("food:"):
		var r := s.substr(5)
		var needs: Needs = world.player.get_node_or_null("Needs")
		if needs != null:
			needs.eat(r)


func _process(_delta: float) -> void:
	_sync_skills()
	var vp := get_viewport_rect().size
	var row: HBoxContainer = get_node("Row")
	row.reset_size()
	row.position = Vector2((vp.x - row.size.x) / 2.0, vp.y - row.size.y - 14.0).round()
	for i in rows * COLUMNS:
		_cells[i].queue_redraw()
	if _picker.visible:
		_picker.reset_size()
		var c: Control = _cells[picking]
		var top := c.get_global_rect()
		_picker.position = Vector2(clampf(top.get_center().x - _picker.size.x / 2.0, 8, vp.x - _picker.size.x - 8), maxf(8.0, _bar.get_global_rect().position.y - _picker.size.y - 8))
	if hovered >= 0 and not _picker.visible and slots[hovered] != "":
		_tip_text.text = _describe(hovered)
		_tip.visible = true
		_tip.reset_size()
		var r: Rect2 = _cells[hovered].get_global_rect()
		_tip.position = Vector2(clampf(r.get_center().x - _tip.size.x / 2.0, 8, vp.x - _tip.size.x - 8), _bar.get_global_rect().position.y - _tip.size.y - 8)
	else:
		_tip.visible = false


# Keeps the bar to what's known: gone skills off, newly known ones into a free slot, once.
func _sync_skills() -> void:
	var known := stats.known_spells()
	for i in slots.size():
		if str(slots[i]).begins_with("spell:") and not known.has(slots[i].substr(6)):
			slots[i] = ""
	for sp in known:
		if not _offered.has(sp):
			assign(sp)
			_offered[sp] = true
	var key := "|".join(known)
	if picking >= 0 and key != _known_key:
		_open_picker(picking)
	_known_key = key


func clicked(i: int) -> void:
	if picking == i:
		_close_picker()
	else:
		_open_picker(i)


func _close_picker() -> void:
	picking = -1
	_picker.visible = false


func _edible() -> Array:
	var out := []
	for r in Bag.RESOURCES:
		if UiKit.data.resources.get(r, {}).get("usable", false):
			out.append(r)
	return out


# The picker over slot [param i]: every known skill, then every food and drink, and Empty this slot.
func _open_picker(i: int) -> void:
	picking = i
	for ch in _picker.get_children():
		_picker.remove_child(ch)
		ch.queue_free()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(_k(4)))
	_picker.add_child(box)
	box.add_child(HudStyle.label("Slot " + key_long(i), 15, "bold", HudStyle.color("accent")))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(_k(250), minf(_k(420), get_viewport_rect().size.y * 0.6))
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", int(_k(4)))
	scroll.add_child(list)
	box.add_child(scroll)
	list.add_child(HudStyle.label("SKILLS", 10, "bold", HudStyle.color("faint")))
	var known := stats.known_spells()
	if known.is_empty():
		list.add_child(HudStyle.label("No skills yet: gear and talents grant them.", 12, "body", HudStyle.color("muted")))
	for sp in known:
		var what: String = "spell:" + sp
		var at := slots.find(what)
		var where := "On this slot" if at == i else ("On %s: swaps" % key_long(at) if at >= 0 and at < rows * COLUMNS else "Not on the bar")
		var spell: Dictionary = caster.spells.get(sp, {})
		list.add_child(_card(UiKit.sprite_texture(int(spell.get("icon", -1))), str(spell.get("name", sp)), "%s mana · %s" % [CharacterStats.fmt(float(spell.get("manaCost", 0))), where], at == i, what))
	list.add_child(HudStyle.label("FOOD & DRINK", 10, "bold", HudStyle.color("faint")))
	for r in _edible():
		var what: String = "food:" + r
		var at := slots.find(what)
		var where := "On this slot" if at == i else ("On %s: swaps" % key_long(at) if at >= 0 and at < rows * COLUMNS else "%d in the bag" % bag.count(r))
		list.add_child(_card(UiKit.resource_icon(r), UiKit.resource_name(r), where, at == i, what))
	if not _free(i):
		var clear := HudStyle.button("Empty this slot", 12, "slot", HudStyle.color("muted"))
		clear.custom_minimum_size.y = _k(28)
		clear.pressed.connect(_choose.bind(""))
		box.add_child(clear)
	_picker.visible = true
	_picker.move_to_front()


func _card(icon: Texture2D, name: String, sub: String, on: bool, what: String) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size.y = _k(40)
	for st in ["normal", "hover", "pressed"]:
		b.add_theme_stylebox_override(st, HudStyle.piece("slotOn" if on else "slot", Color(1.15, 1.1, 1.0) if st == "hover" else Color.WHITE))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = _k(5)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", int(_k(8)))
	var t := TextureRect.new()
	t.texture = icon
	t.custom_minimum_size = Vector2(_k(30), _k(30))
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(t)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 0)
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	names.add_child(HudStyle.label(name, 13, "bold"))
	names.add_child(HudStyle.label(sub, 11, "bold", HudStyle.color("muted")))
	row.add_child(names)
	b.add_child(row)
	b.pressed.connect(_choose.bind(what))
	return b


func _choose(what: String) -> void:
	if picking >= 0:
		put(picking, what)
	_close_picker()


func _describe(i: int) -> String:
	var s: String = slots[i]
	var accent := HudStyle.color("accent").to_html(false)
	var muted := HudStyle.color("muted").to_html(false)
	var small := roundi(_k(11))
	if s.begins_with("food:"):
		var r := s.substr(5)
		return "[color=#%s]%s[/color]  [color=#%s][%s][/color]\n[font_size=%d][color=#%s]%d in the bag · press to %s one[/color][/font_size]" % [
			accent, UiKit.resource_name(r), muted, key_long(i), small, muted, bag.count(r), "drink" if r == "Tea" or r.ends_with("Potion") else "eat"]
	var name := s.substr(6)
	var sp: Dictionary = caster.spells.get(name, {})
	var cd := " · Cooldown %ss" % CharacterStats.fmt(float(sp.get("cooldown", 0))) if float(sp.get("cooldown", 0)) > 0 else ""
	var text := "[color=#%s]%s[/color]  [color=#%s][%s][/color]\n[font_size=%d][color=#%s]%s · %s[/color]\n[color=#%s]%s mana[/color] · Cast %ss%s\nRange %s · Area %s[/font_size]" % [
		accent, sp.get("name", name), muted, key_long(i), small, muted, sp.get("element", ""), sp.get("delivery", ""),
		HudStyle.color("mana").to_html(false), CharacterStats.fmt(float(sp.get("manaCost", 0))), CharacterStats.fmt(float(sp.get("castTime", 0))), cd,
		CharacterStats.fmt(float(sp.get("range", 0))), CharacterStats.fmt(float(sp.get("aoeRadius", 0)))]
	if str(sp.get("description", "")) != "":
		text += "\n[font_size=%d][color=#%s]%s[/color][/font_size]" % [small, muted, sp.description]
	return text


## One slot: its icon, key, mana cost or count, cooldown sweep, and the aiming ring.
class HotCell extends Control:
	var bar: Hotbar
	var index := 0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _notification(what: int) -> void:
		if what == NOTIFICATION_MOUSE_ENTER:
			bar.hovered = index
		elif what == NOTIFICATION_MOUSE_EXIT and bar.hovered == index:
			bar.hovered = -1

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			bar.clicked(index)
			accept_event()

	func _text(at: Vector2, s: String, px: int, c: Color, align := HORIZONTAL_ALIGNMENT_LEFT, w := -1.0) -> void:
		var f := HudStyle.font("pixel")
		draw_string_outline(f, at, s, align, w, px, 4, Color(0, 0, 0, 0.8))
		draw_string(f, at, s, align, w, px, c)

	func _draw() -> void:
		var k := HudStyle.SCALE
		var r := Rect2(Vector2.ZERO, size)
		draw_style_box(HudStyle.piece("slotOn" if bar.picking == index else "slot"), r)
		var s: String = bar.slots[index]
		var inner := r.grow(-6 * k)
		if s.begins_with("spell:"):
			var name := s.substr(6)
			var spell: Dictionary = bar.caster.spells.get(name, {})
			var known := bar.stats.known_spells().has(name)
			var icon := UiKit.sprite_texture(int(spell.get("icon", -1)))
			var dim := not known or bar.stats.mana + 0.001 < float(spell.get("manaCost", 0.0))
			if icon != null:
				draw_texture_rect(icon, inner, false, Color(0.45, 0.45, 0.5) if dim else Color.WHITE)
			# The cooldown: a dark sweep shrinking as it comes back.
			var left := bar.caster.cooldown_left(name)
			if is_inf(left):
				draw_rect(inner, Color(0, 0, 0, 0.55))
			elif left > 0.0:
				var share := left / maxf(0.01, bar.caster.cooldown_total(name))
				draw_rect(Rect2(inner.position, Vector2(inner.size.x, inner.size.y * share)), Color(0, 0, 0, 0.55))
				_text(Vector2(0, size.y * 0.62), "%d" % ceili(left), roundi(16 * k), Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, size.x)
			_text(Vector2(0, size.y - 4), str(int(spell.get("manaCost", 0))), roundi(11 * k), HudStyle.color("mana"), HORIZONTAL_ALIGNMENT_RIGHT, size.x - 4)
			if bar.caster.aiming == name:
				draw_style_box(HudStyle.piece("slotOn"), r)
				draw_rect(r.grow(-1), HudStyle.color("accent"), false, 3.0)
		elif s.begins_with("food:"):
			var res := s.substr(5)
			var icon := UiKit.resource_icon(res)
			var n := bar.bag.count(res)
			if icon != null:
				draw_texture_rect(icon, inner, false, Color.WHITE if n > 0 else Color(0.45, 0.45, 0.5))
			_text(Vector2(0, size.y - 4), str(n), roundi(11 * k), HudStyle.color("text"), HORIZONTAL_ALIGNMENT_RIGHT, size.x - 4)
		# Its key, top left.
		_text(Vector2(4, 13 * k), Hotbar.key_name(index), roundi(10 * k), HudStyle.color("muted"))


## One of the Build, Bag and Character buttons: a slot with its icon, and its key bottom right.
class QuickButton extends Button:
	var icon_name := ""
	var key := ""

	func _init() -> void:
		focus_mode = Control.FOCUS_NONE
		flat = true

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var k := HudStyle.SCALE
		var r := Rect2(Vector2.ZERO, size)
		draw_style_box(HudStyle.piece("slotOn" if is_hovered() else "slot"), r)
		var tex := HudStyle.icon(icon_name)
		if tex != null:
			var s := 28.0 * k
			draw_texture_rect(tex, Rect2((size - Vector2(s, s)) / 2.0, Vector2(s, s)), false, Color(1, 1, 1, 0.85) if button_pressed else Color.WHITE)
		var f := HudStyle.font("bold")
		var px := roundi(10 * k)
		draw_string_outline(f, Vector2(0, size.y - 4 * k), key, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 5 * k, px, 4, Color(0, 0, 0, 0.8))
		draw_string(f, Vector2(0, size.y - 4 * k), key, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 5 * k, px, HudStyle.color("muted"))
