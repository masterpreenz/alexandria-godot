class_name MapMarks
## What the maps share (from Unity's MapMarker and MapSections): characters and creatures are kept off the maps' pictures
## (their canvas items on a visibility layer the map viewports leave out) and marked as squares instead, red for monsters
## out for blood (dark grey while minding their own business), blue for villagers, and the world's 8 x 8 sections (A1 to
## H8) for the world map's grid.

const HIDDEN_LAYER := 2              ## the visibility layer bit the maps don't draw
const HOSTILE := Color(1, 0.3, 0.25)
const CALM := Color(0.24, 0.24, 0.26)
const ALLY := Color(0.36, 0.6, 0.96)
const OUTSIDER := Color(0.55, 0.88, 0.42)
const CRYSTAL := Color(0.45, 0.88, 1.0)
const BANNER := Color(0.86, 0.22, 0.24)
const BAG := Color(1, 0.85, 0.45)
const SECTION_SIZE := 36
const SECTIONS := 8
const MIN_CELL := -142
const MAX_CELL := 141

static var _next_hide := 0.0


## Puts everything [param root] draws onto the hidden layer (bits added later too, when asked again).
static func hide(root: Node) -> void:
	if root is CanvasItem:
		(root as CanvasItem).visibility_layer = HIDDEN_LAYER
	for ch in root.get_children():
		hide(ch)


## Keeps Miko, the villagers, the creatures and the rabbits off the maps (checked every second).
static func hide_characters(w: World) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	if t < _next_hide:
		return
	_next_hide = t + 1.0
	if w.player != null:
		hide(w.player)
	for v in Villager.all:
		hide(v)
	for c in Creature.all:
		if is_instance_valid(c):
			hide(c)
	for r in Rabbit.rabbits:
		if is_instance_valid(r):
			hide(r)


## What to mark: [[where (px), colour, size (HUD px)]], creatures only while she's near them (awake), villagers always.
static func marks(w: World) -> Array:
	var out := []
	var ex := Exploration.active
	for c in Creature.all:
		if not is_instance_valid(c) or not c.visible or c.asleep:
			continue
		if ex != null and not ex.is_seen(c.position):
			continue
		out.append([c.position, HOSTILE if _hostile(c) else CALM, 5.0])
	for v in Villager.all:
		if v.visible:
			out.append([v.position, ALLY, 5.0])
	return out


static func _hostile(c: Node) -> bool:
	if c.get("chasing") == true:
		return true
	var st: Variant = c.get("state")
	return c is Boar and st is int and st in [Boar.State.WIND_UP, Boar.State.CHARGE, Boar.State.RECOVER]


## Where the section grid's lines fall (tile corners), edge to edge.
static func section_lines() -> Array:
	var out := [MIN_CELL]
	for i in range(1, SECTIONS):
		out.append((i - SECTIONS / 2) * SECTION_SIZE)
	out.append(MAX_CELL + 1)
	return out


static func section_name(column: int, row: int) -> String:
	return String.chr(65 + column) + str(row + 1)


## The tiles of section [param column], [param row] (from 0).
static func section_bounds(column: int, row: int) -> Rect2i:
	var x0 := MIN_CELL if column == 0 else (column - SECTIONS / 2) * SECTION_SIZE
	var x1 := MAX_CELL + 1 if column == SECTIONS - 1 else (column + 1 - SECTIONS / 2) * SECTION_SIZE
	var y0 := MIN_CELL if row == 0 else (row - SECTIONS / 2) * SECTION_SIZE
	var y1 := MAX_CELL + 1 if row == SECTIONS - 1 else (row + 1 - SECTIONS / 2) * SECTION_SIZE
	return Rect2i(x0, y0, x1 - x0, y1 - y0)


## The village's edge as loops of world points (px).
static func village_loops(w: World) -> Array:
	var v := w.village
	if not v.founded():
		return []
	var cells := {}
	for r in v.rects():
		for x in range(r.position.x, r.end.x):
			for y in range(r.position.y, r.end.y):
				cells[Vector2i(x, y)] = true
	var banner := Vector2(w.floors.cell_at(v.centre()))
	var out := []
	for loop in VillageBorder.loops(cells):
		var pts := []
		for p in loop:
			pts.append(w.floors.corner(banner + Vector2(p)))
		out.append(pts)
	return out
