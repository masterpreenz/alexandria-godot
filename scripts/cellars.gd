class_name Cellars
extends Node
## Cellars: cold storage under a house. Each Cellar (a trapdoor in the floor) keeps [constant HOLDS] of the village's
## food cold, where it spoils a quarter as fast (Spoilage asks [method cold_share]). E at one takes Miko down into the
## cellar itself, fading to black and out again: for now one plain underground room for all of them (dummy textures),
## its shelves standing in for what's kept, free of mist, with its steps back up at the bottom, which bring her out
## at the trapdoor she went down.

const HOLDS := 100                ## food a cellar keeps cold
const COLD_RATE := 0.25           ## how fast cold food spoils, of the usual
const RANGE := 0.9                ## units from a trapdoor to use it
## The room, in units, well off the map (below it, beside the cave's).
const ROOM := Rect2(140.0, 163.0, 12.0, 8.0)   ## (well clear of the cave: its dark surround would cover this)
const RIM := 0.8

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
	return active != null and ROOM.grow(RIM).has_point(at / active.world.px)


func _steps() -> Vector2:
	return Vector2(ROOM.get_center().x, ROOM.end.y - 0.6) * world.px


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
		if miko.position.distance_to(_steps()) < 0.9 * world.px:
			prompt.visible = true
			prompt.text = "E  Back up"
			WorldPrompts.at(prompt, _steps() + Vector2(0, -0.5 * world.px))
			if pressed:
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
	WorldPrompts.at(prompt, (near as Vector2) + Vector2(0, -0.3 * world.px))
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
	var up: Vector2 = _came_from + Vector2(0, 0.5 * world.px) if _came_from != Vector2.INF else world.village.centre()
	miko.place(_steps() + Vector2(0, -1.4 * world.px) if down else up)
	miko.velocity = Vector2.ZERO
	await get_tree().create_timer(0.15).timeout
	tw = create_tween()
	tw.tween_property(_fade, "color:a", 0.0, 0.35)
	await tw.finished
	_fade.visible = false
	miko.locked = was_locked
	_busy = false


# The stand-in cellar: a stone floor, earth walls round it, shelves along the back, and the steps up.
func _room() -> void:
	var px := world.px
	var room := Node2D.new()
	room.name = "CellarRoom"
	room.z_as_relative = false
	room.z_index = -100
	world.add_child(room)
	var r := Rect2(ROOM.position * px, ROOM.size * px)
	var rim := RIM * px
	_quad(room, r.grow(30.0 * px), Mountains._checker(Color(0.05, 0.04, 0.04), Color(0.05, 0.04, 0.04)))
	_quad(room, r.grow(rim), Mountains._checker(Color(0.3, 0.24, 0.2), Color(0.26, 0.21, 0.18)))
	_quad(room, Rect2(r.position + Vector2(0, rim), r.size - Vector2(0, rim)), Mountains._checker(Color(0.34, 0.36, 0.42), Color(0.3, 0.32, 0.38)))
	# Shelves along the back wall, and barrels (plain blocks for now).
	for i in 5:
		_quad(room, Rect2(r.position + Vector2((0.6 + i * 2.25) * px, rim + 0.1 * px), Vector2(1.7, 0.7) * px), Mountains._checker(Color(0.5, 0.36, 0.22), Color(0.44, 0.31, 0.19)))
	var steps := _steps()
	_quad(room, Rect2(steps.x - 0.8 * px, r.end.y - 0.8 * px, 1.6 * px, 0.9 * px), Mountains._checker(Color(0.78, 0.74, 0.62), Color(0.72, 0.68, 0.56)))
	var pts: Array[Vector2] = [r.end, Vector2(r.position.x, r.end.y), r.position + Vector2(0, rim + 0.8 * px), Vector2(r.end.x, r.position.y + rim + 0.8 * px), r.end]
	for i in pts.size() - 1:
		var shape := CollisionShape2D.new()
		var seg := SegmentShape2D.new()
		seg.a = pts[i]
		seg.b = pts[i + 1]
		shape.shape = seg
		world.solids.add_child(shape)


func _quad(parent: Node2D, rect: Rect2, tex: Texture2D) -> void:
	var sp := Sprite2D.new()
	sp.texture = tex
	sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sp.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	sp.region_enabled = true
	sp.region_rect = Rect2(Vector2.ZERO, rect.size / world.px * 8.0)
	sp.scale = Vector2.ONE * world.px / 8.0
	sp.centered = false
	sp.position = rect.position
	parent.add_child(sp)
