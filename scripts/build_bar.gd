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
var _was_in_cellar := false
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
var _snap: Label                     ## placing a prop: snapping to tiles, or free (Alt)
var _demolish_kinds: HBoxContainer   ## while demolishing: what it takes (All, Walls, Floors, Decor, Farm plots)
var _turn: Label
var _card: PanelContainer
var _card_box: VBoxContainer
var _card_for: Variant = null
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
	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", HudStyle.piece("panelStrong"))
	_card.custom_minimum_size.x = _k(300)
	_card_box = VBoxContainer.new()
	_card_box.add_theme_constant_override("separation", int(_k(6)))
	_card.add_child(_card_box)
	_card.visible = false
	add_child(_card)
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
	col.add_child(_rail_button("Move", "Move  M", "Pick up a prop and put it somewhere else", func(): build.set_tool("Place" if build.tool == "Move" else "Move")))
	col.add_child(_rail_button("Copy", "Copy  V", "Click anything built to pick the same", func(): build.set_tool("Place" if build.tool == "Copy" else "Copy")))
	col.add_child(_rail_button("Inspect", "Inspect  H", "Click a house: what it's given to, what's in it, its roof, and saving it", func(): build.set_tool("Place" if build.tool == "Inspect" else "Inspect")))
	col.add_child(_rail_button("Hide", "Hide  U", "Hide walls, roofs and plans to see the ground", build.toggle_hide_buildings))
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
	_demolish_kinds = HBoxContainer.new()
	_demolish_kinds.add_theme_constant_override("separation", int(_k(4)))
	for kind in BuildMode.DEMOLISH_KINDS:
		var b := HudStyle.button("Farm plots" if kind == "Farm" else kind, 11, "slot")
		b.custom_minimum_size = Vector2(_k(48), _k(24))
		b.tooltip_text = {"All": "Everything, one layer a click: a plan, then a prop, a wall, the floor", "Walls": "Only walls, fences and doors",
			"Floors": "Only floors and paths", "Decor": "Only props: furniture, decorations, trees, lights (not farm plots)",
			"Farm": "Only farm plots (and their crops)"}[kind]
		b.pressed.connect(build.set_demolish_only.bind(kind))
		_demolish_kinds.add_child(b)
	foot.add_child(_demolish_kinds)
	_have = HudStyle.label("", 11, "pixel", HudStyle.color("text"))
	foot.add_child(_have)
	col.add_child(foot)
	_bar.add_child(col)
	add_child(_bar)


# Placing a prop: a note over the bar's right end, snapping to tiles, or (Alt held) set down freely.
func _snap_note() -> void:
	var sel := build.selected
	# A barricade: which way it's turned, R to turn it round.
	var turns: bool = build.tool == "Place" and not sel.is_empty() and sel.kind == "Wall" and world.walls.types.get(sel.name, {}).has("front")
	_snap.visible = turns or (build.tool == "Place" and not sel.is_empty() and sel.kind == "Prop")
	if not _snap.visible:
		return
	var free := Input.is_key_pressed(KEY_ALT)
	if turns:
		_snap.text = ("Spikes towards you" if build.wall_turned else "Spikes away from you") + "  ·  R to turn it round"
	else:
		_snap.text = "Free placement  (Alt held)" if free else "Snapping to tiles  ·  hold Alt for free placement"
	_snap.add_theme_color_override("font_color", HudStyle.color("accentLight") if free and not turns else HudStyle.color("muted"))
	_snap.reset_size()
	_snap.position = Vector2(_bar.position.x + _bar.size.x - _snap.size.x, _bar.position.y - _snap.size.y - _k(6)).round()


func _build_tip() -> void:
	_snap = HudStyle.label("", 11, "bold", HudStyle.color("muted"))
	_snap.add_theme_stylebox_override("normal", HudStyle.piece("panel"))
	_snap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_snap.visible = false
	add_child(_snap)
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


# Down in the cellar only storage can be built: the bar shows that tab alone, and only what goes there.
func _in_cellar() -> bool:
	return build.miko != null and Cellars.inside(build.miko.position)


func _categories() -> Array:
	var out := []
	if _in_cellar():
		return ["Storage"]
	for c in BuildMode.CATEGORIES:
		for it in build.items:
			if it.category == c:
				out.append(c)
				break
	return out


func _process(delta: float) -> void:
	var __t := Time.get_ticks_usec()
	_process_timed(delta)
	Perf.add(&"build_bar.process", __t)


func _process_timed(_delta: float) -> void:
	if _in_cellar() != _was_in_cellar:
		_was_in_cellar = not _was_in_cellar
		_dirty = true
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
	_hint.text = build.tool_hint() + ("   ·   PLAN" if build.blueprint else "") + ("   ·   HIDDEN" if build.hide_buildings else "")
	_house_card()
	if _card.visible:
		_card.reset_size()
		_card.position = Vector2(vp.x - _card.size.x - _k(16), _bar.position.y - _card.size.y - _k(10)).round()
	_snap_note()
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
	var cellar := _in_cellar()
	if cellar:
		category = "Storage"
	for it in build.items:
		if cellar and (it.category != "Storage" or bool(it.get("outdoorsOnly", false))):
			continue
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
		_footer_text.text = {"All": "Demolish: one thing a click (a plan, then furniture, a wall, the floor)", "Walls": "Demolish walls only",
			"Floors": "Demolish floors only", "Decor": "Demolish decor only (not farm plots)", "Farm": "Demolish farm plots only"}[build.demolish_only] + " · refunds half"
	elif sel.is_empty():
		_footer_text.text = "Pick something to build"
	else:
		_footer_text.text = "%s  ·  %s" % [sel.display, sel.description]
	var painting: bool = (build.tool == "Place" and not sel.is_empty() and (sel.kind == "Ground" or sel.kind == "Floor" or build._sizable(sel))) or build.tool == "Demolish"
	_brushes.visible = painting
	_demolish_kinds.visible = build.tool == "Demolish"
	for i in _demolish_kinds.get_child_count():
		_demolish_kinds.get_child(i).add_theme_stylebox_override("normal", HudStyle.piece("slotOn" if BuildMode.DEMOLISH_KINDS[i] == build.demolish_only else "slot"))
	for i in _brushes.get_child_count():
		_brushes.get_child(i).modulate = Color(1.3, 1.15, 0.8) if i == build.brush else Color(1, 1, 1, 0.6)
	var turnable: bool = not sel.is_empty() and sel.kind == "Floor" and world.floors.can_turn(sel.name)
	_turn.text = ("R turn: %s%s" % ["across" if build.turn else "along", "  (auto)" if build.auto_turn else ""]) if turnable else ""
	if build.tool != "Place":
		_turn.text = ""
	elif not sel.is_empty() and sel.kind == "House":
		_turn.text = "R turn: door %s" % ["front right", "front left", "back left", "back right"][build.preset_turn]
	if build.tool == "Move":
		_footer_text.text = "Move: click a prop to pick it up, then click its new spot (Alt: exactly there) · R turns it · right-click puts it back"
	elif build.tool == "Copy":
		_footer_text.text = "Copy: click anything built to pick the same thing to build"
	elif build.tool == "Inspect":
		_footer_text.text = "Inspect: click a house to see what it's given to, what's in it, and change its roof"
	var parts := []
	for r in ["Wood", "Stone", "Gold"]:
		parts.append("%s %d" % [UiKit.resource_name(r), world.village.have(miko.bag, miko, r)])
	_have.text = "  ".join(parts)
	# The rail.
	_light("Place", build.tool == "Place")
	_light("Demolish", build.tool == "Demolish")
	_light("Plan", build.blueprint)
	_light("Move", build.tool == "Move")
	_light("Copy", build.tool == "Copy")
	_light("Inspect", build.tool == "Inspect")
	_light("Hide", build.hide_buildings)
	_card_for = null
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


# [param text] broken into lines of about [param width] letters (the card doesn't wrap by itself).
static func _wrap(text: String, width: int) -> String:
	var lines := []
	var line := ""
	for w in text.split(" ", false):
		if line != "" and line.length() + 1 + w.length() > width:
			lines.append(line)
			line = w
		else:
			line = w if line == "" else line + " " + w
	if line != "":
		lines.append(line)
	return "\n".join(lines)


# The card by the cursor.
func _tooltip() -> void:
	var h := build.hover
	var over := get_viewport().gui_get_hovered_control()
	# Over an item in the row: its card (what it costs, a row a material, red only where she's short).
	if over is ItemTile:
		var it: Dictionary = (over as ItemTile).item
		var st := build.status_of(it)
		var note := ("Needs a %s first" % it.lockedBy) if st == "Locked" else _wrap(str(it.get("description", "")), 40)
		h = {"show": true, "title": it.display, "tier": int(it.get("tier", 1)), "status": st, "costs": it.cost, "note": note,
			"note_plain": st != "Locked"}
	elif h.is_empty() or not bool(h.get("show", false)) or (over != null and over.mouse_filter != Control.MOUSE_FILTER_IGNORE):
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
	elif bool(h.get("move", false)):
		# Move and Copy: what it is, and why not (when it can't go there).
		t = str(h.title)
		if str(h.get("note", "")) != "":
			t += "
[color=#%s]%s[/color]" % [hex.call(HudStyle.color("coral")), h.note]
	else:
		var st: String = h.status
		var sc: Color = HudStyle.color("green") if st == "Ready" else (HudStyle.color("coral") if st == "Short" else HudStyle.color("muted"))
		t = "%s  [color=#%s]T%d[/color]   [color=#%s]%s%s[/color]" % [h.title, hex.call(HudStyle.color("faint")), h.tier, hex.call(sc), st, "  ·  PLAN" if h.get("plan", false) else ""]
		for c in Village.sum(h.costs):
			var have := world.village.have(miko.bag, miko, c[0])
			t += "\n[color=#%s]%s  %d / %d[/color]" % [hex.call(HudStyle.color("text") if have >= c[1] else HudStyle.color("coral")), UiKit.resource_name(c[0]), c[1], have]
		if Village.sum(h.costs).is_empty():
			t += "\n[color=#%s]Free[/color]" % hex.call(HudStyle.color("muted"))
		if str(h.note) != "":
			t += "\n[color=#%s]%s[/color]" % [hex.call(HudStyle.color("muted") if h.get("note_plain", false) else HudStyle.color("coral")), h.note]
	_tip_text.text = t
	_tip.visible = true
	_tip.reset_size()
	var m := get_viewport().get_mouse_position()
	var vp := get_viewport_rect().size
	if get_viewport().gui_get_hovered_control() is ItemTile:
		# An item's card: over the bar's right end (above the snapping note), never off the screen.
		var above := _bar.position.y - _k(8) - (_snap.size.y + _k(4) if _snap.visible else 0.0)
		_tip.position = Vector2(_bar.position.x + _bar.size.x - _tip.size.x, maxf(_k(8), above - _tip.size.y)).round()
		return
	var at := m + Vector2(22, 22)
	if at.x + _tip.size.x > vp.x: at.x = m.x - 22 - _tip.size.x
	if at.y + _tip.size.y > _bar.position.y: at.y = m.y - 22 - _tip.size.y
	_tip.position = at


## One item in the row: its icon and name (dimmer when it can't be built now), amber when picked; its cost on the card
## shown over it.
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
		# Its name, whole (on two lines if it must), dimmer when it can't be built now; its cost is on its card (hover).
		var font := HudStyle.font("bold")
		var px := roundi(10 * k)
		var c := HudStyle.color("faint") if st == "Locked" else (HudStyle.color("muted") if st == "Short" else HudStyle.color("text"))
		var nm := str(item.display)
		if font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x <= size.x - 8:
			draw_string(font, Vector2(4, 68 * k), nm, HORIZONTAL_ALIGNMENT_CENTER, size.x - 8, px, c)
		else:
			draw_multiline_string(font, Vector2(4, 63 * k), nm, HORIZONTAL_ALIGNMENT_CENTER, size.x - 8, px, 2, c)
		draw_string(HudStyle.font("pixel"), Vector2(6, 14 * k), "T%d" % int(item.get("tier", 1)), HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(9 * k), HudStyle.color("faint"))


# The picked house (Inspect): what it's given to and its bonus, what's in it, its roof, and saving it.
func _house_card() -> void:
	var shows: bool = build.tool == "Inspect" and build.picked_room != null
	_card.visible = shows
	if not shows or _card_for == build.picked_room:
		return
	_card_for = build.picked_room
	for ch in _card_box.get_children():
		_card_box.remove_child(ch)
		ch.queue_free()
	var info: Array = build.picked_info()
	_card_box.add_child(HudStyle.label(info[0], 15, "bold", HudStyle.color("accentLight")))
	var perk := HudStyle.label(info[1], 11, "body", HudStyle.color("green"))
	perk.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	perk.custom_minimum_size.x = _k(280)
	_card_box.add_child(perk)
	_card_box.add_child(HudStyle.label("%d tiles" % info[3], 11, "bold", HudStyle.color("muted")))
	var inside := HudStyle.label("Inside: " + info[2], 11, "body")
	inside.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inside.custom_minimum_size.x = _k(280)
	_card_box.add_child(inside)
	_card_box.add_child(HudStyle.label("ROOF", 10, "bold", HudStyle.color("faint")))
	var roofs := HFlowContainer.new()
	roofs.add_theme_constant_override("h_separation", int(_k(4)))
	roofs.add_theme_constant_override("v_separation", int(_k(4)))
	roofs.custom_minimum_size.x = _k(280)
	var current := world.roofs.look_of(build.picked_room)
	for st in world.roofs.styles():
		var b := HudStyle.button(st[1], 11, "pill", HudStyle.color("text") if st[0] == current else HudStyle.color("muted"))
		if st[0] == current:
			b.add_theme_stylebox_override("normal", HudStyle.piece("pill", Color(HudStyle.color("accent"), 0.7)))
		b.pressed.connect(func():
			build.set_picked_roof(st[0])
			_card_for = null)
		roofs.add_child(b)
	_card_box.add_child(roofs)
	var save := HudStyle.button("Save as blueprint", 12, "barFill", HudStyle.color("ink"))
	save.add_theme_stylebox_override("normal", HudStyle.piece("barFill", HudStyle.color("accent")))
	save.pressed.connect(func():
		build.save_picked_house()
		_dirty = true)
	_card_box.add_child(save)
