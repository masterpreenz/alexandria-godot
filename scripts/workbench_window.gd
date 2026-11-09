class_name WorkbenchWindow
extends PanelContainer
## The workbenches, for Miko (from Unity's Workbench): at one (a tool, alchemy or cooking workbench), E opens what it
## can make as a grid, what she can make now first and the rest under a red veil. Clicking one shows what it is, what
## it takes (from her bag and, in the village, the chests; how much she has of each) and a Craft button. Tools for the
## villagers go straight into the village's storage; everything else into her bag, or storage when the bag is full.
## Some of the cooking bench's dishes need a skilled cook.

const COLUMNS := 4
const CELL := 64.0

var world: World
var miko: Miko
var benches: Dictionary          ## build.json's workbenches: prop name -> {title, skill, recipes, reach}
var prompt: Label
var bench: Dictionary = {}       ## the one open
var bench_at := Vector2.ZERO
var picked: Dictionary = {}
var _shown: Array = []
var _title: Label
var _grid: GridContainer
var _pic: ChestWindow.Cell
var _name: Label
var _kind: Label
var _info: Label
var _cost: RichTextLabel
var _craft: Button
var _pressed := false
var _esc := false
var _dirty := true


func setup(w: World, who: Miko, data: Dictionary, hud: Node) -> void:
	world = w
	miko = who
	benches = data
	var k := HudStyle.SCALE
	prompt = HudStyle.label("", 16, "bold")
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	prompt.offset_top = -210
	prompt.offset_bottom = -180
	prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	prompt.visible = false
	hud.add_child(prompt)
	add_theme_stylebox_override("panel", HudStyle.piece("panelStrong"))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(8 * k))
	add_child(box)
	var head := HBoxContainer.new()
	_title = HudStyle.label("", 16, "bold")
	head.add_child(_title)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(gap)
	head.add_child(HudStyle.label("E or Esc to close", 11, "body", HudStyle.color("muted")))
	box.add_child(head)
	var sides := HBoxContainer.new()
	sides.add_theme_constant_override("separation", int(14 * k))
	box.add_child(sides)
	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", int(8 * k))
	_grid.add_theme_constant_override("v_separation", int(8 * k))
	_grid.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_grid.custom_minimum_size = Vector2(COLUMNS * (CELL + 8), (CELL + 8) * 4) * k
	sides.add_child(_grid)
	# The details: what it is, what it takes, and Craft.
	var well := PanelContainer.new()
	well.add_theme_stylebox_override("panel", HudStyle.piece("well"))
	well.custom_minimum_size = Vector2(250, 300) * k
	sides.add_child(well)
	var d := VBoxContainer.new()
	d.add_theme_constant_override("separation", int(6 * k))
	well.add_child(d)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", int(10 * k))
	_pic = ChestWindow.Cell.new()
	_pic.custom_minimum_size = Vector2(52, 52) * k
	_pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(_pic)
	var names := VBoxContainer.new()
	_name = HudStyle.label("", 15, "bold")
	names.add_child(_name)
	_kind = HudStyle.label("", 11, "body", HudStyle.color("muted"))
	_kind.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_kind.custom_minimum_size.x = 170 * k
	names.add_child(_kind)
	top.add_child(names)
	d.add_child(top)
	_info = HudStyle.label("", 12, "body")
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size.x = 230 * k
	d.add_child(_info)
	d.add_child(HudStyle.label("NEEDS", 11, "bold", HudStyle.color("muted")))
	_cost = RichTextLabel.new()
	_cost.bbcode_enabled = true
	_cost.fit_content = true
	_cost.scroll_active = false
	_cost.custom_minimum_size.x = 230 * k
	var f := HudStyle.font("body")
	if f != null:
		_cost.add_theme_font_override("normal_font", f)
	_cost.add_theme_font_size_override("normal_font_size", roundi(12 * k))
	_cost.add_theme_color_override("default_color", HudStyle.color("text"))
	_cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	d.add_child(_cost)
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	d.add_child(fill)
	_craft = HudStyle.button("Craft", 13)
	_craft.custom_minimum_size = Vector2(120, 36) * k
	_craft.size_flags_horizontal = Control.SIZE_SHRINK_END
	_craft.pressed.connect(_on_craft)
	d.add_child(_craft)
	miko.bag.changed.connect(func(): _dirty = true)
	world.village.changed.connect(func(): _dirty = true)
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_E:
			_pressed = true
		elif event.keycode == KEY_ESCAPE and visible:
			_esc = true
			get_viewport().set_input_as_handled()


# The nearest workbench in reach: [prop name, where] or [].
func _nearest(slack := 1.0) -> Array:
	var best := []
	var best_d := INF
	for prop in benches:
		var reach := float(benches[prop].get("reach", 1.3)) * slack * world.px
		for at in world.props_named(prop):
			var dd: float = miko.position.distance_to(at)
			if dd < reach and dd < best_d:
				best_d = dd
				best = [prop, at]
	return best


func _process(_delta: float) -> void:
	var pressed := _pressed
	var esc := _esc
	_pressed = false
	_esc = false
	if visible:
		prompt.visible = false
		if esc or pressed or miko.position.distance_to(bench_at) > float(bench.get("reach", 1.3)) * 1.2 * world.px:
			visible = false
			return
		if _dirty:
			_refresh()
		reset_size()
		position = ((get_viewport_rect().size - size) / 2.0).round() + Vector2(0, 20)
		return
	var near := [] if miko.locked or CharacterPanel.up() else _nearest()
	prompt.visible = not near.is_empty()
	if near.is_empty():
		return
	prompt.text = "E  Use workbench"
	if pressed:
		open(near[0], near[1])


func open(prop: String, at: Vector2) -> void:
	bench = benches[prop]
	bench_at = at
	_title.text = str(bench.get("title", "Workbench"))
	picked = {}
	visible = true
	_refresh()


func _skill() -> int:
	return maxi(0, LifeSkills.NAMES.find(str(bench.get("skill", "Building"))))


## The skill level a recipe takes here: the cooking bench's stews and soups take a skilled cook.
func _need(r: Dictionary) -> int:
	return 3 if str(bench.get("skill", "")) == "Cooking" and bool(r.makesResource) and r.resource in ["CarrotStew", "CabbageSoup"] else 1


static func recipe_name(r: Dictionary) -> String:
	if bool(r.makesResource):
		var n := UiKit.resource_name(r.resource)
		return n + (" x%d" % int(r.amount) if int(r.amount) > 1 else "")
	return str(UiKit.item(r.item).get("name", r.item))


func _can(r: Dictionary) -> bool:
	return world.village.can_afford(miko.bag, miko, r.cost)


# What she can make now first (then by name), the rest veiled in red; and the picked one's details.
func _refresh() -> void:
	_dirty = false
	_shown = bench.get("recipes", []).duplicate()
	_shown.sort_custom(func(a, b):
		var ca := _can(a)
		var cb := _can(b)
		return ca if ca != cb else recipe_name(a) < recipe_name(b))
	if picked.is_empty() and not _shown.is_empty():
		picked = _shown[0]
	while _grid.get_child_count() < _shown.size():
		var c := RecipeCell.new()
		c.custom_minimum_size = Vector2(CELL, CELL) * HudStyle.SCALE
		c.window = self
		_grid.add_child(c)
	for i in _grid.get_child_count():
		var c: RecipeCell = _grid.get_child(i)
		c.visible = i < _shown.size()
		if not c.visible:
			continue
		var r: Dictionary = _shown[i]
		c.recipe = r
		c.on = r == picked
		c.veiled = not _can(r)
		_show(c, r)
		c.queue_redraw()
	_details()


func _show(c: ChestWindow.Cell, r: Dictionary) -> void:
	if bool(r.makesResource):
		c.show_stack(r.resource, 0, Color.WHITE)
		c._count = ""
	else:
		c.show_item(r.item)
	c.queue_redraw()


func _details() -> void:
	var r := picked
	if r.is_empty():
		return
	_show(_pic, r)
	_name.text = recipe_name(r)
	var info := ""
	if bool(r.makesResource):
		var res: String = r.resource
		var kind := "Potion" if res.ends_with("Potion") else ("Food" if UiKit.data.resources.get(res, {}).get("group", "") == "Consumables" else "Material")
		_kind.text = kind + ("  ·  goes to storage" if bool(r.get("toStorage", false)) else "  ·  into your bag")
		if res == "Bottle":
			info = "An empty bottle: potions are made in it."
		var need := _need(r)
		if need > 1:
			info += ("\n" if info != "" else "") + "Needs %s %d (yours: %d)" % [str(bench.skill).to_lower(), need, LifeSkills.get_level(_skill())]
	else:
		var it := UiKit.item(r.item)
		_kind.text = str(it.get("label", "")) + ("  ·  for the villagers (goes to storage)" if bool(r.get("toStorage", false)) else "  ·  into your bag")
		var lines := [str(it.get("description", ""))]
		for st in it.get("stats", []):
			lines.append("+%s%s %s" % [CharacterStats.fmt(float(st[1])), st[2], st[0]])
		if int(it.get("bagSlots", 0)) > 0:
			lines.append("+%d slots" % int(it.bagSlots))
		info = "\n".join(lines.filter(func(l): return l != ""))
	_info.text = info
	# What it takes, and how much she has of each.
	var green := HudStyle.color("green").to_html(false)
	var lines := []
	for c in Village.sum(r.cost):
		var have := world.village.have(miko.bag, miko, c[0])
		lines.append("[color=#%s]%d %s[/color]  (you have %d)" % [green if have >= c[1] else "ff8a6a", c[1], UiKit.resource_name(c[0]).to_lower(), have])
	_cost.text = "\n".join(lines) if not lines.is_empty() else "nothing"
	var ok := _can(r) and _need(r) <= LifeSkills.get_level(_skill())
	_craft.disabled = not ok
	_craft.text = "Craft" if ok else "Not enough"


func _on_craft() -> void:
	if not picked.is_empty():
		_make(picked)


func pick(r: Dictionary) -> void:
	picked = r
	_refresh()


func _make(r: Dictionary) -> void:
	var v := world.village
	var bag := miko.bag
	var at := bench_at + Vector2(0, -1.2 * world.px)
	var red := Color(1, 0.6, 0.5)
	if _need(r) > LifeSkills.get_level(_skill()):
		FloatingText.spawn(world, "Needs %s %d" % [str(bench.skill).to_lower(), _need(r)], at, red)
		return
	if bool(r.makesResource):
		if not v.pay(bag, miko, r.cost):
			FloatingText.spawn(world, "Not enough to make it", at, red)
			return
		# Into the bag (a slot of its own if it's new), else storage, else the ground beside her.
		v.give(bag, miko, r.resource, int(r.amount), miko.position)
		LifeSkills.practise(_skill(), miko)
		Puffs.burst(world, bench_at + Vector2(0, -0.4 * world.px), 0.5, 10)
		FloatingText.spawn(world, "Made: %s" % recipe_name(r), at, HudStyle.color("accentLight"))
		_refresh()
		return
	if not _can(r):
		FloatingText.spawn(world, "Not enough to make it", at, red)
		return
	# Somewhere to put it first: nothing's paid if there's no room.
	var into_storage := bool(r.get("toStorage", false)) or bag.free_slot() < 0
	if into_storage and v.items.size() >= v.item_slots():
		FloatingText.spawn(world, "Storage is full of items" if bool(r.get("toStorage", false)) else "No room in the bag or storage", at, red)
		return
	if not v.pay(bag, miko, r.cost):
		return
	if into_storage:
		v.store_crafted(r.item)
	else:
		bag.items[bag.free_slot()] = r.item
		bag.changed.emit()
	LifeSkills.practise(_skill(), miko)
	Puffs.burst(world, bench_at + Vector2(0, -0.4 * world.px), 0.5, 10)
	FloatingText.spawn(world, "Made: %s%s" % [recipe_name(r), " (in storage)" if into_storage else ""], at, HudStyle.color("accentLight"))
	_refresh()


## A recipe in the grid: its slot (amber when picked), what it makes, and a red veil when she can't make it now.
class RecipeCell extends ChestWindow.Cell:
	var window: WorkbenchWindow
	var recipe: Dictionary
	var on := false
	var veiled := false

	func _draw() -> void:
		super._draw()
		if on:
			draw_rect(Rect2(Vector2.ZERO, size).grow(-1), HudStyle.color("accent"), false, 3.0)
		if veiled:
			draw_rect(Rect2(Vector2.ZERO, size), Color(0.85, 0.15, 0.1, 0.42))

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			window.pick(recipe)
			accept_event()
