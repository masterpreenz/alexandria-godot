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
const SECTIONS := 8                  ## rows (1..8), and the columns A..H
const WEST := 8                      ## more columns west of A (Z, Y, X ... S): the wilds
const MIN_CELL := -142               ## the old edges (y both ways; x on the east)
const MAX_CELL := 141
const MIN_X := -430                  ## the west edge now


## The columns, west to east: -8 (S) ... -1 (Z), 0 (A) ... 7 (H).
static func columns() -> Array:
	return range(-WEST, SECTIONS)

static var _next_hide := 0.0


## Puts everything [param root] draws onto the hidden layer (bits added later too, when asked again).
static func hide(root: Node) -> void:
	if root is CanvasItem:
		(root as CanvasItem).visibility_layer = HIDDEN_LAYER
	for ch in root.get_children():
		hide(ch)


## What the maps' pictures show of the land, as one number that changes whenever it does: floors laid, walls and
## fences built, props placed, trees felled or regrown. A map redraws its picture when this changes.
static func land_stamp(w: World) -> int:
	return hash([w.floors.version, w.walls.rooms_version, w.props.version, Gatherable.version])   # (rooms: a door swinging is left out)


## Keeps every particle effect (smoke, sparks, sparkles, splashes) off the maps: they're drawn now and then, not every
## frame, so moving things would jump about there.
static func hide_particles(tree: SceneTree) -> void:
	if not tree.node_added.is_connected(_on_node_added):
		tree.node_added.connect(_on_node_added)


static func _on_node_added(n: Node) -> void:
	if n is CPUParticles2D or n is GPUParticles2D:
		(n as CanvasItem).visibility_layer = HIDDEN_LAYER


## Keeps Miko, the villagers, the creatures and the rabbits off the maps (checked every second).
static func hide_characters(w: World) -> void:
	var t0 := Time.get_ticks_usec()
	_hide_characters(w)
	Perf.add(&"maps: hiding characters", t0)


static func _hide_characters(w: World) -> void:
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
static func marks(_w: World) -> Array:
	var out := []
	var ex := Exploration.active
	for c in Creature.all:
		if not is_instance_valid(c) or not c.visible or c.asleep:
			continue
		if ex != null and not ex.is_seen(c.position):
			continue
		out.append([c.position, HOSTILE if _hostile(c) else CALM, 5.0])
	for v in Villager.all:
		if v.visible and not playable(v):
			out.append([v.position, ALLY, 5.0])
	return out


## Whether [param v] is someone who can be played (Miyu, Sera while someone else is): shown by their face on the maps,
## not a dot.
static func playable(v: Villager) -> bool:
	return is_instance_valid(v) and not Playable.entry(str(v.person.get("unique", ""))).is_empty()


static func _hostile(c: Node) -> bool:
	if c.get("chasing") == true:
		return true
	var st: Variant = c.get("state")
	return c is Boar and st is int and st in [Boar.State.WIND_UP, Boar.State.CHARGE, Boar.State.RECOVER]


## Where the section grid's lines fall (tile corners), edge to edge: across x ([param along_x]) or y.
static func section_lines(along_x := false) -> Array:
	var out := [MIN_X if along_x else MIN_CELL]
	for i in range(-WEST + 1 if along_x else 1, SECTIONS):
		@warning_ignore("integer_division")
		out.append((i - SECTIONS / 2) * SECTION_SIZE)
	out.append(MAX_CELL + 1)
	return out


## A section's name: its column's letter (A..H; west of A, Z, Y, X ... S), its row's number.
static func section_name(column: int, row: int) -> String:
	return String.chr((65 if column >= 0 else 91) + column) + str(row + 1)


## The column and row of a section named [param nm] (as "X8"), or [] if there's none.
static func section_of(nm: String) -> Array:
	for col in columns():
		for row in SECTIONS:
			if section_name(col, row) == nm.to_upper():
				return [col, row]
	return []


## The tiles of section [param column], [param row] (from 0).
static func section_bounds(column: int, row: int) -> Rect2i:
	@warning_ignore("integer_division")
	var x0 := MIN_X if column == -WEST else (column - SECTIONS / 2) * SECTION_SIZE
	@warning_ignore("integer_division")
	var x1 := MAX_CELL + 1 if column == SECTIONS - 1 else (column + 1 - SECTIONS / 2) * SECTION_SIZE
	@warning_ignore("integer_division")
	var y0 := MIN_CELL if row == 0 else (row - SECTIONS / 2) * SECTION_SIZE
	@warning_ignore("integer_division")
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
