class_name Cellars
extends Node
## Cellars: cold storage underground. Each Cellar (its doors set in the ground outdoors, in the village) keeps [constant HOLDS] of the village's
## food cold, where it spoils a quarter as fast (Spoilage asks [method cold_share]). E at one takes Miko down into the
## cellar itself, fading to black and out again: one underground room for all of them, cobbled, stone walls round
## it, earth beyond, lit by a lamp, free of mist. Walking out through the doorway in its front wall brings her back
## up at the trapdoor she went down. The villagers bring the food they carry to a cellar rather than a chest.

const HOLDS := 100                ## food a cellar keeps cold
const COLD_RATE := 0.25           ## how fast cold food spoils, of the usual
const RANGE := 1.7                ## units from the cellar's doors to use them (they're two tiles across)
## The room: its first cell (well off the map, past the outskirts) and how many cells a side (more, levelled up
## some day). A doorway in the middle of its front wall is the way out.
const AT := Vector2i(300, -300)
const SIDE := 5
const FLOOR := "PathCobble"
const WALL := "FieldstoneWall"
const FRONT_ALPHA := 0.3          ## how solid the two near walls are drawn (seen through, as a house's)

static var active: Cellars

var world: World
var miko: Miko
var prompt: Label
var _fade: ColorRect
var _busy := false
var _pressed := false
var _came_from := Vector2.INF     ## the trapdoor she went down (px)


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


## The cellars in the village: where each trapdoor is (px).
func all() -> Array:
	return world.props_named("Cellar").filter(func(at): return world.village.contains(at))


## How much food the cellars keep cold between them.
func holds() -> int:
	return all().size() * HOLDS


## The share of the village's food that's in the cold (0 to 1): the cellars' room over all the food stored.
func cold_share() -> float:
	var room := holds()
	if room <= 0:
		return 0.0
	var food := 0
	for r in Spoilage.PER_DAY:
		food += world.village.stored(r)
	return 1.0 if food <= room else float(room) / float(food)


## Whether [param at] (px) is down in the cellar (underground: out of the mist and the cold).
static func inside(at: Vector2) -> bool:
	if active == null:
		return false
	var c := active.world.floors.fractional_cell(at) - Vector2(AT)
	return c.x > -3.0 and c.y > -3.0 and c.x < SIDE + 3.0 and c.y < SIDE + 3.0


## Whether [param cell] is one of the cellar room's floor cells: things can be built there (it counts as in the
## village and indoors), though the villagers don't go down.
static func room_has(cell: Vector2i) -> bool:
	return cell.x >= AT.x and cell.y >= AT.y and cell.x < AT.x + SIDE and cell.y < AT.y + SIDE


# The doorway's cell (in the front wall along y = AT.y), and where she arrives: a step inside it.
func _door_cell() -> Vector2i:
	@warning_ignore("integer_division")
	return AT + Vector2i(SIDE / 2, 0)


func _arrive() -> Vector2:
	return world.floors.cell_centre(_door_cell() + Vector2i(0, 1))


## Somewhere in the cellar's room for a villager come down: by the back walls, clear of the way out.
func stand_spot() -> Vector2:
	return world.floors.cell_centre(AT + Vector2i(randi_range(1, SIDE - 2), randi_range(2, SIDE - 1))) + Vector2(randf_range(-0.2, 0.2), randf_range(-0.1, 0.1)) * world.px


## Where a villager stands to put food in the cellar nearest [param from] (px): beside its trapdoor; null with none.
func deposit_spot(from: Vector2) -> Variant:
	var best: Variant = null
	var best_d := INF
	for at in all():
		if at.distance_to(from) < best_d:
			best_d = at.distance_to(from)
			best = at + Vector2(0, 1.25 * world.px)   # (in front of the doors, clear of them)
	return best


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E and prompt.visible:
		_pressed = true


func _process(_delta: float) -> void:
	var pressed := _pressed
	_pressed = false
	prompt.visible = false
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
	prompt.text = "E  Cellar  ·  keeps %d food cold" % HOLDS
	WorldPrompts.at(prompt, (near as Vector2) + Vector2(0, -0.5 * world.px))
	if pressed:
		_came_from = near
		_go(true)


# Fade to black, move, fade back in.
func _go(down: bool) -> void:
	_busy = true
	var was_locked := miko.locked
	miko.locked = true
	_fade.visible = true
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.3)
	await tw.finished
	var up: Vector2 = _came_from + Vector2(0, 1.25 * world.px) if _came_from != Vector2.INF else world.village.centre()
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
	var f := world.floors
	var px := world.px
	var ground := Node2D.new()
	ground.name = "CellarFloor"
	world.add_ground_layer(ground, -9975)   # (under build mode's grid)
	# The dark, then earth for a few cells round the room, then its cobbles.
	var mid := f.corner(Vector2(AT) + Vector2(SIDE, SIDE) / 2.0)
	var dark := ColorRect.new()
	dark.color = Color(0.05, 0.04, 0.04)
	dark.mouse_filter = Control.MOUSE_FILTER_IGNORE   # (else build mode takes the mouse to be over the interface down here)
	dark.size = Vector2(60, 40) * px
	dark.position = mid - dark.size / 2.0
	ground.add_child(dark)
	var tile := int((f.types[FLOOR].whole as Array)[0].sprite)
	for x in range(-4, SIDE + 4):
		for y in range(-4, SIDE + 4):
			var room := x >= 0 and y >= 0 and x < SIDE and y < SIDE
			var sp := Sprite2D.new()
			world.show_frame(sp, tile)
			sp.position = f.cell_centre(AT + Vector2i(x, y))
			if not room:
				# (packed earth: the same stones, dark and brown, darker further out)
				var far := maxi(maxi(-x, x - SIDE + 1), maxi(-y, y - SIDE + 1))
				sp.modulate = Color(0.42, 0.3, 0.22).darkened(0.18 * far)
				# (out through the gap: black)
				if x == _door_cell().x - AT.x and y < 0:
					sp.modulate = Color(0.03, 0.03, 0.03)
			ground.add_child(sp)
	# The walls: the back two solid, the front two seen through; the doorway in the front one along x.
	var wt: Dictionary = world.walls.types[WALL]
	for i in SIDE:
		_wall(Vector2(AT.x + i + 0.5, AT.y + SIDE), int(wt.left), 1.0)
		_wall(Vector2(AT.x + SIDE, AT.y + i + 0.5), int(wt.leftY), 1.0)
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
	world.add_child(lamp)
	# Walked into, not through: round the room, open at the doorway, and a little porch past it (where stepping out
	# takes her back up).
	var d := Vector2(_door_cell())
	var a := Vector2(AT)
	var pts: Array[Vector2] = [f.corner(d + Vector2(0, -1)), f.corner(d), f.corner(a), f.corner(a + Vector2(0, SIDE)), f.corner(a + Vector2(SIDE, SIDE)),
		f.corner(a + Vector2(SIDE, 0)), f.corner(d + Vector2(1, 0)), f.corner(d + Vector2(1, -1))]
	for i in pts.size() - 1:
		var shape := CollisionShape2D.new()
		var seg := SegmentShape2D.new()
		seg.a = pts[i]
		seg.b = pts[i + 1]
		shape.shape = seg
		world.solids.add_child(shape)


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
