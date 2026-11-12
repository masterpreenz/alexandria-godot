class_name Cellars
extends Node
## Cellars: cold storage underground. The village's Cellar (its doors set in the ground outdoors; one only) keeps so
## much of the village's food cold by its level ([constant LEVELS]: expanded with U at its doors, for wood and stone,
## which makes its room bigger and has it keep more), where it spoils a quarter as fast (Spoilage asks [method cold_share]). E at one takes Miko down into the
## cellar itself, fading to black and out again: one underground room for all of them, cobbled, stone walls round
## it, earth beyond, lit by a lamp, free of mist. Walking out through the doorway in its front wall brings her back
## up at the trapdoor she went down. The villagers bring the food they carry to a cellar rather than a chest.

## The cellar's levels: how many cells a side its room is, how much food it keeps cold, and what expanding to it
## costs.
const LEVELS := [
	{"side": 5, "holds": 100, "cost": []},
	{"side": 7, "holds": 220, "cost": [["Wood", 20], ["Stone", 40]]},
	{"side": 9, "holds": 360, "cost": [["Wood", 40], ["Stone", 80]]},
	{"side": 11, "holds": 520, "cost": [["Wood", 70], ["Stone", 140]]},
]
const COLD_RATE := 0.25           ## how fast cold food spoils, of the usual
const RANGE := 1.7                ## units from the cellar's doors to use them (they're two tiles across)
## The room: its first cell (well off the map, past the outskirts) and how many cells a side (by its level; it grows
## away from that first cell, so what stands in it stays where it is). A doorway in its front wall, [constant DOOR]
## cells along, is the way out.
const AT := Vector2i(300, -300)
const DOOR := 2
const MOST_SIDE := 11
static var side := 5
const FLOOR := "PathCobble"
const WALL := "FieldstoneWall"
const FRONT_ALPHA := 0.3          ## how solid the two near walls are drawn (seen through, as a house's)

const STAYS_OPEN := 6.0           ## seconds the doors stay open after someone's used them
const OPEN_SOUND := "res://assets/Sounds/cellar_door_open.mp3"
const CLOSE_SOUND := "res://assets/Sounds/cellar_door_close.mp3"

static var active: Cellars

var world: World
var miko: Miko
var prompt: Label
var _fade: ColorRect
var _busy := false
var _pressed := false
var _came_from := Vector2.INF     ## the trapdoor she went down (px)
var _art := {}                    ## the doors' sprites by name
var _open_until := {}             ## cellar doors standing open (where, px) -> when they close (seconds)
var level := 1                    ## the cellar's level (saved): 1 to LEVELS.size()
var _built: Array = []            ## the room's nodes (taken down and put up again when it's expanded)
var _expand := false              ## U pressed at the doors


func setup(w: World, who: Miko, hud: Node) -> void:
	world = w
	miko = who
	active = self
	prompt = HudStyle.label("", 14, "bold")
	prompt.visible = false
	hud.add_child(prompt)
	WorldPrompts.register(prompt)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.visible = false
	_fade.z_index = 100
	hud.add_child(_fade)
	_room()
	# No snow down there, on the floor or on what stands on it.
	world.set_snow_param("floor_origin", Vector2(world.floors.origin.x, -world.floors.origin.y) / world.px)
	world.set_snow_param("underground", Vector4(AT.x - 6, AT.y - 6, MOST_SIDE + 12, MOST_SIDE + 12))


## The cellars in the village: where each trapdoor is (px).
func all() -> Array:
	return world.props_named("Cellar").filter(func(at): return world.village.contains(at))


## How much food the cellar keeps cold (none without one).
func holds() -> int:
	return 0 if all().is_empty() else int(LEVELS[level - 1].holds)


## What expanding it once more costs ([resource, amount] pairs), or [] at its greatest.
func expand_cost() -> Array:
	return [] if level >= LEVELS.size() else LEVELS[level].cost


## Expands the cellar a level, paid for from Miko's bag and storage: a bigger room, more kept cold. False when it's
## at its greatest or she can't pay.
func expand() -> bool:
	if level >= LEVELS.size() or not world.village.pay(miko.bag, miko, expand_cost()):
		return false
	_set_level(level + 1)
	return true


func _set_level(l: int) -> void:
	l = clampi(l, 1, LEVELS.size())
	if l == level and side == int(LEVELS[l - 1].side):
		return
	level = l
	side = int(LEVELS[l - 1].side)
	if world != null:
		_room()


var cold := 0                     ## how much of the village's food has been carried down (saved; never more than
                                  ## the cellars hold, or than there is)
static var movers := {}           ## Villager -> true: carrying food to a cellar from a chest now


## All the food in storage, of every kind.
func food_stored() -> int:
	var food := 0
	for r in Spoilage.PER_DAY:
		food += world.village.stored(r)
	return food


## Food carried down: that much more is in the cold (as far as there's room).
func put(amount: int) -> void:
	cold = clampi(cold + amount, 0, mini(holds(), food_stored()))


## How much food still up in the chests there's room for down here.
func to_move() -> int:
	cold = clampi(cold, 0, mini(holds(), food_stored()))
	return mini(holds(), food_stored()) - cold


## The share of the village's food that's in the cold (0 to 1): what's been carried down, over all the food stored.
func cold_share() -> float:
	var food := food_stored()
	if food <= 0 or holds() <= 0:
		return 0.0
	cold = clampi(cold, 0, mini(holds(), food))
	return float(cold) / float(food)


func to_json() -> String:
	return JSON.stringify({"cold": cold, "level": level})


func from_json(json: String) -> void:
	var d: Variant = JSON.parse_string(json)
	if d is Dictionary:
		cold = int(d.get("cold", 0))
		_set_level(int(d.get("level", 1)))


## Whether [param at] (px) is down in the cellar (underground: out of the mist and the cold).
static func inside(at: Vector2) -> bool:
	if active == null:
		return false
	var c := active.world.floors.fractional_cell(at) - Vector2(AT)
	return c.x > -3.0 and c.y > -3.0 and c.x < side + 3.0 and c.y < side + 3.0


## Whether [param cell] is one of the cellar room's floor cells: things can be built there (it counts as in the
## village and indoors), though the villagers don't go down.
static func room_has(cell: Vector2i) -> bool:
	return cell.x >= AT.x and cell.y >= AT.y and cell.x < AT.x + side and cell.y < AT.y + side


# The doorway's cell (in the front wall along y = AT.y), and where she arrives: a step inside it.
func _door_cell() -> Vector2i:
	return AT + Vector2i(DOOR, 0)


func _arrive() -> Vector2:
	return world.floors.cell_centre(_door_cell() + Vector2i(0, 1))


## Somewhere in the cellar's room for a villager come down: by the back walls, clear of the way out.
func stand_spot() -> Vector2:
	return world.floors.cell_centre(AT + Vector2i(randi_range(1, side - 2), randi_range(2, side - 1))) + Vector2(randf_range(-0.2, 0.2), randf_range(-0.1, 0.1)) * world.px


## Someone going down or coming up by the cellar nearest [param near] (px): its doors open (heard, if they were shut)
## and stay open a while, so comings and goings one after another don't bang them open and shut. They don't open by
## themselves; left alone, they close.
func use_doors(near: Vector2) -> void:
	var at: Variant = null
	var best := 4.0 * world.px
	for c in all():
		if c.distance_to(near) < best:
			best = c.distance_to(near)
			at = c
	if at == null:
		return
	if not _open_until.has(at):
		Sfx.play(world, Sfx.stream(OPEN_SOUND), at, 0.7, 0.05)
		_show_doors(at, true)
	_open_until[at] = Time.get_ticks_msec() / 1000.0 + STAYS_OPEN


# The doors at [param at] (px) drawn open or shut (their art for the way they face).
func _show_doors(at: Vector2, open: bool) -> void:
	# (by its drawn node: one placed freely, off the grid, has no cell to look it up by)
	for e in world.props.drawn_named("Cellar"):
		if e.pos.distance_to(at) > 0.3 * world.px:
			continue
		var node: Node2D = e.node
		if node == null or not is_instance_valid(node) or node.get_child_count() == 0:
			return
		var which := ("CellarOpen" if open else "Cellar") + ("SE" if int(e.e.turn) % 2 == 1 else "SW")
		if _art.is_empty():
			for i in world.sprites.size():
				if str(world.sprites[i].name).begins_with("Cellar"):
					_art[str(world.sprites[i].name)] = i
		if _art.has(which):
			world.show_frame(node.get_child(0) as Sprite2D, int(_art[which]), Vector2.ONE * PropMap._scale(float(e.e.scale)))
		return


## In front of the cellar doors at [param at] (px): just off the middle of their low edge, the way they open (down-left,
## or turned, down-right), where whoever uses them stands and comes back up.
func front_of(at: Vector2) -> Vector2:
	var right := false
	for e in world.props.entries_named("Cellar"):
		if e.pos.distance_to(at) < 0.3 * world.px:
			right = int(e.e.turn) % 2 == 1
	return at + Vector2(0.95 if right else -0.95, 0.48) * world.px


## Where a villager stands to put food in the cellar nearest [param from] (px): beside its trapdoor; null with none.
func deposit_spot(from: Vector2) -> Variant:
	var best: Variant = null
	var best_d := INF
	for at in all():
		if at.distance_to(from) < best_d:
			best_d = at.distance_to(from)
			best = front_of(at)
	return best


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E and prompt.visible:
		_pressed = true
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_U and prompt.visible:
		_expand = true


func _process(_delta: float) -> void:
	var pressed := _pressed or WorldPrompts.take(prompt)
	_pressed = false
	var expanding := _expand
	_expand = false
	prompt.visible = false
	# A villager nearly at the doors on their way down: the doors open for them before they get there (not as they
	# vanish), and are kept open while anyone's down below.
	var cellars := all()
	if not cellars.is_empty():
		for v in Villager.all:
			if not is_instance_valid(v):
				continue
			if v.state == Villager.State.CELLAR:
				use_doors(v._cellar_from)
			elif v._via_cellar and (v.state == Villager.State.TO_STORE or v.state == Villager.State.TO_EAT):
				for c in cellars:
					if c.distance_to(v.position) < 2.2 * world.px:
						use_doors(c)
	# Doors nobody's used for a while swing shut.
	if not _open_until.is_empty():
		var now := Time.get_ticks_msec() / 1000.0
		for at in _open_until.keys():
			if now >= float(_open_until[at]):
				_open_until.erase(at)
				Sfx.play(world, Sfx.stream(CLOSE_SOUND), at, 0.7, 0.05)
				_show_doors(at, false)
	if _busy or miko == null or miko.locked or BuildMode.is_open():
		return
	if inside(miko.position):
		# Out through the doorway (past the front wall's line): back up.
		if world.floors.fractional_cell(miko.position).y < AT.y - 0.15:
			_go(false)
		return
	var near: Variant = null
	var best := RANGE * world.px
	for at in all():
		if at.distance_to(miko.position) < best:
			best = at.distance_to(miko.position)
			near = at
	if near == null:
		return
	prompt.visible = true
	prompt.text = "E  Cellar (level %d)  ·  keeps %d food cold" % [level, holds()]
	var cost := expand_cost()
	if not cost.is_empty():
		prompt.text += "\nU  Expand: keeps %d  ·  %s" % [int(LEVELS[level].holds), ", ".join(cost.map(func(c): return "%d %s" % [c[1], UiKit.resource_name(c[0]).to_lower()]))]
	WorldPrompts.at(prompt, (near as Vector2) + Vector2(0, -0.5 * world.px))
	if expanding and not cost.is_empty():
		if expand():
			FloatingText.spawn(world, "Cellar expanded: keeps %d" % holds(), (near as Vector2) + Vector2(0, -1.2 * world.px), Color(1, 0.86, 0.45))
		else:
			FloatingText.spawn(world, "Not enough to expand it", (near as Vector2) + Vector2(0, -1.2 * world.px), Color(1, 0.6, 0.5))
		return
	if pressed:
		_came_from = near
		_go(true)


# Fade to black, move, fade back in.
func _go(down: bool) -> void:
	_busy = true
	if _came_from != Vector2.INF:
		use_doors(_came_from)
	var was_locked := miko.locked
	miko.locked = true
	_fade.visible = true
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.3)
	await tw.finished
	var up: Vector2 = front_of(_came_from) if _came_from != Vector2.INF else world.village.centre()
	miko.place(_arrive() if down else up)
	miko.velocity = Vector2.ZERO
	await get_tree().create_timer(0.15).timeout
	tw = create_tween()
	tw.tween_property(_fade, "color:a", 0.0, 0.35)
	await tw.finished
	_fade.visible = false
	miko.locked = was_locked
	_busy = false


# The cellar: cobbles, stone walls on all four sides (the two near ones seen through), a doorway in the front, earth
# round it and dark beyond, a lamp's light over it.
func _room() -> void:
	for n in _built:
		if is_instance_valid(n):
			n.queue_free()
	_built = []
	var f := world.floors
	var px := world.px
	var ground := Node2D.new()
	ground.name = "CellarFloor"
	world.add_ground_layer(ground, -9975)   # (under build mode's grid)
	_built.append(ground)
	# The dark, then earth for a few cells round the room, then its cobbles.
	var mid := f.corner(Vector2(AT) + Vector2(side, side) / 2.0)
	var dark := ColorRect.new()
	dark.color = Color(0.05, 0.04, 0.04)
	dark.mouse_filter = Control.MOUSE_FILTER_IGNORE   # (else build mode takes the mouse to be over the interface down here)
	dark.size = Vector2(60, 40) * px
	dark.position = mid - dark.size / 2.0
	ground.add_child(dark)
	var tile := int((f.types[FLOOR].whole as Array)[0].sprite)
	for x in range(-4, side + 4):
		for y in range(-4, side + 4):
			var room := x >= 0 and y >= 0 and x < side and y < side
			var sp := Sprite2D.new()
			world.show_frame(sp, tile)
			sp.position = f.cell_centre(AT + Vector2i(x, y))
			if not room:
				# (packed earth: the same stones, dark and brown, darker further out)
				var far := maxi(maxi(-x, x - side + 1), maxi(-y, y - side + 1))
				sp.modulate = Color(0.42, 0.3, 0.22).darkened(0.18 * far)
				# (out through the gap: black)
				if x == _door_cell().x - AT.x and y < 0:
					sp.modulate = Color(0.03, 0.03, 0.03)
			ground.add_child(sp)
	# The walls: the back two solid, the front two seen through; the doorway in the front one along x.
	var wt: Dictionary = world.walls.types[WALL]
	for i in side:
		_wall(Vector2(AT.x + i + 0.5, AT.y + side), int(wt.left), 1.0)
		_wall(Vector2(AT.x + side, AT.y + i + 0.5), int(wt.leftY), 1.0)
		_wall(Vector2(AT.x, AT.y + i + 0.5), int(wt.leftY), FRONT_ALPHA)
		# (the way out: a gap in the front wall, dark beyond it)
		if AT.x + i != _door_cell().x:
			_wall(Vector2(AT.x + i + 0.5, AT.y), int(wt.left), FRONT_ALPHA)
	# A lamp's light, so it isn't dark down there at night.
	var lamp := PointLight2D.new()
	lamp.texture = Fires._glow()
	lamp.color = Color(1.0, 0.8, 0.55)
	lamp.energy = 0.9
	lamp.texture_scale = 7.0 * 2.0 * px / float(Fires._glow().get_width())
	lamp.position = mid + Vector2(0, -0.6 * px)
	lamp.texture_scale *= float(side) / 5.0
	world.add_child(lamp)
	_built.append(lamp)
	# Walked into, not through: round the room, open at the doorway, and a little porch past it (where stepping out
	# takes her back up).
	var d := Vector2(_door_cell())
	var a := Vector2(AT)
	var pts: Array[Vector2] = [f.corner(d + Vector2(0, -1)), f.corner(d), f.corner(a), f.corner(a + Vector2(0, side)), f.corner(a + Vector2(side, side)),
		f.corner(a + Vector2(side, 0)), f.corner(d + Vector2(1, 0)), f.corner(d + Vector2(1, -1))]
	for i in pts.size() - 1:
		var shape := CollisionShape2D.new()
		var seg := SegmentShape2D.new()
		seg.a = pts[i]
		seg.b = pts[i + 1]
		shape.shape = seg
		world.solids.add_child(shape)
		_built.append(shape)


# A wall panel standing on the middle of an edge (fractional cell coordinates of that middle), sorted there.
func _wall(edge_mid: Vector2, sprite_id: int, alpha: float) -> void:
	if sprite_id < 0:
		return
	var holder := Node2D.new()
	holder.position = world.floors.corner(edge_mid)
	var sp := Sprite2D.new()
	world.show_frame(sp, sprite_id)
	sp.modulate.a = alpha
	holder.add_child(sp)
	world.things.add_child(holder)
	_built.append(holder)
