class_name BuildBar
extends Control
## Build mode's interface (from Unity's BuildBar), shown while build mode is open: a pill at the top (BUILD, a hint for
## the tool in hand, PLAN when blueprints are on, and Esc Done); a rail of tools on the left (Place, Demolish X,
## Blueprint N, Undo, Redo, Start building and Clear plans); and the build bar along the bottom: category tabs (Q and
## E step through them), a search across everything, one row of items that scrolls sideways (each with its cost,
## coral when short, or what to build first when locked), and a footer with what the picked item does, what's to hand,
## the brush sizes and the turn. A card by the cursor says what clicking would do: the item, Ready / Short / Locked,
## each cost as needed / have, or what demolishing gives back.

const TILE := Vector2(78, 92)

var build: BuildMode
var world: World
var miko: Miko
var category := ""
var query := ""
var _dirty := true
var _pill: PanelContainer
var _hint: Label
var _rail: PanelContainer
var _rail_buttons := {}
var _bar: PanelContainer
var _tabs: HBoxContainer
var _items: HBoxContainer
var _search: LineEdit
var _footer_text: Label
var _have: Label
var _brushes: HBoxContainer
var _turn: Label
var _tip: PanelContainer
var _tip_text: RichTextLabel


func _k(v: float) -> float:
	return v * HudStyle.SCALE


func setup(b: BuildMode, w: World, who: Miko) -> void:
	build = b
	world = w
	miko = who
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.changed.connect(func(): _dirty = true)
	who.bag.changed.connect(func(): _dirty = true)
	w.village.changed.connect(func(): _dirty = true)
	_build_pill()
	_build_rail()
	_build_bar()
	_build_tip()
	for it in b.items:
		if category == "":
			category = it.category
	if not b.selected.is_empty():
		category = b.selected.category
	visible = false


func _build_pill() -> void:
	_pill = PanelContainer.new()
	_pill.add_theme_stylebox_override("panel", HudStyle.piece("pill"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(_k(12)))
	row.add_child(HudStyle.label("BUILD", 13, "pixel", HudStyle.color("accent")))
	_hint = HudStyle.label("", 12, "bold")
	row.add_child(_hint)
	var done := HudStyle.button("Esc  Done", 11, "slot")
	done.pressed.connect(func(): build.set_open(false))
	row.add_child(done)
	_pill.add_child(row)
	add_child(_pill)


func _rail_button(key: String, text: String, tip: String, act: Callable) -> Button:
	var b := HudStyle.button(text, 11, "slot")
	b.custom_minimum_size = Vector2(_k(96), _k(32))
	b.tooltip_text = tip
	b.pressed.connect(act)
	_rail_buttons[key] = b
	return b


func _build_rail() -> void:
	_rail = PanelContainer.new()
	_rail.add_theme_stylebox_override("panel", HudStyle.piece("panel"))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", int(_k(4)))
	col.add_child(_rail_button("Place", "Place", "Place the picked item", func(): build.set_tool("Place")))
	col.add_child(_rail_button("Demolish", "Demolish  X", "Remove what's built (refunds half)", func(): build.set_tool("Place" if build.tool == "Demolish" else "Demolish")))
	col.add_child(_rail_button("Plan", "Blueprint  N", "Blueprint mode: walls and floors you place become plans for the villagers to build", build.toggle_blueprint))
	col.add_child(_rail_button("Undo", "Undo", "Ctrl+Z", build.undo))
	col.add_child(_rail_button("Redo", "Redo", "Ctrl+Y", build.redo))
	col.add_child(_rail_button("Start", "Start building", "Mark the plans ready for the villagers", build.start_building))
	col.add_child(_rail_button("Clear", "Clear plans", "Drop the plans not started", build.clear_plans))
	_rail.add_child(col)
	add_child(_rail)


func _build_bar() -> void:
	_bar = PanelContainer.new()
	_bar.add_theme_stylebox_override("panel", HudStyle.piece("panelStrong"))
	_bar.custom_minimum_size.x = _k(820)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", int(_k(6)))
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", int(_k(4)))
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", int(_k(4)))
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_tabs)
	_search = LineEdit.new()
	_search.placeholder_text = "Search  /"
	_search.custom_minimum_size = Vector2(_k(150), _k(28))
	_search.add_theme_stylebox_override("normal", HudStyle.piece("well"))
	_search.add_theme_stylebox_override("focus", HudStyle.piece("well"))
	_search.add_theme_font_size_override("font_size", roundi(_k(12)))
	_search.text_changed.connect(func(t: String):
		query = t.strip_edges().to_lower()
		_dirty = true)
	top.add_child(_search)
	col.add_child(top)
	var scroll := ScrollContainer.new()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = _k(TILE.y + 14)
	_items = HBoxContainer.new()
	_items.add_theme_constant_override("separation", int(_k(6)))
	scroll.add_child(_items)
	col.add_child(scroll)
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", int(_k(10)))
	_footer_text = HudStyle.label("", 11, "bold", HudStyle.color("muted"))
	_footer_text.clip_text = true
	_footer_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_footer_text.custom_minimum_size.x = _k(100)
	foot.add_child(_footer_text)
	_turn = HudStyle.label("", 11, "bold", HudStyle.color("accentLight"))
	foot.add_child(_turn)
	_brushes = HBoxContainer.new()
	_brushes.add_theme_constant_override("separation", int(_k(4)))
	for i in build._brush_sizes().size():
		var n := int(build._brush_sizes()[i])
		var b := HudStyle.button("%dx%d" % [n, n], 11, "slot")
		b.custom_minimum_size = Vector2(_k(40), _k(24))
		b.pressed.connect(build.set_brush.bind(i))
		_brushes.add_child(b)
	foot.add_child(_brushes)
	_have = HudStyle.label("", 11, "pixel", HudStyle.color("text"))
	foot.add_child(_have)
	col.add_child(foot)
	_bar.add_child(col)
	add_child(_bar)


func _build_tip() -> void:
	_tip = PanelContainer.new()
	_tip.add_theme_stylebox_override("panel", HudStyle.piece("panelStrong"))
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip_text = RichTextLabel.new()
	_tip_text.bbcode_enabled = true
	_tip_text.fit_content = true
	_tip_text.scroll_active = false
	_tip_text.autowrap_mode = TextServer.AUTOWRAP_OFF
	_tip_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip_text.add_theme_font_override("normal_font", HudStyle.font("bold"))
	_tip_text.add_theme_font_size_override("normal_font_size", roundi(_k(12)))
	_tip_text.add_theme_color_override("default_color", HudStyle.color("text"))
	_tip.add_child(_tip_text)
	_tip.visible = false
	add_child(_tip)


func _unhandled_input(event: InputEvent) -> void:
	if not build.open or not (event is InputEventKey and event.pressed and not event.echo):
		return
	if get_viewport().gui_get_focus_owner() == _search:
		if event.keycode == KEY_ESCAPE:
			_search.release_focus()
			get_viewport().set_input_as_handled()
		return
	var cats := _categories()
	var i := cats.find(category)
	match event.keycode:
		KEY_Q: category = cats[(i - 1 + cats.size()) % cats.size()]
		KEY_E: category = cats[(i + 1) % cats.size()]
		KEY_SLASH: _search.grab_focus()
		KEY_1, KEY_2, KEY_3: build.set_brush(event.keycode - KEY_1)
		_: return
	_dirty = true
	get_viewport().set_input_as_handled()


func _categories() -> Array:
	var out := []
	for c in BuildMode.CATEGORIES:
		for it in build.items:
			if it.category == c:
				out.append(c)
				break
	return out


func _process(_delta: float) -> void:
	visible = build.open
	if not visible:
		return
	var vp := get_viewport_rect().size
	if _dirty:
		_dirty = false
		_refresh()
	_pill.reset_size()
	_pill.position = Vector2((vp.x - _pill.size.x) / 2.0, _k(14)).round()
	_bar.reset_size()
	_bar.position = Vector2((vp.x - _bar.size.x) / 2.0, vp.y - _bar.size.y - _k(14)).round()
	_rail.reset_size()
	_rail.position = Vector2(_bar.position.x - _rail.size.x - _k(8), vp.y - _rail.size.y - _k(14)).round()
	_hint.text = build.tool_hint() + ("   ·   PLAN" if build.blueprint else "")
	_tooltip()


func _refresh() -> void:
	# Tabs: the open one named.
	for ch in _tabs.get_children():
		_tabs.remove_child(ch)
		ch.queue_free()
	for c in _categories():
		var b := HudStyle.button(c, 11, "pill", HudStyle.color("text") if c == category else HudStyle.color("muted"))
		if c == category and query == "":
			b.add_theme_stylebox_override("normal", HudStyle.piece("pill", Color(HudStyle.color("accent"), 0.7)))
		b.pressed.connect(_pick_category.bind(c))
		_tabs.add_child(b)
	# The items: the tab's, or everything matching the search.
	for ch in _items.get_children():
		_items.remove_child(ch)
		ch.queue_free()
	for it in build.items:
		if query != "":
			if not (str(it.display).to_lower().contains(query) or str(it.category).to_lower().contains(query)):
				continue
		elif it.category != category:
			continue
		var t := ItemTile.new()
		t.bar = self
		t.item = it
		t.custom_minimum_size = TILE * HudStyle.SCALE
		_items.add_child(t)
	# The footer.
	var sel := build.selected
	if build.tool == "Demolish":
		_footer_text.text = "Demolish: click to remove one thing (a plan, then furniture, a wall, the floor) · refunds half"
	elif sel.is_empty():
		_footer_text.text = "Pick something to build"
	else:
		_footer_text.text = "%s  ·  %s" % [sel.display, sel.description]
	var painting: bool = not sel.is_empty() and (sel.kind == "Ground" or sel.kind == "Floor" or build._sizable(sel)) or build.tool == "Demolish"
	_brushes.visible = painting
	for i in _brushes.get_child_count():
		_brushes.get_child(i).modulate = Color(1.3, 1.15, 0.8) if i == build.brush else Color(1, 1, 1, 0.6)
	var turnable: bool = not sel.is_empty() and sel.kind == "Floor" and world.floors.can_turn(sel.name)
	_turn.text = ("R turn: %s%s" % ["across" if build.turn else "along", "  (auto)" if build.auto_turn else ""]) if turnable else ""
	var parts := []
	for r in ["Wood", "Stone", "Gold"]:
		parts.append("%s %d" % [UiKit.resource_name(r), world.village.have(miko.bag, miko, r)])
	_have.text = "  ".join(parts)
	# The rail.
	_light("Place", build.tool == "Place")
	_light("Demolish", build.tool == "Demolish")
	_light("Plan", build.blueprint)
	_rail_buttons.Undo.disabled = not build.can_undo()
	_rail_buttons.Redo.disabled = not build.can_redo()
	var drafts: int = Construction.active.drafts() if Construction.active != null else 0
	_rail_buttons.Start.disabled = drafts == 0
	_rail_buttons.Clear.disabled = drafts == 0
	_rail_buttons.Start.text = "Start building" + (" (%d)" % drafts if drafts > 0 else "")


func _light(key: String, on: bool) -> void:
	var b: Button = _rail_buttons[key]
	b.add_theme_stylebox_override("normal", HudStyle.piece("slotOn" if on else "slot"))


func _pick_category(c: String) -> void:
	category = c
	_search.text = ""
	query = ""
	_dirty = true


func pick(it: Dictionary) -> void:
	build.select(it)
	_dirty = true


# The card by the cursor.
func _tooltip() -> void:
	var h := build.hover
	var over := get_viewport().gui_get_hovered_control()
	if h.is_empty() or not bool(h.get("show", false)) or (over != null and over.mouse_filter != Control.MOUSE_FILTER_IGNORE):
		_tip.visible = false
		return
	var hex := func(c: Color) -> String: return c.to_html(false)
	var t := ""
	if bool(h.get("demolish", false)):
		t = "[color=#%s]%s[/color]" % [hex.call(HudStyle.color("coral")), h.title]
		var parts := []
		for c in h.refund:
			parts.append("+%d %s" % [c[1], UiKit.resource_name(c[0]).to_lower()])
		t += "\n[color=#%s]%s[/color]" % [hex.call(HudStyle.color("muted")), ("Refunds " + ", ".join(parts)) if not parts.is_empty() else "Nothing back"]
	else:
		var st: String = h.status
		var sc: Color = HudStyle.color("green") if st == "Ready" else (HudStyle.color("coral") if st == "Short" else HudStyle.color("muted"))
		t = "%s  [color=#%s]T%d[/color]   [color=#%s]%s%s[/color]" % [h.title, hex.call(HudStyle.color("faint")), h.tier, hex.call(sc), st, "  ·  PLAN" if h.get("plan", false) else ""]
		for c in Village.sum(h.costs):
			var have := world.village.have(miko.bag, miko, c[0])
			t += "\n[color=#%s]%s  %d / %d[/color]" % [hex.call(HudStyle.color("text") if have >= c[1] else HudStyle.color("coral")), UiKit.resource_name(c[0]), c[1], have]
		if str(h.note) != "":
			t += "\n[color=#%s]%s[/color]" % [hex.call(HudStyle.color("coral")), h.note]
	_tip_text.text = t
	_tip.visible = true
	_tip.reset_size()
	var m := get_viewport().get_mouse_position()
	var vp := get_viewport_rect().size
	var at := m + Vector2(22, 22)
	if at.x + _tip.size.x > vp.x: at.x = m.x - 22 - _tip.size.x
	if at.y + _tip.size.y > _bar.position.y: at.y = m.y - 22 - _tip.size.y
	_tip.position = at


## One item in the row: its icon, name and cost (coral when short), "needs X" when locked, amber when picked.
class ItemTile extends Control:
	var bar: BuildBar
	var item: Dictionary

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			bar.pick(item)
			accept_event()

	func _draw() -> void:
		var k := HudStyle.SCALE
		var picked: bool = bar.build.selected == item and bar.build.tool == "Place"
		var st := bar.build.status_of(item)
		var r := Rect2(Vector2.ZERO, size)
		draw_style_box(HudStyle.piece("tileOn" if picked else "tile"), r)
		var icon := UiKit.sprite_texture(int(item.get("icon", -1)))
		var box := Rect2(Vector2(14, 6) * k, Vector2(size.x - 28 * k, 44 * k))
		if icon != null:
			var s := icon.get_size()
			var f := minf(box.size.x / s.x, box.size.y / s.y)
			var w := s * f
			draw_texture_rect(icon, Rect2(box.position + (box.size - w) / 2.0, w), false, Color(1, 1, 1, 0.45) if st == "Locked" else Color.WHITE)
		var font := HudStyle.font("bold")
		var px := roundi(10 * k)
		draw_string(font, Vector2(4, 62 * k), str(item.display), HORIZONTAL_ALIGNMENT_CENTER, size.x - 8, px, HudStyle.color("text"))
		var line := ""
		var c := HudStyle.color("muted")
		if st == "Locked":
			line = "needs " + str(item.lockedBy)
			c = HudStyle.color("faint")
		else:
			var parts := []
			for cost in Village.sum(item.cost):
				parts.append("%d %s" % [cost[1], UiKit.resource_name(cost[0]).left(5).to_lower()])
			line = " ".join(parts) if not parts.is_empty() else "free"
			c = HudStyle.color("coral") if st == "Short" else HudStyle.color("muted")
		draw_string(font, Vector2(4, 78 * k), line, HORIZONTAL_ALIGNMENT_CENTER, size.x - 8, roundi(9 * k), c)
		draw_string(HudStyle.font("pixel"), Vector2(6, 14 * k), "T%d" % int(item.get("tier", 1)), HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(9 * k), HudStyle.color("faint"))
