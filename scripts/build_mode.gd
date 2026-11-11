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
## things only go inside the village; nothing is built on the map's roads or in water. Paths (brick, cobble) go
## anywhere on dry land, out of the village too, and over the main road. Blueprint mode (N) plans floors and walls for the villagers instead (Start building marks them ready).
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
var _grid: GridLines
var tool := "Place"               ## Place or Demolish
## What Demolish takes: "All" (a plan, then a prop, a wall, the floor), or only "Walls", "Floors", "Decor" (props but
## farm plots) or "Farm" (farm plots).
var demolish_only := "All"
const DEMOLISH_KINDS := ["All", "Walls", "Floors", "Decor", "Farm"]
var selected: Dictionary = {}
var blueprint := false
var brush := 0
var turn := false
var auto_turn := false
var wall_turned := false           ## barricades placed showing their other face (spikes towards the viewer): R
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
var _wall_art: Array = []         ## the wall's own art over that line: [[sprite, mirrored, at]] (WallMap.ghost_pieces)
var _ghost_tint := Color(1, 1, 1, 0.6)
var _floor_art := ""              ## a floor being laid: its tiles drawn see-through on the cells   ## what the art of a wall or prop being placed is drawn in
var _prop_ghost: Dictionary = {}  ## {sprite, at, scale, flip, colour}
var _ring := 0.0
var _ring_at := Vector2.ZERO
var _ring_ok := true


func setup(w: World, who: Miko, data: Dictionary) -> void:
	world = w
	miko = who
	active = self
	settings = data.get("buildMode", {})
	# The tile grid over the ground while building (under walls and everything standing).
	_grid = GridLines.new()
	_grid.build = self
	_grid.visible = false
	_grid.visibility_layer = MapMarks.HIDDEN_LAYER
	w.add_ground_layer(_grid, -9970)
	z_as_relative = false
	visibility_layer = MapMarks.HIDDEN_LAYER   # build mode's feedback stays off the maps
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
	_add_houses()


static func is_open() -> bool:
	return active != null and active.open


func toggle() -> void:
	set_open(not open)


func set_open(on: bool) -> void:
	if on == open:
		return
	if not on:
		put_back_carried()
		picked_room = null
		hover_room = null
		_house_ghost = {}
		hide_buildings = false
		_show_buildings()
	open = on
	_grid.visible = on
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


func item_for(kind: String, nm: String) -> Dictionary:
	for it in items:
		if it.name == nm and (it.kind == kind or (kind == "Floor" and it.kind == "Ground") or (kind == "Ground" and it.kind == "Floor")):
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
	# The click that picked it (in the bar) isn't a click on the world: nothing's placed until the button comes up.
	_tool_clicked = true
	if it.is_empty() or (kind_of(it) != "Ground" and kind_of(it) != "Floor" and not _sizable(it)):
		brush = 0
	changed.emit()


func set_tool(t: String) -> void:
	if t != "Move":
		put_back_carried()
	if t != "Inspect":
		picked_room = null
	_house_ghost = {}
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
	if tool == "Move":
		return "Click its new spot · RMB puts it back" if not carried.is_empty() else "Click a building, then click its new spot"
	if tool == "Copy":
		return "Click anything built to copy it"
	if tool == "Inspect":
		return "Click a house to see what it is and change its roof"
	if kind_of(selected) == "House":
		return "Click to build the house · R turns it"
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
		wall_turned = not wall_turned
		prop_turn += 1
		preset_turn = (preset_turn + 1) % 4
		if not carried.is_empty():
			carried.turn = int(carried.turn) + 1
		changed.emit()
	elif k == KEY_Z and event.ctrl_pressed:
		if event.shift_pressed: redo()
		else: undo()
	elif k == KEY_Y and event.ctrl_pressed: redo()
	elif k == KEY_X: set_tool("Place" if tool == "Demolish" else "Demolish")
	elif k == KEY_N: toggle_blueprint()
	elif k == KEY_M: set_tool("Place" if tool == "Move" else "Move")
	elif k == KEY_V: set_tool("Place" if tool == "Copy" else "Copy")
	elif k == KEY_H: set_tool("Place" if tool == "Inspect" else "Inspect")
	elif k == KEY_U: toggle_hide_buildings()
	else: handled = false
	if handled:
		get_viewport().set_input_as_handled()


func _over_ui() -> bool:
	var c := get_viewport().gui_get_hovered_control()
	return c != null and c.mouse_filter != Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	var __t := Time.get_ticks_usec()
	_process_timed(delta)
	Perf.add(&"build_mode.process", __t)


func _process_timed(delta: float) -> void:
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
	if hide_buildings:
		_hide_buildings()
	var cell := world.floors.cell_at(point)
	if tool == "Move" or tool == "Copy":
		_house_ghost = {}
		_move_or_copy(point, cell, over)
	elif tool == "Inspect":
		_house_ghost = {}
		_inspect(point, over)
	elif kind_of(selected) == "House":
		_cells.clear()
		_wall_ghost = null
		_wall_art = []
		_floor_art = ""
		_prop_ghost = {}
		_group_ghost = []
		_ring = 0.0
		_house_cursor(cell, over, not over and world.floors.in_bounds(cell))
	else:
		_house_ghost = {}
		_place_or_clear(point, cell, over)
	queue_redraw()


# ---- Where things may go ----

func _road_floors() -> Array:
	return settings.get("roadFloors", ["Dirt"])


## Nothing is built on one of the map's roads, or in water.
func no_build(cell: Vector2i) -> bool:
	if Mountains.covers(cell):
		return true
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


static func _paving(floor_name: String) -> bool:
	return floor_name.begins_with("Path")


# A path (brick or cobble) may be laid anywhere on dry land, in the village or out of it (roads between places), the
# main road included.
func _paving_road(cell: Vector2i, floor_name: String) -> bool:
	return _paving(floor_name) and world.floors.is_whole(floor_name) and not world.wet(world.floors.cell_centre(cell))


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


func _outside(at: Vector2, say: bool, margin := 0.0) -> bool:
	if world.village.contains(at, margin):
		return false
	if say:
		_say(_village_note(), at)
	return true


## Barricades and gates (walls with health) may go up to this many tiles past the village's edge: a ring round it.
const DEFENCE_MARGIN := 2.0

# Whether the wall [param type] on [param e] would be out of bounds: both its ends in the village, or for a barricade
# or gate within [constant DEFENCE_MARGIN] tiles of it.
func _wall_outside(e: WallMap.Edge, type: String, say: bool) -> bool:
	var w := world.walls
	var margin := DEFENCE_MARGIN if w.max_hp(type) > 0.0 else 0.0
	var a := w.vertex_position(e.vertex)
	var b := w.vertex_position(w.span_end(e, type))
	return _outside(a, say, margin) or _outside(b, say and not _outside(a, false, margin), margin)


## A fireplace stands with its back against a wall and faces out from it: the way it's turned on [param cell] (0 its
## back to the wall up and to the right, opening down-left; 1 its back up and to the left, opening down-right), or
## -1 where there's no wall behind, -2 in a back corner (a wall both ways: it doesn't go there).
func hearth_turn(cell: Vector2i) -> int:
	var right := _solid_wall(WallMap.Edge.new(cell + Vector2i(1, 0), true))
	var left := _solid_wall(WallMap.Edge.new(cell + Vector2i(0, 1), false))
	if right and left:
		return -2   # (a back corner: no)
	return 0 if right else (1 if left else -1)


# A whole wall on [param e]: not a fence or barricade, a doorway or a door.
func _solid_wall(e: WallMap.Edge) -> bool:
	var t := world.walls.get_wall(e)
	if t == "":
		return false
	var type: Dictionary = world.walls.types[t]
	return not bool(type.fence) and float(type.opening) <= 0.0 and str(type.toggle) == ""


# The turn [param prop_name] is placed with on [param cell]: the one picked (R), or for a fireplace, its wall's.
func _turn_on(prop_name: String, cell: Vector2i) -> int:
	if prop_name == "Fireplace":
		return maxi(0, hearth_turn(cell))
	var turns := int(world.props._turns(world.props.types[prop_name])) if world.props.types.has(prop_name) else 1
	return prop_turn % maxi(1, turns)


## Why [param it] (a prop) can't stand at [param at], or "".
## How many of [param it] may stand now (its "limit": one number for each time the village has grown, the last
## standing for any more), or -1 for as many as you like.
func limit_of(it: Dictionary) -> int:
	var l: Variant = it.get("limit")
	if not (l is Array) or (l as Array).is_empty():
		return -1
	return int(l[clampi(world.village.growths(), 0, (l as Array).size() - 1)])


func why_not(it: Dictionary, at: Vector2, moving: Dictionary = {}) -> String:
	if it.is_empty():
		return ""
	# Down in the cellar: storage only (chests and the like).
	if Cellars.room_has(world.floors.cell_at(at)) and str(it.get("category", "")) != "Storage":
		return "Only storage goes in the cellar"
	if str(it.name) == "Fireplace":
		var facing := hearth_turn(world.floors.cell_at(at))
		if facing < 0:
			return "Not in a corner" if facing == -2 else "A fireplace goes against a back wall"
	if _use_cells().has(world.floors.cell_at(at)):
		return "Keep clear: the way in to a bed or chest"
	if bool(it.get("indoorsOnly", false)) and (world.roofs == null or not world.roofs.covers(at)):
		return "Only inside a house"
	if bool(it.get("outdoorsOnly", false)) and world.roofs != null and world.roofs.covers(at):
		return "Only outdoors"
	if bool(it.get("nearWater", false)) and not Fishing.water_near(world, at):
		return "Only by the water (a river, a lake or a pond)"
	if bool(it.get("villageOnly", false)) and not world.village.contains(at):
		return "Only inside the village" if world.village.founded() else "Place a town banner first"
	if bool(it.get("onlyOne", false)) and world.props.has(it.name) and moving.is_empty():
		return "There's already a %s" % it.display
	# So many of it and no more, by how far the village has grown.
	var most := limit_of(it)
	if most >= 0 and moving.is_empty() and world.props_named(str(it.name)).size() >= most:
		if most >= int((it.limit as Array).max()):
			return "No more than %d of these" % most
		return "Only %d at this village level (grow the village for more)" % most
	# Furniture stands within one room or yard: never across a wall or fence.
	var t := int(moving.turn) if not moving.is_empty() else prop_turn
	var sc := float(moving.scale) if not moving.is_empty() else 1.0
	# (a fireplace is built into its wall: it's meant to touch it)
	if not _sizable(it) and str(it.name) != "Fireplace" and _across_wall(it.name, at, t, sc):
		return "Can't stand across a wall"
	if bool(it.get("crystal", false)):
		return _crystal_why(at, moving.pos if not moving.is_empty() else null)
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
	@warning_ignore("integer_division")
	var low := cell - Vector2i.ONE * ((size - 1) / 2)
	var shown := not over_ui and f.in_bounds(cell)
	var edge: WallMap.Edge = world.walls.edge_at(point, _wall_along_y if wall_mode else null, 0.2) if world.walls != null else null
	@warning_ignore("incompatible_ternary")
	_wall_along_y = edge.along_y if wall_mode else null
	var status := "Ready" if clear else status_of(selected)
	var laid_floor := painting and f.is_whole(selected.name)
	var structure := not clear and (wall_mode or laid_floor)
	var paving := painting and _paving_road(cell, selected.name)
	var building := not clear and (placing_prop or laid_floor) and not paving
	if paving:
		structure = false
	var outside := structure and (_wall_outside(edge, selected.name, false) if wall_mode else _outside(f.cell_centre(cell), false))
	var why := why_not(selected, f.cell_centre(cell)) if placing_prop else ""
	var can_here := status == "Ready" and not outside and not (building and no_build(cell)) and why == ""
	if wall_mode:
		can_here = can_here and world.walls.can_place(edge, selected.name) and not _wall_no_build(edge, selected.name)
	# What the cursor would do, for the bar's tooltip.
	if clear:
		hover = _demolish_hover(cell, shown)
	elif selected.is_empty():
		hover = {}
	else:
		var note := ""
		if outside: note = _village_note()
		elif status == "Locked": note = "Build a %s first" % selected.lockedBy
		elif status == "Short": note = missing(selected.cost)
		elif building and Mountains.covers(cell): note = "Mountains in the way"
		elif building and no_build(cell): note = "Can't build on the road"
		elif why != "": note = why
		elif wall_mode and not world.walls.can_place(edge, selected.name): note = "Doors and windows keep off corners"
		hover = {"show": shown, "title": selected.display, "tier": int(selected.get("tier", 1)), "status": status, "costs": selected.cost, "note": note,
			"plan": blueprint and (wall_mode or laid_floor)}
	# The feedback in the world.
	_cells.clear()
	_wall_ghost = null
	_wall_art = []
	_floor_art = ""
	_prop_ghost = {}
	_group_ghost = []
	_ring = 0.0
	if shown and not selected.is_empty() or (shown and clear):
		if wall_mode:
			_wall_ghost = [world.walls.vertex_position(edge.vertex), world.walls.vertex_position(world.walls.span_end(edge, selected.name))]
			_wall_art = [] if clear else world.walls.ghost_pieces(edge, selected.name, wall_turned)
		elif not placing_free:
			for x in size:
				for y in size:
					_cells.append(low + Vector2i(x, y))
		_floor_art = selected.name if not clear and kind_of(selected) == "Floor" and f.types.has(selected.name) else ""
		var ok := Color(HudStyle.color("green"), 0.9)
		_cell_colour = HudStyle.color("coral") if clear else (ok if can_here else BLOCKED)
		if blueprint and can_here and structure:
			_cell_colour = Color(0.55, 0.78, 1.0, 0.9)
		# The thing itself, see-through: as it'll look, red where it can't go, blue as a plan.
		_ghost_tint = BLOCKED if not can_here else (Color(0.6, 0.82, 1.0, 0.6) if blueprint and structure else Color(1, 1, 1, 0.6))
		if placing_prop:
			var at := point if placing_free else f.cell_centre(cell)
			var turns := int(world.props._turns(world.props.types[selected.name])) if world.props.types.has(selected.name) else 1
			var ghost_turn := _turn_on(selected.name, cell) if turns > 1 else 0
			# (a thing with one picture is mirrored on its odd turns, as it will be when placed)
			var mirrored: bool = turns > 1 and (world.props.types[selected.name].turnSprites as Array).is_empty() and ghost_turn % 2 == 1
			_prop_ghost = {"sprite": world.props.sprite_for(selected.name, ghost_turn), "at": at, "scale": prop_scale,
				"colour": _ghost_tint, "flip": mirrored}
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
				_drop_in([world.props.last_free_node()], 0.0, _prop_sound(selected.name))
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
	@warning_ignore("integer_division")
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


func _paint(cell: Vector2i, floor_name: String, is_turned: bool) -> void:
	var f := world.floors
	var laid := f.is_whole(floor_name)
	var paving := _paving_road(cell, floor_name)
	if laid and no_build(cell) and not paving:
		return
	# The main road stays a road: no grass over it.
	if not laid and floor_name == f.base_floor and main_road(cell):
		_say("The main road stays: pave it instead", f.cell_centre(cell))
		return
	var changes := (f.get_laid(cell) != floor_name) if laid else (f.get_floor(cell) != floor_name)
	if laid and changes and blueprint and Construction.active != null:
		if paving or not _outside(f.cell_centre(cell), true):
			Construction.active.plan_floor(cell, floor_name, is_turned and f.can_turn(floor_name))
		return
	if changes and laid and not paving and _outside(f.cell_centre(cell), true):
		return
	if changes and not _pay(item_for("Floor", floor_name), f.cell_centre(cell)):
		return
	f.paint(cell, floor_name, is_turned)
	if changes:
		drop_sound("land" if laid else ("grass" if floor_name.contains("Grass") else "land"), f.cell_centre(cell))


func _place_wall(e: WallMap.Edge, type: String) -> void:
	var w := world.walls
	if _wall_no_build(e, type) or not w.can_place(e, type) or blocks_way_in(e):
		return
	var at := w.vertex_position(e.vertex)
	var had := w.get_wall(e)
	if had == type:
		# Already there: placed again, it's turned to face the way chosen (R), free.
		var start: WallMap.Edge = w.covering(e)[1]
		if w.is_turned(start) != wall_turned and w.types[type].has("front"):
			w.set_turned(start, wall_turned)
			drop_sound("land", w.wall_middle(start.key()))
		return
	if blueprint and Construction.active != null:
		if not _wall_outside(e, type, true):
			Construction.active.plan_wall(e, type, wall_turned)
		return
	if _wall_outside(e, type, true) or not _pay(item_for("Wall", type), at):
		return
	w.place(e, type, wall_turned)
	_drop_in(w.nodes_of(e))


func _place_prop(cell: Vector2i, sc: float) -> void:
	var at := world.floors.cell_centre(cell)
	if no_build(cell) or why_not(selected, at) != "":
		return
	var slot := int(world.props.types[selected.name].slot)
	if world.props.get_prop(cell, slot) == selected.name:
		return
	if not _pay(selected, at):
		return
	var turns := int(world.props._turns(world.props.types[selected.name]))
	world.props.place(cell, selected.name, sc, _turn_on(selected.name, cell) if turns > 1 else -1)
	_drop_in([world.props.node_at(cell, slot)], 0.0, _prop_sound(selected.name))


func set_demolish_only(kind: String) -> void:
	demolish_only = kind
	changed.emit()


# Whether Demolish (as set) takes a prop called [param prop_name].
func _demolish_prop(prop_name: String) -> bool:
	var farm_plot: bool = prop_name in ["FarmPlot", "WildPotatoes"]
	return demolish_only == "All" or (demolish_only == "Farm" and farm_plot) or (demolish_only == "Decor" and not farm_plot)


# A rabbit pen covers the 3x3 tiles round the one it stands on: on any of them, the tile it stands on (else [param cell]).
func _pen_cell(cell: Vector2i) -> Vector2i:
	if world.props.peek_where(cell, _demolish_prop) != "":
		return cell
	for at in world.props_named("RabbitPen"):
		var c := world.floors.cell_at(at)
		if absi(c.x - cell.x) <= 1 and absi(c.y - cell.y) <= 1 and _demolish_prop("RabbitPen"):
			return c
	return cell


func _clear_one(cell: Vector2i) -> void:
	var f := world.floors
	var at := f.cell_centre(cell)
	var only := demolish_only
	var prop_cell := _pen_cell(cell) if only in ["All", "Decor", "Farm"] else cell
	# A plan there goes first (nothing to refund).
	if only in ["All", "Walls", "Floors"] and Construction.active != null and Construction.active.remove_at(cell, world.walls.edges_in(cell)):
		return
	if only in ["All", "Decor", "Farm"]:
		var top := world.props.peek_where(prop_cell, _demolish_prop)
		if world.props.remove_one_where(prop_cell, _demolish_prop):
			_refund(item_for("Prop", top), at)
			return
	if only == "Decor" or only == "Farm":
		return
	for e in ([] if only == "Floors" else world.walls.edges_in(cell)):
		var before := world.walls.version
		var type := world.walls.get_wall(e)
		world.walls.restore(e)
		if world.walls.version != before:
			if type != "" and world.walls.get_wall(e) != type:
				_refund(item_for("Wall", type), at)
			return
	if only == "Walls":
		return
	var laid := f.get_laid(cell)
	var ground := f.get_floor(cell)
	f.restore(cell)
	var gone := laid if laid != "" and f.get_laid(cell) != laid else (ground if ground != "" and f.get_floor(cell) != ground else "")
	if gone != "":
		_refund(item_for("Floor", gone), at)


# What demolishing here would take, and give back.
func _demolish_hover(cell: Vector2i, shown: bool) -> Dictionary:
	var it := {}
	var nm := ""
	var only := demolish_only
	var top := world.props.peek_where(_pen_cell(cell), _demolish_prop) if only in ["All", "Decor", "Farm"] else ""
	if top != "":
		it = item_for("Prop", top)
		nm = str(world.props.types.get(top, {}).get("display", top))
	if nm == "" and only in ["All", "Walls"]:
		for e in world.walls.edges_in(cell):
			var w := world.walls.get_wall(e)
			if w != "":
				it = item_for("Wall", w)
				nm = str(world.walls.types[w].get("display", w))
				break
	if nm == "" and only in ["All", "Floors"]:
		var laid := world.floors.get_laid(cell)
		if laid != "":
			it = item_for("Floor", laid)
			nm = str(world.floors.types.get(laid, {}).get("display", laid))
	if nm == "":
		return {}
	var refund := []
	if not it.is_empty():
		for c in Village.sum(it.cost):
			if c[1] / 2 > 0:
				refund.append([c[0], c[1] / 2])
	return {"show": shown, "title": "Remove " + nm, "demolish": true, "refund": refund}


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
	_draw_more()
	var f := world.floors
	for c in _cells:
		if _floor_art != "":
			# The floor itself on the cell, see-through (a laid floor's whole tile; ground, its plain tile).
			var ft: Dictionary = f.types[_floor_art]
			var tile: Variant = (ft.whole[0] if not (ft.whole as Array).is_empty() else null) if f.is_whole(_floor_art) else ft.tiles[15]
			var sid := FloorMap._sprite_for(tile, c)
			if sid >= 0:
				var info: Dictionary = world.sprites[sid]
				var tex := world._texture(info.tex)
				var k := world.px / float(info.ppu)
				var region := Rect2(info.rect[0], info.rect[1], info.rect[2], info.rect[3])
				draw_texture_rect_region(tex, Rect2(f.cell_centre(c) - Vector2(float(info.pivot[0]), float(info.pivot[1])) * k, region.size * k), region, _ghost_tint)
		var pts := PackedVector2Array([f.corner(Vector2(c)), f.corner(Vector2(c) + Vector2(1, 0)), f.corner(Vector2(c) + Vector2(1, 1)), f.corner(Vector2(c) + Vector2(0, 1))])
		draw_colored_polygon(pts, Color(_cell_colour, 0.18))
		pts.append(pts[0])
		draw_polyline(pts, _cell_colour, 0.03 * world.px, true)
	if _wall_ghost != null:
		# The line it runs along, faint, and the wall's own art over it (just the line where there's none: demolishing).
		draw_line(_wall_ghost[0], _wall_ghost[1], Color(_cell_colour, 0.2 if not _wall_art.is_empty() else 0.35), 0.16 * world.px, true)
		draw_line(_wall_ghost[0], _wall_ghost[1], Color(_cell_colour, 0.5 if not _wall_art.is_empty() else 1.0), 0.04 * world.px, true)
		for piece in _wall_art:
			var info: Dictionary = world.sprites[int(piece[0])]
			var tex := world._texture(info.tex)
			if tex == null:
				continue
			var k := world.px / float(info.ppu)
			var region := Rect2(info.rect[0], info.rect[1], info.rect[2], info.rect[3])
			draw_set_transform(piece[2], 0.0, Vector2(-1.0 if piece[1] else 1.0, 1.0))
			draw_texture_rect_region(tex, Rect2(-Vector2(float(info.pivot[0]), float(info.pivot[1])) * k, region.size * k), region, _ghost_tint)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for g in _group_ghost:
		if int(g.sprite) < 0:
			continue
		var gi: Dictionary = world.sprites[int(g.sprite)]
		var gk := float(g.scale) * world.px / float(gi.ppu)
		var gr := Rect2(gi.rect[0], gi.rect[1], gi.rect[2], gi.rect[3])
		draw_texture_rect_region(world._texture(gi.tex), Rect2(g.at - Vector2(float(gi.pivot[0]), float(gi.pivot[1])) * gk, gr.size * gk), gr, g.colour)
	if not _prop_ghost.is_empty() and int(_prop_ghost.sprite) >= 0:
		var info: Dictionary = world.sprites[int(_prop_ghost.sprite)]
		var tex := world._texture(info.tex)
		var k := float(_prop_ghost.scale) * world.px / float(info.ppu)
		var region := Rect2(info.rect[0], info.rect[1], info.rect[2], info.rect[3])
		var at: Vector2 = _prop_ghost.at - Vector2(float(info.pivot[0]), float(info.pivot[1])) * k
		if bool(_prop_ghost.get("flip", false)):
			# Mirrored about its pivot.
			draw_set_transform(Vector2(_prop_ghost.at.x * 2.0, 0.0), 0.0, Vector2(-1, 1))
			draw_texture_rect_region(tex, Rect2(at, region.size * k), region, _prop_ghost.colour)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			draw_texture_rect_region(tex, Rect2(at, region.size * k), region, _prop_ghost.colour)
	if _ring > 0.0:
		var c := Color(HudStyle.color("green"), 0.8) if _ring_ok else BLOCKED
		draw_set_transform(_ring_at, 0.0, Vector2(1, 0.5))
		draw_arc(Vector2.ZERO, _ring * world.px, 0.0, TAU, 64, c, 0.04 * world.px, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


# ==== Move, Copy, Inspect, houses, hiding buildings, the drop-in (Unity's BuildCatalog and the rest of BuildMode) ====

const SQUARES := [["Hut", 5], ["House", 6], ["Hall", 8]]
const PRESETS_FILE := "user://house_presets.json"
const CRYSTAL_MIN_GAP := 10.0
const CRYSTAL_MAX_GAP := 26.0

var carried: Dictionary = {}           ## a prop picked up with Move: {prop, turn, scale, free, pos}; a farm field: and
## group: [{off (cells from the one picked up), prop, turn, scale, farm (its crop)}], from (the cell picked up)
var _group_ghost: Array = []           ## a farm field being moved: a ghost for each plot ({sprite, at, scale, colour})
var preset_turn := 0
var picked_room: Variant = null        ## the house picked with Inspect (its cells), or null
var hover_room: Variant = null
var hide_buildings := false
var saved_presets: Array = []
var _move_down := false
var _house_ghost: Dictionary = {}      ## {cells: [Vector2i], walls: [[a, b]], blocked}
var _hidden: Array = []


## A size x size room of [param floor] (laid alternately turned), walled all round, a door in the middle of the front
## right side and windows in the middle of the others (Unity's HousePreset.Square).
static func square(nm: String, size: int, floor_name: String, wall: String, door: String, window: String) -> Dictionary:
	var p := {"name": nm, "width": size, "height": size, "cells": [], "walls": [], "props": [], "free": []}
	for x in size:
		for y in size:
			p.cells.append({"x": x, "y": y, "floor": floor_name, "turned": (x + y) % 2 == 0, "roof": ""})
	@warning_ignore("integer_division")
	var mid := size / 2
	for i in size:
		var middle := i == mid
		p.walls.append({"x": i, "y": 0, "alongY": false, "type": door if middle else wall})
		p.walls.append({"x": 0, "y": i, "alongY": true, "type": window if middle else wall})
		p.walls.append({"x": i, "y": size, "alongY": false, "type": window if middle else wall})
		p.walls.append({"x": size, "y": i, "alongY": true, "type": window if middle else wall})
	return p


## The same house turned a quarter, rebuilt round the other way (grid corners (x, y) go to (y, width - x)).
static func turned(p: Dictionary, quarters := 1) -> Dictionary:
	var q := p
	for n in ((quarters % 4) + 4) % 4:
		var w: int = int(q.width)
		var t := {"name": q.name, "width": q.height, "height": q.width, "cells": [], "walls": [], "props": [], "free": []}
		for c in q.cells:
			t.cells.append({"x": c.y, "y": w - 1 - int(c.x), "floor": c.floor, "turned": not bool(c.turned), "roof": c.get("roof", "")})
		for f in q.get("free", []):
			t.free.append({"x": f.y, "y": w - float(f.x), "type": f.type, "turn": int(f.turn) + 1, "scale": f.scale})
		for r in q.get("props", []):
			t.props.append({"x": r.y, "y": w - 1 - int(r.x), "type": r.type, "turn": int(r.turn) + 1, "scale": r.scale})
		for wl in q.walls:
			if bool(wl.alongY):
				t.walls.append({"x": wl.y, "y": w - int(wl.x), "alongY": false, "type": wl.type})
			else:
				t.walls.append({"x": wl.y, "y": w - int(wl.x) - 1, "alongY": true, "type": wl.type})
		q = t
	return q


func _first_laid_floor() -> String:
	for it in items:
		if it.kind == "Floor" and not _paving(it.name):
			return it.name
	return ""


func _wall_named(n: String, fallback := "BarnWall") -> String:
	return n if world.walls.types.has(n) else fallback


# The houses in the catalogue: the squares, then what's been saved.
func _add_houses() -> void:
	var floor_name := _first_laid_floor()
	var wall := _wall_named("BarnWall", world.walls.types.keys()[0])
	var door := _wall_named("WallDoorClosed", wall)
	var window := _wall_named("WallWindow", wall)
	var houses := []
	for s in SQUARES:
		houses.append(_house_item(square(s[0], s[1], floor_name, wall, door, window), "%s %dx%d" % [s[0], s[1], s[1]]))
	if FileAccess.file_exists(PRESETS_FILE):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(PRESETS_FILE))
		if d is Dictionary:
			saved_presets = d.get("presets", [])
	for p in saved_presets:
		houses.append(_house_item(p, str(p.name)))
	var at := 0
	for i in items.size():
		if CATEGORIES.find(items[i].category) <= CATEGORIES.find("Houses"):
			at = i + 1
	for h in houses:
		items.insert(at, h)
		at += 1


# A house costs its floor, its walls and what's inside.
func _house_item(p: Dictionary, display: String) -> Dictionary:
	var cost := []
	for c in p.cells:
		cost.append_array(item_for("Floor", str(c.floor) if str(c.floor) != "" else _first_laid_floor()).get("cost", []))
	for w in p.walls:
		cost.append_array(item_for("Wall", _wall_named(str(w.type))).get("cost", []))
	var inside := 0
	for r in p.get("props", []) + p.get("free", []):
		var it := item_for("Prop", str(r.type))
		if not it.is_empty():
			inside += 1
			cost.append_array(it.cost)
	var desc := ("A whole %dx%d house as saved: floor, walls and the %d things inside. R turns it. In blueprint mode (N) the villagers build it all." % [p.width, p.height, inside]) if inside > 0 \
		else "A whole %dx%d room: floor, walls, a door and windows. R turns the door." % [p.width, p.height]
	var house_icon := -1
	for it in items:
		if it.name == "BarnWall":
			house_icon = int(it.icon)
	return {"name": str(p.name), "display": display, "kind": "House", "category": "Houses", "tier": 1, "description": desc,
		"cost": Village.sum(cost), "lockedBy": "", "ring": 0.0, "icon": house_icon, "house": p}


## Which house the cursor is over in Inspect, and clicking picks it.
func _inspect(point: Vector2, over_ui: bool) -> void:
	_cells.clear()
	_wall_ghost = null
	_wall_art = []
	_floor_art = ""
	_prop_ghost = {}
	_group_ghost = []
	_ring = 0.0
	hover = {}
	hover_room = null if over_ui or world.roofs == null else world.roofs.room_on(point)
	var down := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var click := down and not _move_down and not over_ui and not _tool_clicked
	_move_down = down
	if not down:
		_tool_clicked = false
	if click:
		picked_room = hover_room
		changed.emit()
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and not over_ui and picked_room != null:
		picked_room = null
		changed.emit()


## What the picked house is: [kind, perk, what's in it].
func picked_info() -> Array:
	if picked_room == null:
		return []
	var cells: Dictionary = picked_room
	var at: Vector2 = world.floors.cell_centre(cells.keys()[0])
	var kind := world.village.room_kind_at(at)
	var names := {"Storage": "Storage house", "Shelter": "Shelter", "House": "House", "": "Empty room"}
	var perks := {"Storage": "Each chest adds 16 item slots to the village store instead of 8", "Shelter": "Sleep restores 25% faster, and beds are 15% comfier",
		"House": "Put only beds in it for a Shelter, or only chests for a Storage house", "": "Put beds in it for a Shelter, or chests for a Storage house"}
	var inside := {}
	for c in cells:
		for e in world.props.at(c):
			inside[e.prop] = int(inside.get(e.prop, 0)) + 1
	for e in world.props.free_props():
		if cells.has(world.floors.cell_at(e.pos)):
			inside[e.prop] = int(inside.get(e.prop, 0)) + 1
	var list := []
	for p in inside:
		list.append("%s%s" % [world.props.types.get(p, {}).get("display", p), " ×%d" % inside[p] if inside[p] > 1 else ""])
	return [names.get(kind, kind), perks.get(kind, ""), ", ".join(list) if not list.is_empty() else "nothing yet", cells.size()]


func set_picked_roof(look: String) -> void:
	if picked_room == null:
		return
	world.roofs.set_roof((picked_room as Dictionary).keys(), look)
	changed.emit()


## Keeps the picked house as a house to build again, here and in later games.
func save_picked_house() -> void:
	if picked_room == null:
		return
	var p := capture_house(picked_room, "My House %d" % (saved_presets.size() + 1))
	saved_presets.append(p)
	var f := FileAccess.open(PRESETS_FILE, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"presets": saved_presets}, "  "))
	var at := 0
	for i in items.size():
		if items[i].kind == "House":
			at = i + 1
	items.insert(at, _house_item(p, str(p.name)))
	_say("Saved as %s" % p.name, miko.position, HudStyle.color("accentLight"), true)
	changed.emit()


## A house as a preset: its cells' floors and roofs, every wall round or through them, and what's inside.
func capture_house(cells: Dictionary, nm: String) -> Dictionary:
	var lo := Vector2i(1 << 30, 1 << 30)
	var hi := -lo
	for c in cells:
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	var p := {"name": nm, "width": hi.x - lo.x + 1, "height": hi.y - lo.y + 1, "cells": [], "walls": [], "props": [], "free": []}
	var seen := {}
	for c in cells:
		p.cells.append({"x": c.x - lo.x, "y": c.y - lo.y, "floor": world.floors.get_laid(c), "turned": world.floors.is_turned(c), "roof": world.roofs.roof_floors.get(c, "")})
		for e in [WallMap.Edge.new(c, true), WallMap.Edge.new(c + Vector2i(1, 0), true), WallMap.Edge.new(c, false), WallMap.Edge.new(c + Vector2i(0, 1), false)]:
			var t := world.walls.get_wall(e)
			if t == "" or seen.has(e.key()):
				continue
			seen[e.key()] = true
			p.walls.append({"x": e.vertex.x - lo.x, "y": e.vertex.y - lo.y, "alongY": e.along_y, "type": t})
		for slot in PropMap.Slot.values():
			var k := Vector3i(c.x, c.y, slot)
			if world.props.cells.has(k):
				var e: Dictionary = world.props.cells[k]
				p.props.append({"x": c.x - lo.x, "y": c.y - lo.y, "type": e.prop, "turn": int(e.get("turn", 0)), "scale": float(e.get("scale", 1.0))})
	for e in world.props.free_props():
		if cells.has(world.floors.cell_at(e.pos)):
			var fc := world.floors.fractional_cell(e.pos) - Vector2(lo)
			p.free.append({"x": fc.x, "y": fc.y, "type": e.prop, "turn": int(e.get("turn", 0)), "scale": float(e.get("scale", 1.0))})
	return p


# ---- Placing a house ----

func _house_low(p: Dictionary, cell: Vector2i) -> Vector2i:
	@warning_ignore("integer_division")
	return cell - Vector2i((int(p.width) - 1) / 2, (int(p.height) - 1) / 2)


func _house_no_build(p: Dictionary, low: Vector2i) -> bool:
	for c in p.cells:
		if no_build(low + Vector2i(int(c.x), int(c.y))):
			return true
	return false


func _house_outside(p: Dictionary, low: Vector2i, say: bool) -> bool:
	for c in p.cells:
		if _outside(world.floors.cell_centre(low + Vector2i(int(c.x), int(c.y))), say):
			return true
	return false


func _place_house(p: Dictionary, low: Vector2i) -> void:
	var f := world.floors
	if blueprint and Construction.active != null:
		for c in p.cells:
			var fl := str(c.floor) if f.types.has(str(c.floor)) else _first_laid_floor()
			Construction.active.plan_floor(low + Vector2i(int(c.x), int(c.y)), fl, bool(c.turned) and f.can_turn(fl))
		for w in p.walls:
			Construction.active.plan_wall(WallMap.Edge.new(low + Vector2i(int(w.x), int(w.y)), bool(w.alongY)), _wall_named(str(w.type)))
		for r in p.get("props", []):
			if world.props.types.has(r.type):
				Construction.active.plan_prop(low + Vector2i(int(r.x), int(r.y)), r.type, int(r.turn), float(r.get("scale", 1.0)))
		for r in p.get("free", []):
			if world.props.types.has(r.type):
				Construction.active.plan_free(Vector2(low) + Vector2(float(r.x), float(r.y)), r.type, int(r.turn), float(r.get("scale", 1.0)))
		return
	var dropped := []
	for c in p.cells:
		var cell := low + Vector2i(int(c.x), int(c.y))
		if not f.in_bounds(cell):
			continue
		world.props.remove_all(cell)
		var fl := str(c.floor) if f.types.has(str(c.floor)) else _first_laid_floor()
		f.paint(cell, fl, bool(c.turned) and f.can_turn(fl))
		if str(c.get("roof", "")) != "":
			world.roofs.roof_floors[cell] = c.roof
	for w in p.walls:
		var e := WallMap.Edge.new(low + Vector2i(int(w.x), int(w.y)), bool(w.alongY))
		world.walls.place(e, _wall_named(str(w.type)))
		dropped.append_array(world.walls.nodes_of(e))
	for r in p.get("free", []):
		if not world.props.types.has(r.type):
			continue
		var turns := maxi(1, world.props._turns(world.props.types[r.type]))
		world.props.place_free(f.corner(Vector2(low) + Vector2(float(r.x), float(r.y))), r.type, float(r.get("scale", 1.0)), ((int(r.turn) % turns) + turns) % turns if turns > 1 else -1)
	for r in p.get("props", []):
		if not world.props.types.has(r.type):
			continue
		var turns := maxi(1, world.props._turns(world.props.types[r.type]))
		world.props.place(low + Vector2i(int(r.x), int(r.y)), r.type, float(r.get("scale", 1.0)), ((int(r.turn) % turns) + turns) % turns if turns > 1 else -1)
	_drop_in(dropped, 0.1)


func _house_cursor(cell: Vector2i, over_ui: bool, shown: bool) -> void:
	var p := turned(selected.house, preset_turn)
	var low := _house_low(p, cell)
	var status := status_of(selected)
	var outside := _house_outside(p, low, false)
	var blocked := _house_no_build(p, low)
	var ok := status == "Ready" or blueprint
	_house_ghost = {}
	if shown:
		var cells := []
		for c in p.cells:
			cells.append(low + Vector2i(int(c.x), int(c.y)))
		var walls := []
		for w in p.walls:
			var e := WallMap.Edge.new(low + Vector2i(int(w.x), int(w.y)), bool(w.alongY))
			walls.append([world.walls.vertex_position(e.vertex), world.walls.vertex_position(e.end())])
		_house_ghost = {"cells": cells, "walls": walls, "blocked": blocked or outside or not ok}
	var note := ""
	if outside: note = _village_note()
	elif blocked: note = "Can't build on the road"
	elif status == "Short" and not blueprint: note = missing(selected.cost)
	hover = {"show": shown, "title": selected.display, "tier": 1, "status": "Ready" if blueprint else status, "costs": selected.cost, "note": note, "plan": blueprint}
	var down := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var click := down and not _move_down and not over_ui and not _tool_clicked
	_move_down = down
	if not down:
		_tool_clicked = false
	if not click or not shown:
		return
	if blocked:
		_say("Can't build on the road", world.floors.cell_centre(cell))
		return
	if _house_outside(p, low, true):
		return
	var before := _capture()
	if not blueprint and not _pay(selected, world.floors.cell_centre(cell)):
		return
	_stroke_start = before
	_place_house(p, low)
	_end_stroke()


# ---- Move and Copy ----

func _move_or_copy(point: Vector2, cell: Vector2i, over_ui: bool) -> void:
	_cells.clear()
	_wall_ghost = null
	_wall_art = []
	_floor_art = ""
	_prop_ghost = {}
	_group_ghost = []
	_ring = 0.0
	var shown := not over_ui and world.floors.in_bounds(cell)
	var top := world.props.peek_top(cell)
	var down := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var click := down and not _move_down and not over_ui and not _tool_clicked
	_move_down = down
	if not down:
		_tool_clicked = false
	if shown:
		_cells.append(cell)
	if tool == "Move":
		if carried.has("group"):
			_carry_field(cell, shown, click)
			return
		if not carried.is_empty():
			var free := Input.is_key_pressed(KEY_ALT)
			var at := point if free else world.floors.cell_centre(cell)
			var it := item_for("Prop", carried.prop)
			var why := "Can't build on the road" if no_build(cell) else why_not(it, at, carried)
			var blocked := why != ""
			_cell_colour = BLOCKED if blocked else Color(HudStyle.color("green"), 0.9)
			if free:
				_cells.clear()
			_prop_ghost = {"sprite": world.props.sprite_for(carried.prop, int(carried.turn)), "at": at, "scale": float(carried.scale), "colour": BLOCKED if blocked else Color(1, 1, 1, 0.6)}
			hover = {"show": shown, "title": "Move " + str(world.props.types.get(carried.prop, {}).get("display", carried.prop)), "move": true, "note": why}
			if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
				put_back_carried()
				return
			if click and not blocked and shown:
				var turns := world.props._turns(world.props.types[carried.prop])
				var t := int(carried.turn) if turns > 1 else -1
				if free:
					world.props.place_free(point, carried.prop, float(carried.scale), t)
					_drop_in([world.props.last_free_node()])
				else:
					world.props.place(cell, carried.prop, float(carried.scale), t)
					_drop_in([world.props.node_at(cell, int(world.props.types[carried.prop].slot))])
				_set_plot(point if free else world.floors.cell_centre(cell))
				carried = {}
				_end_stroke()
				changed.emit()
			return
		_cell_colour = HudStyle.color("accent") if top != "" else Color(1, 1, 1, 0.35)
		hover = {"show": shown and top != "", "title": "Move " + str(world.props.types.get(top, {}).get("display", top)), "move": true, "note": ""}
		var fm0 := _farming()
		if click and top != "" and fm0 != null and fm0.d.get("plots", {}).has(top) and world.props.peek_top(cell) == top:
			# A farm plot: its whole field comes up together.
			_stroke_start = _capture()
			_lift_field(cell)
			changed.emit()
			return
		if click and top != "":
			_stroke_start = _capture()
			carried = world.props.take_top(cell)
			# A farm plot: its crop comes along.
			var fm := _farming()
			if fm != null and not carried.is_empty() and fm.d.get("plots", {}).has(carried.prop):
				carried.farm = fm.lift_plot(carried.pos)
			changed.emit()
		return
	# Copy: what's here, top first.
	var found := item_for("Prop", top) if top != "" else {}
	if found.is_empty():
		for e in world.walls.edges_in(cell):
			var w := world.walls.get_wall(e)
			if w != "":
				found = item_for("Wall", w)
				if found.is_empty() and str(world.walls.types[w].get("toggle", "")) != "":
					found = item_for("Wall", world.walls.types[w].toggle)
				if not found.is_empty():
					break
	if found.is_empty():
		var laid := world.floors.get_laid(cell)
		found = item_for("Floor", laid) if laid != "" else item_for("Ground", world.floors.get_floor(cell))
	_cell_colour = HudStyle.color("accent") if not found.is_empty() else Color(1, 1, 1, 0.35)
	hover = {"show": shown and not found.is_empty(), "title": "Copy " + str(found.get("display", "")), "move": true, "note": ""}
	if click and not found.is_empty():
		select(found)


func _farming() -> Farming:
	return miko.get_node_or_null("Farming") as Farming if miko != null else null


# Picks up the farm field the plot on [param cell] belongs to: every plot, with its crop.
func _lift_field(cell: Vector2i) -> void:
	var fm := _farming()
	fm._look()
	var p := fm.nearest(world.floors.cell_centre(cell), 0.4 * world.px)
	if p.is_empty():
		return
	var group := []
	for q in fm.field_of(p):
		var qc := world.floors.cell_at(q.pos)
		var slot := int(world.props.types[q.type].slot)
		var e: Dictionary = world.props.cells.get(Vector3i(qc.x, qc.y, slot), {})
		if e.is_empty():
			continue
		group.append({"off": qc - cell, "prop": e.prop, "turn": int(e.get("turn", 0)), "scale": PropMap._scale(float(e.get("scale", 1.0))),
			"farm": fm.lift_plot(q.pos)})
		world.props.remove(qc, slot)
	carried = {"prop": p.type, "turn": 0, "scale": 1.0, "free": false, "pos": world.floors.cell_centre(cell), "group": group, "from": cell}


# A farm field carried by Move: its ghost under the cursor (red where a plot can't go), set down on a click if every
# plot can be.
func _carry_field(cell: Vector2i, shown: bool, click: bool) -> void:
	var blocked := ""
	for g in carried.group:
		var c: Vector2i = cell + g.off
		var at := world.floors.cell_centre(c)
		var why := "Can't build on the road" if no_build(c) else ("Something's in the way" if world.props.get_prop(c, int(world.props.types[g.prop].slot)) != "" else why_not(item_for("Prop", g.prop), at, carried))
		if not world.floors.in_bounds(c):
			why = "Off the map"
		if why != "" and blocked == "":
			blocked = why
		if shown:
			_cells.append(c)
		_group_ghost.append({"sprite": world.props.sprite_for(g.prop, int(g.turn)), "at": at, "scale": float(g.scale), "colour": BLOCKED if why != "" else Color(1, 1, 1, 0.6)})
	_cell_colour = BLOCKED if blocked != "" else Color(HudStyle.color("green"), 0.9)
	hover = {"show": shown, "title": "Move field (%d plot%s)" % [carried.group.size(), "" if carried.group.size() == 1 else "s"], "move": true, "note": blocked}
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		put_back_carried()
		return
	if click and shown and blocked == "":
		_set_field_down(cell)
		carried = {}
		_end_stroke()
		changed.emit()


# Sets the carried field down with the plot picked up on [param cell], each plot's crop with it.
func _set_field_down(cell: Vector2i) -> void:
	var fm := _farming()
	var nodes := []
	for g in carried.group:
		var c: Vector2i = cell + g.off
		var turns := world.props._turns(world.props.types[g.prop])
		world.props.place(c, g.prop, float(g.scale), int(g.turn) if turns > 1 else -1)
		nodes.append(world.props.node_at(c, int(world.props.types[g.prop].slot)))
		if fm != null:
			fm.set_plot(world.floors.cell_centre(c), g.farm)
	_drop_in(nodes.filter(func(n): return n != null))


# A farm plot carried by Move set down at [param at]: its crop with it.
func _set_plot(at: Vector2) -> void:
	var fm := _farming()
	if fm != null and carried.has("farm"):
		fm.set_plot(at, carried.farm)


## Puts what Move is carrying back where it came from.
func put_back_carried() -> void:
	if carried.is_empty():
		return
	if carried.has("group"):
		_set_field_down(carried.from)
		carried = {}
		_stroke_start = null
		changed.emit()
		return
	var turns := world.props._turns(world.props.types[carried.prop])
	var t := int(carried.turn) if turns > 1 else -1
	if bool(carried.free):
		world.props.place_free(carried.pos, carried.prop, float(carried.scale), t)
	else:
		world.props.place(world.floors.cell_at(carried.pos), carried.prop, float(carried.scale), t)
	_set_plot(carried.pos)
	carried = {}
	_stroke_start = null
	changed.emit()


# ---- Where props may stand (the rest of Unity's WhyNot) ----

# The tiles beds and chests are used from.
func _use_cells() -> Dictionary:
	var out := {}
	var people: Villagers = get_tree().current_scene.get_node_or_null("Villagers")
	for bed in (Needs.all_beds(world, people.d.get("beds", {})) if people != null else []):
		out[UseSpots.bed_cell(world, bed)] = world.floors.cell_at(bed.pos)
	for c in world.props.entries_named("Chest"):
		out[UseSpots.chest_cell(world, c.pos, int(c.e.get("turn", 0)))] = world.floors.cell_at(c.pos)
	return out


## Whether [param e] would run between a bed or chest and its way in.
func blocks_way_in(e: WallMap.Edge) -> bool:
	var uses := _use_cells()
	for use in uses:
		var on: Vector2i = uses[use]
		var d: Vector2i = use - on
		var between: WallMap.Edge = null
		if d == Vector2i(1, 0): between = WallMap.Edge.new(use, true)
		elif d == Vector2i(-1, 0): between = WallMap.Edge.new(on, true)
		elif d == Vector2i(0, 1): between = WallMap.Edge.new(use, false)
		elif d == Vector2i(0, -1): between = WallMap.Edge.new(on, false)
		if between != null and between.key() == e.key():
			return true
	return false


# Whether a prop's footing at [param at] has a solid wall running through it.
func _across_wall(prop: String, at: Vector2, t: int, sc: float) -> bool:
	var id := world.props.sprite_for(prop, t)
	if id < 0:
		return false
	var info: Dictionary = world.sprites[id]
	var k := sc * world.px / float(info.ppu)
	var w: float = float(info.rect[2]) * k * 0.8
	var h: float = float(info.rect[3]) * k
	var below: float = (float(info.rect[3]) - float(info.pivot[1])) * k   # how far its picture reaches below its spot
	var foot := at.y + below
	var depth := h * 0.3
	var seen := {}
	for i in 7:
		for j in 3:
			seen[world.floors.cell_at(Vector2(at.x - w / 2.0 + w * i / 6.0, foot - depth * (j + 0.5) / 3.0))] = true
	for c in seen:
		for pair in [[Vector2i(1, 0), WallMap.Edge.new(c + Vector2i(1, 0), true)], [Vector2i(0, 1), WallMap.Edge.new(c + Vector2i(0, 1), false)]]:
			if not seen.has(c + pair[0]):
				continue
			var type := world.walls.get_wall(pair[1])
			if type != "" and float(world.walls.types[type].get("opening", 0.0)) < 1.0 and not bool(world.walls.types[type].get("fence", false)):
				return true
	return false


func _crystal_gap(at: Vector2, skip: Variant = null) -> float:
	var best := INF
	var crystals: Crystals = get_tree().current_scene.get_node_or_null("Crystals")
	if crystals == null:
		return best
	for c in crystals.teleports:
		if skip != null and (c.pos as Vector2).distance_to(skip) < 1.0:
			continue
		best = minf(best, c.pos.distance_to(at) / world.px)
	return best


func _crystal_why(at: Vector2, moved_from: Variant) -> String:
	var gap := _crystal_gap(at, moved_from)
	if is_inf(gap):
		return ""
	if gap < CRYSTAL_MIN_GAP:
		return "Too close to another crystal (%.1f of %d needed)" % [gap, CRYSTAL_MIN_GAP]
	var alone: bool = moved_from != null and _crystal_gap(moved_from, moved_from) > CRYSTAL_MAX_GAP
	if gap > CRYSTAL_MAX_GAP and not alone:
		return "Too far from the nearest crystal (%.1f, at most %d)" % [gap, CRYSTAL_MAX_GAP]
	return ""


# ---- Hiding walls and roofs, and the drop-in ----

func toggle_hide_buildings() -> void:
	hide_buildings = not hide_buildings
	if not hide_buildings:
		_show_buildings()
	changed.emit()


func _show_buildings() -> void:
	for n in _hidden:
		if is_instance_valid(n):
			n.visible = true
	_hidden.clear()


func _hide_buildings() -> void:
	var nodes: Array = world.walls.all_nodes() + (world.roofs.all_nodes() if world.roofs != null else [])
	if Construction.active != null:
		nodes += Construction.active.ghost_nodes()
	for n in nodes:
		if is_instance_valid(n) and n.visible:
			n.visible = false
			_hidden.append(n)


## Drops freshly built pieces into place: from a little above, fading in, with a small squash as they land.
## Build mode's drop-in sounds (sounds.json's drop: a thud, grass rustling, leaves for plants).
var drop_sounds: Dictionary = {}
var _last_thud := -1.0
var _last_rustle := -1.0


## A thud as something lands ([param kind] "land"), or grass ("grass") or leaves ("leaf") rustling; a burst shares a few.
func drop_sound(kind: String, at: Vector2) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var key: String = {"land": "landSound", "grass": "grassSound", "leaf": "leafSound"}[kind]
	var vol := float(drop_sounds.get({"land": "volume", "grass": "grassVolume", "leaf": "leafVolume"}[kind], 0.7))
	if kind == "land":
		if t - _last_thud < float(drop_sounds.get("soundGap", 0.06)):
			return
		_last_thud = t
	else:
		if t - _last_rustle < float(drop_sounds.get("grassGap", 0.09)):
			return
		_last_rustle = t
	var path: Variant = drop_sounds.get(key)
	if path is String and ResourceLoader.exists(path):
		Sfx.play(world, Sfx.stream(path), at, vol, 0.06)


# Which sound a prop makes landing: grass rustles, plants rustle their leaves, the rest thud.
func _prop_sound(prop: String) -> String:
	var cat := str(world.props.types.get(prop, {}).get("category", ""))
	if prop.contains("Grass"):
		return "grass"
	if cat == "Decorations" or cat == "Trees" or prop.contains("Leaf"):
		return "leaf"
	return "land"


func _drop_in(nodes: Array, spread := 0.0, sound := "land") -> void:
	var sounded := false
	for n in nodes:
		if not sounded and n != null and is_instance_valid(n):
			sounded = true
			var where: Vector2 = (n as Node2D).global_position
			get_tree().create_timer(0.2 + spread * 0.5).timeout.connect(func(): drop_sound(sound, where))
		if n == null or not is_instance_valid(n):
			continue
		var node: Node2D = n
		var rest := node.position
		var delay := randf_range(0.0, spread)
		node.position = rest + Vector2(0, -0.6 * world.px)
		node.modulate.a = 0.0
		var tw := node.create_tween()
		tw.tween_interval(delay)
		tw.tween_property(node, "modulate:a", 1.0, 0.12)
		tw.parallel().tween_property(node, "position", rest, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(node, "scale", Vector2(1.06, 0.92), 0.06)
		tw.tween_property(node, "scale", Vector2.ONE, 0.1)


# ---- More to draw while building: the village's edge, crystals' rings, the missing floors, the picked house, a house's ghost ----

func _draw_more() -> void:
	var f := world.floors
	var green := HudStyle.color("green")
	var t := Time.get_ticks_msec() / 1000.0
	# The village's edge, breathing gently (where the banner being placed would put it).
	var edge := Color(green, 0.55 + 0.2 * sin(t * 2.0))
	if kind_of(selected) == "Prop" and bool(selected.get("banner", false)) and tool == "Place" and not _prop_ghost.is_empty():
		var c := f.cell_at(_prop_ghost.at)
		var r := int(world.village.radii[0])
		var pts := PackedVector2Array()
		for k in [Vector2(-r, -r), Vector2(r + 1, -r), Vector2(r + 1, r + 1), Vector2(-r, r + 1), Vector2(-r, -r)]:
			pts.append(f.corner(Vector2(c) + k))
		draw_polyline(pts, edge, 0.04 * world.px, true)
	else:
		for loop in MapMarks.village_loops(world):
			var pts := PackedVector2Array(loop)
			pts.append(loop[0])
			draw_polyline(pts, edge, 0.04 * world.px, true)
	# Placing a crystal: round each one, the nearest a new one may stand (coral) and the farthest (blue).
	if kind_of(selected) == "Prop" and bool(selected.get("crystal", false)) and tool == "Place":
		var crystals: Crystals = get_tree().current_scene.get_node_or_null("Crystals")
		if crystals != null:
			for c in crystals.teleports:
				draw_set_transform(c.pos, 0.0, Vector2(1, 0.5))
				draw_arc(Vector2.ZERO, CRYSTAL_MIN_GAP * world.px, 0, TAU, 96, Color(HudStyle.color("coral"), 0.75), 0.04 * world.px * 2.0, true)
				draw_arc(Vector2.ZERO, CRYSTAL_MAX_GAP * world.px, 0, TAU, 128, Color(HudStyle.color("mana"), 0.75), 0.04 * world.px * 2.0, true)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Bare tiles in walled-in rooms, pulsing.
	if world.roofs != null:
		var pulse := 0.45 + 0.35 * sin(t * 5.0)
		for c in world.roofs.missing_floor():
			draw_colored_polygon(_diamond(c), Color(1, 0.3, 0.25, pulse * 0.6))
	# Inspect: the house under the cursor, and the one picked.
	for pair in [[hover_room, Color(1, 1, 1, 0.18)], [picked_room, Color(HudStyle.color("accent"), 0.35)]]:
		if pair[0] != null and tool == "Inspect":
			for c in pair[0]:
				draw_colored_polygon(_diamond(c), pair[1])
	# A house's ghost: its floor and its walls.
	if not _house_ghost.is_empty():
		var col := BLOCKED if _house_ghost.blocked else (Color(0.55, 0.78, 1.0, 0.8) if blueprint else Color(green, 0.85))
		for c in _house_ghost.cells:
			draw_colored_polygon(_diamond(c), Color(col, 0.22))
		for w in _house_ghost.walls:
			draw_line(w[0], w[1], col, 0.06 * world.px, true)


func _diamond(c: Vector2i) -> PackedVector2Array:
	var f := world.floors
	return PackedVector2Array([f.corner(Vector2(c)), f.corner(Vector2(c) + Vector2(1, 0)), f.corner(Vector2(c) + Vector2(1, 1)), f.corner(Vector2(c) + Vector2(0, 1))])



## The tile grid drawn over the ground while building: a faint line round every cell in view (the corner lines of the
## floor grid), on the ground, under the walls and props.
class GridLines extends Node2D:
	var build: BuildMode
	var _seen := Rect2()

	func _process(_delta: float) -> void:
		var cam := get_viewport().get_camera_2d()
		if cam == null:
			return
		var half := get_viewport_rect().size / cam.zoom / 2.0
		var view := Rect2(cam.get_screen_center_position() - half, half * 2.0)
		if not view.is_equal_approx(_seen):
			_seen = view
			queue_redraw()

	func _draw() -> void:
		var f := build.world.floors
		# The cells the view's corners fall in: the range of corner lines to draw.
		var lo := Vector2(INF, INF)
		var hi := -lo
		for p in [_seen.position, _seen.end, Vector2(_seen.position.x, _seen.end.y), Vector2(_seen.end.x, _seen.position.y)]:
			var cell_at := f.fractional_cell(p)
			lo = lo.min(cell_at)
			hi = hi.max(cell_at)
		var x0 := maxi(floori(lo.x) - 1, f.bounds.position.x)
		var x1 := mini(ceili(hi.x) + 1, f.bounds.end.x)
		var y0 := maxi(floori(lo.y) - 1, f.bounds.position.y)
		var y1 := mini(ceili(hi.y) + 1, f.bounds.end.y)
		var c := Color(1, 1, 1, 0.3)
		var w := maxf(1.5, 0.02 * build.world.px)
		for x in range(x0, x1 + 1):
			draw_line(f.corner(Vector2(x, y0)), f.corner(Vector2(x, y1)), c, w)
		for y in range(y0, y1 + 1):
			draw_line(f.corner(Vector2(x0, y)), f.corner(Vector2(x1, y)), c, w)
