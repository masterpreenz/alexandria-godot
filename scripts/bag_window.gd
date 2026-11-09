class_name BagWindow
extends PanelContainer
## The bag (from Unity's BagGrid, shown on its own until the character panel comes over): its 8 x 8 grid of slots,
## each showing its item (its icon, or a coloured tile with its initials) or a stack with its count. The slots past
## Miko's own 8 are the worn bag's (ringed amber); past what she has, they're shut. Click one to select it (the details
## below show it), double-click to use it (eat or drink), drag one onto another slot to move or swap them. A filter
## narrows it to one kind: Equipment keeps the bag's own layout, Consumables and Materials list their stacks.
## Opened and closed with I.

const CELL := 54.0
const FILTERS := ["All", "Equipment", "Consumables", "Materials"]

var bag: Bag
var world: World
var filter := "All"
var selected := -1           # the shown slot picked, or -1
var _cells: Array[SlotCell] = []
var _shows := []             # what each shown slot holds: ["item", slot] / ["stack", resource] / []
var _gold: Label
var _detail_name: Label
var _detail_kind: Label
var _detail_text: Label
var _tabs := {}


func setup(w: World, b: Bag) -> void:
	world = w
	bag = b
	add_theme_stylebox_override("panel", UiKit.piece("frame"))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	var head := HBoxContainer.new()
	head.add_child(UiKit.label("Bag", 26, true))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	var gold_icon := TextureRect.new()
	gold_icon.texture = UiKit.resource_icon("Gold")
	gold_icon.custom_minimum_size = Vector2(22, 22)
	gold_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	gold_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	head.add_child(gold_icon)
	_gold = UiKit.label("0", 18)
	head.add_child(_gold)
	box.add_child(head)
	var tabs := HBoxContainer.new()
	for f in FILTERS:
		var b2 := Button.new()
		b2.text = f
		b2.toggle_mode = true
		b2.add_theme_font_size_override("font_size", 15)
		b2.pressed.connect(func(): _set_filter(f))
		tabs.add_child(b2)
		_tabs[f] = b2
	box.add_child(tabs)
	var grid := GridContainer.new()
	grid.columns = Bag.COLUMNS
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	for i in Bag.SIZE:
		var c := SlotCell.new()
		c.window = self
		c.index = i
		c.custom_minimum_size = Vector2(CELL, CELL)
		grid.add_child(c)
		_cells.append(c)
	box.add_child(grid)
	var detail := PanelContainer.new()
	detail.add_theme_stylebox_override("panel", UiKit.piece("inset"))
	detail.custom_minimum_size = Vector2(0, 110)
	var dbox := VBoxContainer.new()
	_detail_name = UiKit.label("", 20, true)
	_detail_kind = UiKit.label("", 14, false, UiKit.colors.muted)
	_detail_text = UiKit.label("", 15)
	_detail_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_text.custom_minimum_size = Vector2(CELL * Bag.COLUMNS, 0)
	dbox.add_child(_detail_name)
	dbox.add_child(_detail_kind)
	dbox.add_child(_detail_text)
	detail.add_child(dbox)
	box.add_child(detail)
	bag.changed.connect(refresh)
	_set_filter("All")


func _set_filter(f: String) -> void:
	filter = f
	for k in _tabs:
		_tabs[k].button_pressed = k == f
	selected = -1
	refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_I:
		visible = not visible
		if visible:
			refresh()
		get_viewport().set_input_as_handled()


## What the shown slots hold, by the filter.
func _layout() -> void:
	_shows.clear()
	_shows.resize(Bag.SIZE)
	_shows.fill([])
	if filter == "All" or filter == "Equipment":
		for i in Bag.SIZE:
			if bag.items[i] != "":
				_shows[i] = ["item", i]
			elif filter == "All" and bag.stack_in(i) != "":
				_shows[i] = ["stack", bag.stack_in(i)]
		return
	var n := 0
	for r in Bag.RESOURCES:
		if bag.count(r) > 0 and Bag.slotted(r) and UiKit.data.resources.get(r, {}).get("group", "") == filter:
			_shows[n] = ["stack", r]
			n += 1


func refresh() -> void:
	if bag == null:
		return
	_gold.text = str(bag.count("Gold"))
	_layout()
	var cap := bag.capacity()
	var keep_layout := filter == "All" or filter == "Equipment"
	for i in Bag.SIZE:
		var c := _cells[i]
		c.shut = keep_layout and i >= cap
		c.bag_owned = keep_layout and i >= Bag.BASE_SLOTS and i < cap
		c.selected = i == selected
		c.show_what(_shows[i], bag)
	_detail()


func _detail() -> void:
	var what: Array = _shows[selected] if selected >= 0 else []
	if what.is_empty():
		_detail_name.text = ""
		_detail_kind.text = ""
		_detail_text.text = "Click a slot to see it; double-click food to eat it; drag to move." if filter in ["All", "Equipment"] else ""
		return
	if what[0] == "item":
		var it := UiKit.item(bag.items[what[1]])
		_detail_name.text = it.get("name", bag.items[what[1]])
		_detail_kind.text = it.get("label", "")
		var lines := []
		for st in it.get("stats", []):
			lines.append("+%s%s %s" % [_num(st[1]), st[2], st[0]])
		if it.get("bagSlots", 0) > 0:
			lines.append("+%d bag slots" % it.bagSlots)
		lines.append(it.get("description", ""))
		_detail_text.text = "\n".join(lines.filter(func(l): return l != ""))
	else:
		var r: String = what[1]
		_detail_name.text = UiKit.resource_name(r)
		_detail_kind.text = UiKit.data.resources.get(r, {}).get("group", "").trim_suffix("s")
		_detail_text.text = "%d carried.%s" % [bag.count(r), "  Double-click to use one." if UiKit.data.resources[r].usable else ""]


static func _num(v: float) -> String:
	return str(int(v)) if is_equal_approx(v, roundf(v)) else "%.1f" % v


func clicked(i: int, double: bool) -> void:
	selected = i
	if double:
		use(i)
	refresh()


## Using what's in shown slot [param i]: something to eat or drink, one of it (its effects come with the needs).
func use(i: int) -> void:
	var what: Array = _shows[i]
	if what.is_empty() or what[0] != "stack":
		return
	var r: String = what[1]
	if not UiKit.data.resources.get(r, {}).get("usable", false):
		return
	if bag.spend(r, 1):
		FloatingText.spawn(world, "%s %s" % ["Drank" if r in ["Tea", "HpPotion", "ManaPotion"] else "Ate", UiKit.resource_name(r)], world.player.position + Vector2(0, -1.6 * world.px), UiKit.colors.worldText)


## A drag from shown slot [param from] dropped on [param to]: moved or swapped (in the bag's own layout).
func dropped(from: int, to: int) -> void:
	if filter != "All" and filter != "Equipment":
		return
	bag.move(from, to)
	selected = to


## One slot of the grid: draws its slot piece, what's in it, its count, and its rings.
class SlotCell extends Control:
	var window: BagWindow
	var index := 0
	var shut := false
	var bag_owned := false
	var selected := false
	var _icon: Texture2D
	var _tile := Color.TRANSPARENT
	var _initials := ""
	var _count := ""
	var _empty := true

	func show_what(what: Array, bag: Bag) -> void:
		_icon = null
		_tile = Color.TRANSPARENT
		_initials = ""
		_count = ""
		_empty = what.is_empty()
		if not _empty:
			if what[0] == "item":
				var it := UiKit.item(bag.items[what[1]])
				_icon = UiKit.sprite_texture(int(it.get("icon", -1)))
				if _icon == null:
					_tile = UiKit.kind_color(it.get("kind", ""))
					_initials = UiKit.initials(it.get("name", "?"))
			else:
				_icon = UiKit.resource_icon(what[1])
				_count = str(bag.count(what[1]))
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_style_box(UiKit.piece("slot", Color(0.55, 0.55, 0.55, 0.6) if shut else Color.WHITE), r)
		if bag_owned:
			draw_rect(r.grow(-3), Color(0.9, 0.62, 0.2, 0.55), false, 2.0)
		if selected:
			draw_rect(r.grow(-1), UiKit.colors.gold, false, 3.0)
		var inner := r.grow(-9)
		if _tile.a > 0:
			draw_rect(inner, _tile)
			var f: Font = UiKit.body_font if UiKit.body_font else get_theme_default_font()
			draw_string(f, inner.position + Vector2(0, inner.size.y * 0.66), _initials, HORIZONTAL_ALIGNMENT_CENTER, inner.size.x, 18, Color.WHITE)
		elif _icon != null:
			draw_texture_rect(_icon, inner, false)
		if _count != "":
			var f2: Font = UiKit.body_font if UiKit.body_font else get_theme_default_font()
			var at := Vector2(4, size.y - 5)
			draw_string_outline(f2, at, _count, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 8, 15, 4, Color(1, 1, 1, 0.9))
			draw_string(f2, at, _count, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 8, 15, UiKit.colors.text)

	func _gui_input(event: InputEvent) -> void:
		if shut:
			return
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			window.clicked(index, event.double_click)

	func _get_drag_data(_at: Vector2) -> Variant:
		if _empty or shut:
			return null
		var preview := TextureRect.new()
		preview.texture = _icon
		preview.custom_minimum_size = Vector2(40, 40)
		preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		set_drag_preview(preview)
		return {"bag_slot": index}

	func _can_drop_data(_at: Vector2, d: Variant) -> bool:
		return not shut and d is Dictionary and d.has("bag_slot")

	func _drop_data(_at: Vector2, d: Variant) -> void:
		window.dropped(int(d.bag_slot), index)
