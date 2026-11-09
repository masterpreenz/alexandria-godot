class_name BuildMode
extends Node2D
## Build mode (from Unity's BuildMode and BuildCatalog; B, or the hotbar's Build button), its placing engine and its
## feedback in the world; the interface is the [BuildBar]. Everything buildable (build.json's catalogue: grounds,
## laid floors, walls and props, each with its category, tier, cost and what must be built first) is placed with the
## Place tool, paying its cost per piece from Miko's bag and, in the village, its chests; Demolish (X) takes one layer
## off a cell per click (a plan first, then the top prop, a wall, then the floor back to how the map loaded) and
## refunds half. Floors paint with a 1x1 to 3x3 brush and drag; R turns laid floors that can turn (Shift+R
## alternates them); walls go on the grid line nearest the mouse, one length per drag step; props go on the cell
## (Alt: exactly where clicked, spaced along a drag), plants at the brush's size. Laid floors, walls and village
## things only go inside the village; nothing is built on the map's roads or in water (paving the main road is
## fine). Blueprint mode (N) plans floors and walls for the villagers instead (Start building marks them ready).
## Every stroke can be undone and redone (Ctrl+Z, Ctrl+Y or Ctrl+Shift+Z). Miko holds still while it's open and
## WASD moves the view.

signal changed

const CATEGORIES := ["Landmarks", "Houses", "Walls", "Floors", "Terrain", "Storage", "Crafting", "Comfort", "Light", "Farming", "Decor"]
const HISTORY := 50
const BLOCKED := Color(1, 0.35, 0.3, 0.75)

static var active: BuildMode

var world: World
var miko: Miko
var items: Array = []             ## the catalogue, in category order
var settings: Dictionary
var open := false
var tool := "Place"               ## Place or Demolish
var selected: Dictionary = {}
var blueprint := false
var brush := 0
var turn := false
var auto_turn := false
var prop_turn := 0
var hover := {}                   ## what the cursor would do: {show, title, status, costs, refund, note, demolish}
var _undo: Array = []
var _redo: Array = []
var _stroke_start: Variant = null
var _stroke_cells := {}
var _last_cell: Variant = null
var _last_free: Variant = null
var _wall_along_y: Variant = null
var _tool_clicked := false
var _said := 0.0
# What's drawn this frame.
var _cells: Array = []            ## cells under the cursor
var _cell_colour := Color.WHITE
var _wall_ghost: Variant = null   ## [a, b] px
var _prop_ghost: Dictionary = {}  ## {sprite, at, scale, flip, colour}
var _ring := 0.0
var _ring_at := Vector2.ZERO
var _ring_ok := true


func setup(w: World, who: Miko, data: Dictionary) -> void:
	world = w
	miko = who
	active = self
	settings = data.get("buildMode", {})
	z_as_relative = false
	z_index = 4080  # over the world and the mist veil, under floating text
	var rank := {}
	for i in CATEGORIES.size():
		rank[CATEGORIES[i]] = i
	var list: Array = data.get("catalog", []).duplicate()
	var order := {}
	for i in list.size():
		order[list[i].name + list[i].kind] = i
	list.sort_custom(func(a, b):
		var ra: int = rank.get(a.category, 99)
		var rb: int = rank.get(b.category, 99)
		return ra < rb if ra != rb else order[a.name + a.kind] < order[b.name + b.kind])
	items = list
	for it in items:
		if it.kind == "Floor":
			selected = it
			break


static func is_open() -> bool:
	return active != null and active.open


func toggle() -> void:
	set_open(not open)


func set_open(on: bool) -> void:
	if on == open:
		return
	open = on
	_end_stroke()
	miko.locked = on
	var caster: SpellCaster = world.get_node_or_null("Caster")
	if caster != null and on and caster.aiming != "":
		caster.toggle_aiming(caster.aiming)
	var hotbar: Node = get_tree().current_scene.get_node_or_null("Hud/Hotbar")
	if hotbar != null:
		hotbar.visible = not on
	queue_redraw()
	changed.emit()


# ---- The catalogue ----

func kind_of(it: Dictionary) -> String:
	return str(it.get("kind", ""))


func locked(it: Dictionary) -> bool:
	return str(it.get("lockedBy", "")) != "" and not world.props.has(it.lockedBy)


## Ready, Short or Locked.
func status_of(it: Dictionary) -> String:
	if it.is_empty():
		return "Ready"
	if locked(it):
		return "Locked"
	return "Ready" if world.village.can_afford(miko.bag, miko, it.cost) else "Short"


func item_for(kind: String, name: String) -> Dictionary:
	for it in items:
		if it.name == name and (it.kind == kind or (kind == "Floor" and it.kind == "Ground") or (kind == "Ground" and it.kind == "Floor")):
			return it
	return {}


func missing(cost: Array) -> String:
	var parts := []
	for c in Village.sum(cost):
		var have := world.village.have(miko.bag, miko, c[0])
		if have < c[1]:
			parts.append("%d more %s" % [c[1] - have, UiKit.resource_name(c[0]).to_lower()])
	return "Need " + ", ".join(parts)


func select(it: Dictionary) -> void:
	selected = it
	tool = "Place"
	if it.is_empty() or (kind_of(it) != "Ground" and kind_of(it) != "Floor" and not _sizable(it)):
		brush = 0
	changed.emit()


func set_tool(t: String) -> void:
	tool = t
	_tool_clicked = true
	changed.emit()


func set_brush(i: int) -> void:
	brush = clampi(i, 0, _brush_sizes().size() - 1)
	changed.emit()


func toggle_blueprint() -> void:
	blueprint = not blueprint
	changed.emit()


func start_building() -> void:
	var n := Construction.active.start_building() if Construction.active != null else 0
	_say(("%d pieces ready to build" % n) if n > 0 else "No plans waiting", miko.position, Color(1, 0.86, 0.6), true)
	changed.emit()


func clear_plans() -> void:
	if Construction.active != null:
		Construction.active.clear_drafts()
	changed.emit()


func _brush_sizes() -> Array:
	return settings.get("brushSizes", [1, 2, 3])


func brush_size() -> int:
	return int(_brush_sizes()[brush])


func tool_hint() -> String:
	if tool == "Demolish":
		return "Click a building to remove it · refunds half"
	if selected.is_empty():
		return "Pick something to build"
	if kind_of(selected) == "Ground" or kind_of(selected) == "Floor":
		return "Click to place · drag to paint"
	return "Click to place · drag to paint a line"


func _sizable(it: Dictionary) -> bool:
	if kind_of(it) != "Prop":
		return false
	var cat := str(world.props.types.get(it.name, {}).get("category", ""))
	return cat == "Decorations" or cat == "Trees"


# ---- Input ----

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return
	var k: int = event.keycode
	if k == KEY_B and not event.ctrl_pressed:
		if not open and (CharacterPanel.up() or miko.locked):
			return
		toggle()
		get_viewport().set_input_as_handled()
		return
	if not open:
		return
	var handled := true
	if k == KEY_ESCAPE: set_open(false)
	elif k == KEY_R and event.shift_pressed:
		auto_turn = not auto_turn
		changed.emit()
	elif k == KEY_R:
		turn = not turn
		prop_turn += 1
		changed.emit()
	elif k == KEY_Z and event.ctrl_pressed:
		if event.shift_pressed: redo()
		else: undo()
	elif k == KEY_Y and event.ctrl_pressed: redo()
	elif k == KEY_X: set_tool("Place" if tool == "Demolish" else "Demolish")
	elif k == KEY_N: toggle_blueprint()
	else: handled = false
	if handled:
		get_viewport().set_input_as_handled()


func _over_ui() -> bool:
	var c := get_viewport().gui_get_hovered_control()
	return c != null and c.mouse_filter != Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	if not open:
		return
	# The view: WASD (or the arrows) move it while building.
	var cam := get_viewport().get_camera_2d()
	if cam != null and not (get_viewport().gui_get_focus_owner() is LineEdit):
		var dir := Vector2.ZERO
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): dir.x -= 1
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): dir.x += 1
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): dir.y -= 1
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): dir.y += 1
		cam.position += dir.limit_length(1.0) * 14.0 * world.px * delta / cam.zoom.x
	var point := get_global_mouse_position()
	var over := _over_ui()
	var test := Shots.arg("cursor")
	if test != "":
		# For screenshots: the cursor this many units from Miko (the harness's mouse isn't on the window).
		var p := test.split(",")
		point = miko.position + Vector2(float(p[0]), float(p[1])) * world.px
		over = false
	_place_or_clear(point, world.floors.cell_at(point), over)
	queue_redraw()


# ---- Where things may go ----

func _road_floors() -> Array:
	return settings.get("roadFloors", ["Dirt"])


## Nothing is built on one of the map's roads, or in water.
func no_build(cell: Vector2i) -> bool:
	if world.water_depth(world.floors.cell_centre(cell)) > 0.0:
		return true
	return _road_floors().has(world.floors.original.get(cell, world.floors.base_floor))


## The two main roads across the map, as made: paved anywhere, never built on or grassed over.
func main_road(cell: Vector2i) -> bool:
	var h := FloorMap.ROAD_HALF_WIDTH
	if absi(cell.x) > h and absi(cell.y) > h:
		return false
	if world.water_depth(world.floors.cell_centre(cell)) > 0.0:
		return false
	return _road_floors().has(world.floors.original.get(cell, world.floors.base_floor))


static func _paving(floor: String) -> bool:
	return floor.begins_with("Path")


func _paving_road(cell: Vector2i, floor: String) -> bool:
	return _paving(floor) and world.floors.is_whole(floor) and main_road(cell)


func _wall_no_build(e: WallMap.Edge, type: String) -> bool:
	var end := world.walls.span_end(e, type)
	var step := Vector2i(0, 1) if e.along_y else Vector2i(1, 0)
	var side := Vector2i(-1, 0) if e.along_y else Vector2i(0, -1)
	var v := e.vertex
	while v != end:
		if no_build(v) or no_build(v + side):
			return true
		v += step
	return false


func _village_note() -> String:
	return "Only inside the village (outdoor things go anywhere)" if world.village.founded() else "Place a town banner to found a village first"


func _outside(at: Vector2, say: bool) -> bool:
	if world.village.contains(at):
		return false
	if say:
		_say(_village_note(), at)
	return true


## Why [param it] (a prop) can't stand at [param at], or "".
func why_not(it: Dictionary, at: Vector2) -> String:
	if bool(it.get("indoorsOnly", false)) and (world.roofs == null or not world.roofs.covers(at)):
		return "Only inside a house"
	if bool(it.get("villageOnly", false)) and not world.village.contains(at):
		return "Only inside the village" if world.village.founded() else "Place a town banner first"
	if bool(it.get("onlyOne", false)) and world.props.has(it.name):
		return "There's already a %s" % it.display
	return ""


func _say(text: String, at: Vector2, c: Variant = null, always := false) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	if not always and t - _said < 0.8:
		return
	_said = t
	FloatingText.spawn(world, text, at + Vector2(0, -0.8 * world.px), c if c is Color else HudStyle.color("coral"))


func _pay(it: Dictionary, at: Vector2) -> bool:
	if it.is_empty():
		return true
	if locked(it):
		_say("Build a %s first" % it.lockedBy, at)
		return false
	if world.village.pay(miko.bag, miko, it.cost):
		LifeSkills.practise(LifeSkills.Skill.BUILDING, miko)
		changed.emit()
		return true
	_say(missing(it.cost), at)
	return false


func _refund(it: Dictionary, at: Vector2) -> void:
	if it.is_empty():
		return
	var parts := []
	for c in Village.sum(it.cost):
		var n: int = c[1] / 2
		if n > 0:
			world.village.give(miko.bag, miko, c[0], n, at)
			parts.append("+%d %s" % [n, UiKit.resource_name(c[0]).to_lower()])
	if not parts.is_empty():
		_say(", ".join(parts), at, Color(0.75, 0.95, 0.6), true)


# ---- Placing and clearing ----

func _place_or_clear(point: Vector2, cell: Vector2i, over_ui: bool) -> void:
	var f := world.floors
	var clear := tool == "Demolish"
	var k := kind_of(selected)
	var wall_mode := not clear and k == "Wall"
	var placing_prop := not clear and k == "Prop"
	var placing_free := placing_prop and Input.is_key_pressed(KEY_ALT)
	var prop_scale: float = float(settings.get("propScales", [1, 1.5, 2])[mini(brush, 2)]) if placing_prop and _sizable(selected) else 1.0
	var painting := not clear and (k == "Ground" or k == "Floor")
	var size := brush_size() if painting or clear else 1
	var low := cell - Vector2i.ONE * ((size - 1) / 2)
	var visible := not over_ui and f.in_bounds(cell)
	var edge: WallMap.Edge = world.walls.edge_at(point, _wall_along_y if wall_mode else null, 0.2) if world.walls != null else null
	_wall_along_y = edge.along_y if wall_mode else null
	var status := "Ready" if clear else status_of(selected)
	var laid_floor := painting and f.is_whole(selected.name)
	var structure := not clear and (wall_mode or laid_floor)
	var paving := painting and _paving_road(cell, selected.name)
	var building := not clear and (placing_prop or laid_floor) and not paving
	if paving:
		structure = false
	var outside := structure and _outside(world.walls.vertex_position(edge.vertex) if wall_mode else f.cell_centre(cell), false)
	var why := why_not(selected, f.cell_centre(cell)) if placing_prop else ""
	var can_here := status == "Ready" and not outside and not (building and no_build(cell)) and why == ""
	if wall_mode:
		can_here = can_here and world.walls.can_place(edge, selected.name) and not _wall_no_build(edge, selected.name)
	# What the cursor would do, for the bar's tooltip.
	if clear:
		hover = _demolish_hover(cell, visible)
	elif selected.is_empty():
		hover = {}
	else:
		var note := ""
		if outside: note = _village_note()
		elif status == "Locked": note = "Build a %s first" % selected.lockedBy
		elif status == "Short": note = missing(selected.cost)
		elif building and no_build(cell): note = "Can't build on the road"
		elif why != "": note = why
		elif wall_mode and not world.walls.can_place(edge, selected.name): note = "Doors and windows keep off corners"
		hover = {"show": visible, "title": selected.display, "tier": int(selected.get("tier", 1)), "status": status, "costs": selected.cost, "note": note,
			"plan": blueprint and (wall_mode or laid_floor)}
	# The feedback in the world.
	_cells.clear()
	_wall_ghost = null
	_prop_ghost = {}
	_ring = 0.0
	if visible and not selected.is_empty() or (visible and clear):
		if wall_mode:
			_wall_ghost = [world.walls.vertex_position(edge.vertex), world.walls.vertex_position(world.walls.span_end(edge, selected.name))]
		elif not placing_free:
			for x in size:
				for y in size:
					_cells.append(low + Vector2i(x, y))
		var ok := Color(HudStyle.color("green"), 0.9)
		_cell_colour = HudStyle.color("coral") if clear else (ok if can_here else BLOCKED)
		if blueprint and can_here and structure:
			_cell_colour = Color(0.55, 0.78, 1.0, 0.9)
		if placing_prop:
			var at := point if placing_free else f.cell_centre(cell)
			var turns := int(world.props._turns(world.props.types[selected.name])) if world.props.types.has(selected.name) else 1
			_prop_ghost = {"sprite": world.props.sprite_for(selected.name, prop_turn % maxi(1, turns)), "at": at, "scale": prop_scale,
				"colour": Color(1, 1, 1, 0.6) if can_here else BLOCKED}
			if float(selected.get("ring", 0.0)) > 0.0:
				_ring = float(selected.ring)
				_ring_at = at
				_ring_ok = can_here
	# The mouse.
	var down := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if not down:
		_tool_clicked = false
	var pressed := down and not _tool_clicked
	# Right-click in Place lets go of the picked item.
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and not over_ui and tool == "Place" and not selected.is_empty():
		selected = {}
		changed.emit()
		return
	if not pressed:
		_end_stroke()
		_stroke_cells.clear()
	if over_ui or not pressed or selected.is_empty() and not clear:
		_last_cell = null
		_last_free = null
		return
	if _stroke_start == null:
		_stroke_start = _capture()
	if wall_mode:
		_place_wall(edge, selected.name)
		return
	if placing_free:
		var spacing := float(settings.get("freeSpacing", 0.4)) * world.px * prop_scale
		if _last_free == null or (_last_free as Vector2).distance_to(point) >= spacing:
			if not no_build(f.cell_at(point)) and why_not(selected, point) == "" and _pay(selected, point):
				var turns := int(world.props._turns(world.props.types[selected.name]))
				world.props.place_free(point, selected.name, prop_scale, prop_turn % turns if turns > 1 else -1)
			_last_free = point
		return
	# Fill the cells between this frame and the last, so fast strokes don't skip.
	var from: Vector2i = _last_cell if _last_cell != null else cell
	var steps := maxi(absi(cell.x - from.x), absi(cell.y - from.y))
	for s in steps + 1:
		var t := 0.0 if steps == 0 else float(s) / steps
		var at := Vector2i(roundi(lerpf(from.x, cell.x, t)), roundi(lerpf(from.y, cell.y, t)))
		if placing_prop: _place_prop(at, prop_scale)
		else: _stamp(at, clear)
	_last_cell = cell


func _stamp(centre: Vector2i, clear: bool) -> void:
	var size := brush_size()
	var low := centre - Vector2i.ONE * ((size - 1) / 2)
	var placed := false
	for x in size:
		for y in size:
			var cell := low + Vector2i(x, y)
			if not world.floors.in_bounds(cell):
				continue
			if clear:
				# One layer off each cell per stroke: a click takes one thing.
				if not _stroke_cells.has(cell):
					_stroke_cells[cell] = true
					_clear_one(cell)
			elif auto_turn:
				if not _stroke_cells.has(cell):
					_stroke_cells[cell] = true
					_paint(cell, selected.name, turn)
					placed = true
			else:
				_paint(cell, selected.name, turn)
	# Alternating: each stamp lays its new cells one way, the next the other.
	if placed and world.floors.can_turn(selected.name):
		turn = not turn


func _paint(cell: Vector2i, floor: String, turned: bool) -> void:
	var f := world.floors
	var laid := f.is_whole(floor)
	var paving := _paving_road(cell, floor)
	if laid and no_build(cell) and not paving:
		return
	# The main road stays a road: no grass over it.
	if not laid and floor == f.base_floor and main_road(cell):
		_say("The main road stays: pave it instead", f.cell_centre(cell))
		return
	var changes := (f.get_laid(cell) != floor) if laid else (f.get_floor(cell) != floor)
	if laid and changes and blueprint and Construction.active != null:
		if paving or not _outside(f.cell_centre(cell), true):
			Construction.active.plan_floor(cell, floor, turned and f.can_turn(floor))
		return
	if changes and laid and not paving and _outside(f.cell_centre(cell), true):
		return
	if changes and not _pay(item_for("Floor", floor), f.cell_centre(cell)):
		return
	f.paint(cell, floor, turned)


func _place_wall(e: WallMap.Edge, type: String) -> void:
	var w := world.walls
	if _wall_no_build(e, type) or not w.can_place(e, type):
		return
	var at := w.vertex_position(e.vertex)
	var had := w.get_wall(e)
	if had == type:
		return
	if blueprint and Construction.active != null:
		if not _outside(at, true):
			Construction.active.plan_wall(e, type)
		return
	if _outside(at, true) or not _pay(item_for("Wall", type), at):
		return
	w.place(e, type)


func _place_prop(cell: Vector2i, scale: float) -> void:
	var at := world.floors.cell_centre(cell)
	if no_build(cell) or why_not(selected, at) != "":
		return
	var slot := int(world.props.types[selected.name].slot)
	if world.props.get_prop(cell, slot) == selected.name:
		return
	if not _pay(selected, at):
		return
	var turns := int(world.props._turns(world.props.types[selected.name]))
	world.props.place(cell, selected.name, scale, prop_turn % turns if turns > 1 else -1)


func _clear_one(cell: Vector2i) -> void:
	var f := world.floors
	var at := f.cell_centre(cell)
	# A plan there goes first (nothing to refund).
	if Construction.active != null and Construction.active.remove_at(cell, world.walls.edges_in(cell)):
		return
	var top := world.props.peek_top(cell)
	if world.props.remove_one(cell):
		_refund(item_for("Prop", top), at)
		return
	for e in world.walls.edges_in(cell):
		var before := world.walls.version
		var type := world.walls.get_wall(e)
		world.walls.restore(e)
		if world.walls.version != before:
			if type != "" and world.walls.get_wall(e) != type:
				_refund(item_for("Wall", type), at)
			return
	var laid := f.get_laid(cell)
	var ground := f.get_floor(cell)
	f.restore(cell)
	var gone := laid if laid != "" and f.get_laid(cell) != laid else (ground if ground != "" and f.get_floor(cell) != ground else "")
	if gone != "":
		_refund(item_for("Floor", gone), at)


# What demolishing here would take, and give back.
func _demolish_hover(cell: Vector2i, visible: bool) -> Dictionary:
	var it := {}
	var name := ""
	var top := world.props.peek_top(cell)
	if top != "":
		it = item_for("Prop", top)
		name = str(world.props.types.get(top, {}).get("display", top))
	if name == "":
		for e in world.walls.edges_in(cell):
			var w := world.walls.get_wall(e)
			if w != "":
				it = item_for("Wall", w)
				name = str(world.walls.types[w].get("display", w))
				break
	if name == "":
		var laid := world.floors.get_laid(cell)
		if laid != "":
			it = item_for("Floor", laid)
			name = str(world.floors.types.get(laid, {}).get("display", laid))
	if name == "":
		return {}
	var refund := []
	if not it.is_empty():
		for c in Village.sum(it.cost):
			if c[1] / 2 > 0:
				refund.append([c[0], c[1] / 2])
	return {"show": visible, "title": "Remove " + name, "demolish": true, "refund": refund}


# ---- Undo and redo: whole snapshots of the floors, props, walls, plans, the bag and the stash ----

func _capture() -> Dictionary:
	return {"floors": world.floors.to_json(), "props": world.props.to_json(), "walls": world.walls.to_json(),
		"plans": Construction.active.to_json() if Construction.active != null else "",
		"counts": miko.bag.counts.duplicate(), "slots": miko.bag.stack_slot.duplicate(), "stash": world.village.stash.duplicate()}


func _end_stroke() -> void:
	if _stroke_start == null:
		return
	var before: Dictionary = _stroke_start
	_stroke_start = null
	var now := _capture()
	if now.floors == before.floors and now.props == before.props and now.walls == before.walls and now.plans == before.plans:
		return
	_undo.append(before)
	if _undo.size() > HISTORY:
		_undo.pop_front()
	_redo.clear()
	changed.emit()


func can_undo() -> bool:
	return not _undo.is_empty()


func can_redo() -> bool:
	return not _redo.is_empty()


func undo() -> void:
	_step(_undo, _redo)


func redo() -> void:
	_step(_redo, _undo)


func _step(from: Array, to: Array) -> void:
	_end_stroke()
	if from.is_empty():
		return
	to.append(_capture())
	var st: Dictionary = from.pop_back()
	if world.floors.to_json() != st.floors: world.floors.from_json(st.floors)
	if world.props.to_json() != st.props: world.props.from_json(st.props)
	if world.walls.to_json() != st.walls: world.walls.from_json(st.walls)
	if Construction.active != null and st.plans != "": Construction.active.from_json(st.plans)
	miko.bag.counts = st.counts.duplicate()
	miko.bag.stack_slot = st.slots.duplicate()
	miko.bag.changed.emit()
	world.village.stash = st.stash.duplicate()
	world.village.changed.emit()
	changed.emit()


# ---- Drawing the feedback ----

func _draw() -> void:
	if not open:
		return
	var f := world.floors
	for c in _cells:
		var pts := PackedVector2Array([f.corner(Vector2(c)), f.corner(Vector2(c) + Vector2(1, 0)), f.corner(Vector2(c) + Vector2(1, 1)), f.corner(Vector2(c) + Vector2(0, 1))])
		draw_colored_polygon(pts, Color(_cell_colour, 0.18))
		pts.append(pts[0])
		draw_polyline(pts, _cell_colour, 0.03 * world.px, true)
	if _wall_ghost != null:
		draw_line(_wall_ghost[0], _wall_ghost[1], Color(_cell_colour, 0.35), 0.16 * world.px, true)
		draw_line(_wall_ghost[0], _wall_ghost[1], _cell_colour, 0.05 * world.px, true)
	if not _prop_ghost.is_empty() and int(_prop_ghost.sprite) >= 0:
		var info: Dictionary = world.sprites[int(_prop_ghost.sprite)]
		var tex := world._texture(info.tex)
		var k := float(_prop_ghost.scale) * world.px / float(info.ppu)
		var region := Rect2(info.rect[0], info.rect[1], info.rect[2], info.rect[3])
		var at: Vector2 = _prop_ghost.at - Vector2(float(info.pivot[0]), float(info.pivot[1])) * k
		draw_texture_rect_region(tex, Rect2(at, region.size * k), region, _prop_ghost.colour)
	if _ring > 0.0:
		var c := Color(HudStyle.color("green"), 0.8) if _ring_ok else BLOCKED
		draw_set_transform(_ring_at, 0.0, Vector2(1, 0.5))
		draw_arc(Vector2.ZERO, _ring * world.px, 0.0, TAU, 64, c, 0.04 * world.px, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
