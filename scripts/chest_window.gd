class_name ChestWindow
extends PanelContainer
## A chest, opened (from Unity's ChestWindow): the village's storage on the left (one cell for each resource stored,
## its count coral when the chests are full of it, then the stored gear) and Miko's bag on the right. Click something
## stored to take it all (as much as the bag takes), Ctrl+click to say how many; click something in the bag to store
## it. "Store all" puts every resource she carries in storage; "Sort" tidies the bag and the stored gear; "Village
## totals" lists what's carried and stored of everything, with the limits.

const CELL := 46.0
const STORE_COLUMNS := 6
## The storage's order (Unity's); anything else stored comes after, in the bag's order.
const ORDER := ["Wood", "Stone", "Gold", "Food", "Meal", "Tea", "Seed", "Hide", "Crystal", "Jelly", "Candy", "Potato",
	"BakedPotato", "Rabbit"]

var world: World
var bag: Bag
var miko: Miko
var _sub: Label
var _store_grid: GridContainer
var _bag_grid: GridContainer
var _gold: Label
var _say: Label
var _say_until := 0.0
var _dirty := true
var _ask: PanelContainer
var _ask_title: Label
var _ask_field: LineEdit
var _asking := ""
var _totals: PanelContainer
var _totals_list: VBoxContainer


func setup(w: World, who: Miko, hud: Node) -> void:
	world = w
	miko = who
	bag = who.bag
	var k := HudStyle.SCALE
	add_theme_stylebox_override("panel", HudStyle.piece("panelStrong"))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(6 * k))
	add_child(box)
	var head := HBoxContainer.new()
	head.add_child(HudStyle.label("Village storage", 16, "bold", HudStyle.color("accentLight")))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(gap)
	head.add_child(HudStyle.label("E / Esc close", 10, "bold", HudStyle.color("faint")))
	box.add_child(head)
	_sub = HudStyle.label("", 11, "bold", HudStyle.color("muted"))
	box.add_child(_sub)
	var sides := HBoxContainer.new()
	sides.add_theme_constant_override("separation", int(18 * k))
	box.add_child(sides)
	# Left: what's stored.
	var left := VBoxContainer.new()
	left.add_child(HudStyle.label("STORED  ·  click to take  ·  Ctrl+click: how many", 10, "bold", HudStyle.color("faint")))
	_store_grid = _grid(STORE_COLUMNS)
	left.add_child(_scroll(_store_grid, STORE_COLUMNS))
	sides.add_child(left)
	# Right: what she carries.
	var right := VBoxContainer.new()
	var rh := HBoxContainer.new()
	rh.add_child(HudStyle.label("CARRIED  ·  click to store", 10, "bold", HudStyle.color("faint")))
	var gap2 := Control.new()
	gap2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rh.add_child(gap2)
	var coin := TextureRect.new()
	coin.texture = UiKit.resource_icon("Gold")
	coin.custom_minimum_size = Vector2(14, 14) * k
	coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rh.add_child(coin)
	_gold = HudStyle.label("0", 12, "pixel", HudStyle.color("accentLight"))
	rh.add_child(_gold)
	right.add_child(rh)
	_bag_grid = _grid(Bag.COLUMNS)
	right.add_child(_scroll(_bag_grid, Bag.COLUMNS))
	sides.add_child(right)
	# The footer: a word when something can't be done, and the buttons.
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", int(8 * k))
	_say = HudStyle.label("", 11, "bold", HudStyle.color("coral"))
	_say.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(_say)
	var sort := HudStyle.button("Sort", 12)
	sort.pressed.connect(func():
		_sort_bag()
		world.village.sort_items()
		_dirty = true)
	foot.add_child(sort)
	var totals := HudStyle.button("Village totals", 12)
	totals.pressed.connect(func(): show_totals(not _totals.visible))
	foot.add_child(totals)
	var all := HudStyle.button("Store all", 12, "barFill", HudStyle.color("ink"))
	all.pressed.connect(store_all)
	foot.add_child(all)
	box.add_child(foot)
	_build_ask(hud)
	_build_totals(hud)
	bag.changed.connect(func(): _dirty = true)
	world.village.changed.connect(func(): _dirty = true)
	visible = false


func _grid(columns: int) -> GridContainer:
	var g := GridContainer.new()
	g.columns = columns
	g.add_theme_constant_override("h_separation", int(4 * HudStyle.SCALE))
	g.add_theme_constant_override("v_separation", int(4 * HudStyle.SCALE))
	return g


func _scroll(g: GridContainer, columns: int) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.custom_minimum_size = Vector2(columns * (CELL + 4) + 6, 6 * (CELL + 4)) * HudStyle.SCALE
	s.add_child(g)
	return s


func open() -> void:
	visible = true
	_dirty = true
	_say.text = ""


func close() -> void:
	visible = false
	cancel_ask()
	show_totals(false)


func asking() -> bool:
	return _ask.visible


func totals_open() -> bool:
	return _totals.visible


func say(text: String) -> void:
	_say.text = text
	_say_until = Villager.now() + 2.5


func _process(_delta: float) -> void:
	if not visible:
		return
	if _say.text != "" and Villager.now() > _say_until:
		_say.text = ""
	if _dirty:
		_dirty = false
		_refresh()
	var vp := get_viewport_rect().size
	reset_size()
	position = ((vp - size) / 2.0).round() + Vector2(0, -20)
	if _totals.visible:
		_totals.reset_size()
		_totals.position = ((vp - _totals.size) / 2.0).round()
	if _ask.visible:
		_ask.reset_size()
		_ask.position = ((vp - _ask.size) / 2.0).round()


# ---- The grids ----

func _refresh() -> void:
	var v := world.village
	var chests := v.chests().size()
	_sub.text = "%d chest%s  ·  shared anywhere in the village  ·  gear %d/%d" % [chests, "" if chests == 1 else "s", v.items.size(), v.item_slots()]
	_gold.text = str(bag.count("Gold"))
	# Storage: each resource stored, then the gear.
	var shows := []
	for r in _order():
		if v.stored(r) > 0:
			shows.append(["stack", r])
	for i in v.items.size():
		shows.append(["item", i])
	var n := maxi(STORE_COLUMNS * 6, ceili(shows.size() / float(STORE_COLUMNS)) * STORE_COLUMNS)
	_cells(_store_grid, n)
	for i in n:
		var c: Cell = _store_grid.get_child(i)
		if i >= shows.size():
			continue
		var what: Array = shows[i]
		if what[0] == "stack":
			var r: String = what[1]
			var full := v.stored(r) >= v.stash_cap(r)
			c.show_stack(r, v.stored(r), HudStyle.color("coral") if full else HudStyle.color("text"))
			c.tooltip_text = "%s  ·  %d / %d" % [UiKit.resource_name(r), v.stored(r), v.stash_cap(r)]
			c.on_click = _take.bind(r)
		else:
			var name: String = v.items[what[1]]
			c.show_item(name)
			c.tooltip_text = str(UiKit.item(name).get("name", name))
			c.on_click = _take_item.bind(int(what[1]))
	# The bag, in its own layout: its gear and stacks, the slots past what she has shut.
	var cap := bag.capacity()
	_cells(_bag_grid, Bag.SIZE)
	for i in Bag.SIZE:
		var c: Cell = _bag_grid.get_child(i)
		c.shut = i >= cap
		if bag.items[i] != "":
			var name: String = bag.items[i]
			c.show_item(name)
			c.tooltip_text = str(UiKit.item(name).get("name", name))
			c.on_click = _store_item.bind(i)
		elif bag.stack_in(i) != "":
			var r := bag.stack_in(i)
			c.show_stack(r, bag.count(r), HudStyle.color("text"))
			c.tooltip_text = UiKit.resource_name(r)
			c.on_click = _store.bind(r)


func _take_item(_ctrl: bool, index: int) -> void:
	if not world.village.take_item(bag, index):
		say("No room in your bag")


func _store_item(_ctrl: bool, slot: int) -> void:
	if not world.village.store_item(bag, slot):
		say("The chests have no room for gear")


func _store(_ctrl: bool, r: String) -> void:
	if world.village.store(bag, r, bag.count(r)) <= 0:
		say("The chests are full of that")


func _order() -> Array:
	var list := ORDER.duplicate()
	for r in Bag.RESOURCES:
		if not list.has(r):
			list.append(r)
	return list


func _cells(grid: GridContainer, n: int) -> void:
	while grid.get_child_count() < n:
		var c := Cell.new()
		c.custom_minimum_size = Vector2(CELL, CELL) * HudStyle.SCALE
		grid.add_child(c)
	while grid.get_child_count() > n:
		var last := grid.get_child(grid.get_child_count() - 1)
		grid.remove_child(last)
		last.queue_free()
	for c in grid.get_children():
		c.on_click = Callable()
		c.tooltip_text = ""
		c.shut = false
		c.show_nothing()
		c.queue_redraw()


# ---- Taking and storing ----

func _most_to_take(r: String) -> int:
	return maxi(0, mini(world.village.stored(r), Village.base_cap(r) - bag.count(r)))


func _take(ctrl: bool, r: String) -> void:
	var most := _most_to_take(r)
	if most <= 0:
		say("None stored" if world.village.stored(r) <= 0 else "You can't carry more of that")
		return
	if ctrl:
		_ask_for(r)
		return
	if world.village.withdraw(bag, r, most) <= 0:
		say("No room in your bag")


func store_all() -> void:
	for r in _order():
		if bag.count(r) > 0:
			world.village.store(bag, r, bag.count(r))
	_dirty = true


# The bag tidied: its gear first (by kind, then name), then the stacks, food before materials.
func _sort_bag() -> void:
	var gear := []
	for i in Bag.SIZE:
		if bag.items[i] != "":
			gear.append(bag.items[i])
	gear.sort_custom(func(a, b):
		var ka := str(UiKit.item(a).get("kind", "")); var kb := str(UiKit.item(b).get("kind", ""))
		return ka < kb if ka != kb else str(UiKit.item(a).get("name", a)) < str(UiKit.item(b).get("name", b)))
	for i in Bag.SIZE:
		bag.items[i] = gear[i] if i < gear.size() else ""
	var next := gear.size()
	for group in ["Consumables", "Materials"]:
		for r in Bag.RESOURCES:
			if Bag.slotted(r) and bag.count(r) > 0 and UiKit.data.resources.get(r, {}).get("group", "Materials") == group:
				bag.stack_slot[r] = next
				next += 1
	for r in Bag.RESOURCES:
		if Bag.slotted(r) and bag.count(r) > 0 and int(bag.stack_slot.get(r, -1)) < gear.size():
			bag.stack_slot[r] = next
			next += 1
	bag.changed.emit()


# ---- How many to take: a little box over the window ----

func _build_ask(hud: Node) -> void:
	var k := HudStyle.SCALE
	_ask = PanelContainer.new()
	_ask.add_theme_stylebox_override("panel", HudStyle.piece("panelStrong"))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(6 * k))
	_ask.add_child(box)
	_ask_title = HudStyle.label("", 14, "bold", HudStyle.color("accentLight"))
	box.add_child(_ask_title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(4 * k))
	for step in [-10, -1]:
		var b := HudStyle.button(str(step), 12, "slot")
		b.custom_minimum_size = Vector2(36, 28) * k
		b.pressed.connect(func(): _step(step))
		row.add_child(b)
	_ask_field = LineEdit.new()
	_ask_field.custom_minimum_size = Vector2(70, 28) * k
	_ask_field.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ask_field.add_theme_stylebox_override("normal", HudStyle.piece("well"))
	_ask_field.add_theme_stylebox_override("focus", HudStyle.piece("well"))
	_ask_field.add_theme_font_size_override("font_size", roundi(13 * k))
	_ask_field.text_submitted.connect(func(_t): _take_asked())
	row.add_child(_ask_field)
	for step in [1, 10]:
		var b := HudStyle.button("+%d" % step, 12, "slot")
		b.custom_minimum_size = Vector2(36, 28) * k
		b.pressed.connect(func(): _step(step))
		row.add_child(b)
	var all := HudStyle.button("All", 12, "slot")
	all.custom_minimum_size = Vector2(40, 28) * k
	all.pressed.connect(func(): _ask_field.text = str(_most_to_take(_asking)))
	row.add_child(all)
	box.add_child(row)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", int(6 * k))
	var cancel := HudStyle.button("Cancel", 12)
	cancel.pressed.connect(cancel_ask)
	buttons.add_child(cancel)
	var take := HudStyle.button("Take", 12, "barFill", HudStyle.color("ink"))
	take.pressed.connect(_take_asked)
	buttons.add_child(take)
	box.add_child(buttons)
	_ask.visible = false
	hud.add_child(_ask)


func _ask_for(r: String) -> void:
	_asking = r
	_ask_title.text = "Take how many %s?  (up to %d)" % [UiKit.resource_name(r).to_lower(), _most_to_take(r)]
	_ask_field.text = str(_most_to_take(r))
	_ask.visible = true
	_ask.move_to_front()
	_ask_field.grab_focus()
	_ask_field.select_all()


func _step(by: int) -> void:
	_ask_field.text = str(clampi(int(_ask_field.text) + by, 0, _most_to_take(_asking)))


func _take_asked() -> void:
	var n := clampi(int(_ask_field.text), 0, _most_to_take(_asking))
	if n > 0 and world.village.withdraw(bag, _asking, n) <= 0:
		say("No room in your bag")
	cancel_ask()


func cancel_ask() -> void:
	if _ask.visible:
		_ask_field.release_focus()
	_ask.visible = false


# ---- The village totals (Unity's StoragePanel): what's carried and stored of everything, with the limits ----

func _build_totals(hud: Node) -> void:
	_totals = PanelContainer.new()
	_totals.add_theme_stylebox_override("panel", HudStyle.piece("panelStrong"))
	var box := VBoxContainer.new()
	_totals.add_child(box)
	var head := HBoxContainer.new()
	head.add_child(HudStyle.label("Village inventory", 15, "bold", HudStyle.color("accentLight")))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(gap)
	head.add_child(HudStyle.label("E / Esc close", 10, "bold", HudStyle.color("faint")))
	box.add_child(head)
	_totals_list = VBoxContainer.new()
	box.add_child(_totals_list)
	_totals.visible = false
	hud.add_child(_totals)


func show_totals(on: bool) -> void:
	_totals.visible = on
	if not on:
		return
	_totals.move_to_front()
	for ch in _totals_list.get_children():
		ch.queue_free()
	var k := HudStyle.SCALE
	var v := world.village
	var head := HBoxContainer.new()
	for t in [["", 160], ["CARRIED", 70], ["STORED", 110]]:
		var l := HudStyle.label(t[0], 10, "bold", HudStyle.color("faint"))
		l.custom_minimum_size.x = t[1] * k
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if t[0] != "" else HORIZONTAL_ALIGNMENT_LEFT
		head.add_child(l)
	_totals_list.add_child(head)
	var shown := 0
	for r in _order():
		var carried := bag.count(r)
		var stored := v.stored(r)
		if carried + stored <= 0:
			continue
		shown += 1
		var row := HBoxContainer.new()
		var icon := TextureRect.new()
		icon.texture = UiKit.resource_icon(r)
		icon.custom_minimum_size = Vector2(16, 16) * k
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(icon)
		var name := HudStyle.label(UiKit.resource_name(r), 12, "bold")
		name.custom_minimum_size.x = 140 * k
		row.add_child(name)
		var c := HudStyle.label("%d / %d" % [carried, Village.base_cap(r)] if r != "Gold" else str(carried), 12, "pixel", HudStyle.color("muted"))
		c.custom_minimum_size.x = 70 * k
		c.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(c)
		var full := stored >= v.stash_cap(r)
		var s := HudStyle.label("%d / %d" % [stored, v.stash_cap(r)], 12, "pixel", HudStyle.color("coral") if full else HudStyle.color("text"))
		s.custom_minimum_size.x = 110 * k
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(s)
		_totals_list.add_child(row)
	if shown == 0:
		_totals_list.add_child(HudStyle.label("Nothing carried or stored yet.", 12, "body", HudStyle.color("muted")))
	_totals_list.add_child(HudStyle.label("Gear stored: %d / %d slots" % [v.items.size(), v.item_slots()], 11, "body", HudStyle.color("muted")))


## One cell of the grids: its slot, what's in it (an icon, or a tile with initials for gear without one) and a count.
class Cell extends Control:
	var on_click := Callable()
	var shut := false
	var _icon: Texture2D
	var _tile := Color.TRANSPARENT
	var _initials := ""
	var _count := ""
	var _count_c := Color.WHITE

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func show_nothing() -> void:
		_icon = null
		_tile = Color.TRANSPARENT
		_initials = ""
		_count = ""

	func show_stack(r: String, n: int, c: Color) -> void:
		show_nothing()
		_icon = UiKit.resource_icon(r)
		_count = str(n)
		_count_c = c

	func show_item(name: String) -> void:
		show_nothing()
		var it := UiKit.item(name)
		_icon = UiKit.sprite_texture(int(it.get("icon", -1)))
		if _icon == null:
			_tile = UiKit.kind_color(it.get("kind", ""))
			_initials = UiKit.initials(it.get("name", name))

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_style_box(HudStyle.piece("slot", Color(1, 1, 1, 0.35) if shut else Color.WHITE), r)
		var inner := r.grow(-7 * HudStyle.SCALE)
		var f := HudStyle.font("bold")
		if f == null:
			f = get_theme_default_font()
		if _tile.a > 0:
			draw_rect(inner, _tile)
			draw_string(f, inner.position + Vector2(0, inner.size.y * 0.66), _initials, HORIZONTAL_ALIGNMENT_CENTER, inner.size.x, roundi(13 * HudStyle.SCALE), Color.WHITE)
		elif _icon != null:
			draw_texture_rect(_icon, inner, false)
		if _count != "":
			var p := HudStyle.font("pixel")
			if p == null:
				p = f
			var at := Vector2(3, size.y - 4)
			var px := roundi(11 * HudStyle.SCALE)
			draw_string_outline(p, at, _count, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 6, px, 4, Color(0, 0, 0, 0.75))
			draw_string(p, at, _count, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 6, px, _count_c)

	func _gui_input(event: InputEvent) -> void:
		if shut or not on_click.is_valid():
			return
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			on_click.call(event.ctrl_pressed)
			accept_event()
