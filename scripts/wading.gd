class_name Wading
extends Node2D
## Wading at the water's edge (from Unity's Wading): the deeper in, the further the body sinks, with everything below
## the waterline cut away so the water shows instead; a ring of ripples where the water meets the body, gently
## swelling, and rings spreading behind as it moves; a splash going in. The walker slows down in the water, and their
## shadow goes. Depth comes from the water's own depth map (cells in from its edge).

const FULL_DEPTH := 0.7     ## cells in at which the body has sunk all it will
const SINK_SHARE := 0.32    ## of the body's height, sunk at full depth
const SLOW_SHARE := 0.35    ## of the speed lost at full depth

var world: World
var walker: Node2D          ## whose feet (this node sits on them)
var body: Sprite2D          ## the art that sinks
var shadow: Sprite2D
var depth := 0.0            ## 0 dry .. 1 in to full depth
var wading := false
var _rest := Vector2.ZERO   ## the body's place on dry land
var extra := Vector2.ZERO   ## a lift or jolt on top (thrown in the air, flinching from a hit)
var _height := 0.0
var _last_ripple := Vector2.ZERO
var _next_ripple := 0.0
var _mat: ShaderMaterial
var _wake: WaterWake


func setup(w: World, who: Node2D, art: Sprite2D, ground_shadow: Sprite2D) -> void:
	world = w
	walker = who
	body = art
	shadow = ground_shadow
	_rest = body.position
	_mat = ShaderMaterial.new()
	_mat.shader = preload("res://shaders/wading.gdshader")
	body.material = _mat
	# The river splitting round them while they stand in a current.
	_wake = WaterWake.make(world, who, Vector2.ZERO, 0.4 * world.px)
	_wake.strength = 0.0


func _process(delta: float) -> void:
	if walker == null:
		return
	var feet: Vector2 = walker.global_position
	var target := clampf(world.water_depth(feet) / FULL_DEPTH, 0.0, 1.0)
	depth = move_toward(depth, target, delta * 3.0)
	_wake.strength = depth if body.visible else 0.0
	_wake.width = maxf(0.3 * world.px, World.sprite_rect(body).size.x * 0.35)
	if walker.get("speed_scale") != null:
		walker.set("speed_scale", 1.0 - SLOW_SHARE * depth)
	if depth <= 0.01 or not body.visible:
		if wading:
			_dry()
		return
	if not wading:
		_wet(feet)
	# How tall the body stands (its top above the feet), measured on dry land so sinking doesn't shrink it.
	if _height <= 0.0:
		_height = maxf(38.0, -World.sprite_rect(body).position.y + feet.y) * 0.75
	body.position = _rest + Vector2(0, depth * SINK_SHARE * _height) + extra
	_mat.set_shader_parameter("waterline", feet.y + 2.0)
	# Rings spreading behind as it moves through the water.
	var width := maxf(45.0, World.sprite_rect(body).size.x * 0.42)
	var now := Time.get_ticks_msec() / 1000.0
	if feet.distance_to(_last_ripple) > 0.18 * world.px and now >= _next_ripple:
		_next_ripple = now + 0.22
		_last_ripple = feet
		Ripples.spawn(world, feet, width, depth)
	queue_redraw()


# The ring where the water meets the body, just over it, gently swelling.
func _draw() -> void:
	if not wading:
		return
	var width := maxf(45.0, World.sprite_rect(body).size.x * 0.42)
	var swell := 1.0 + 0.06 * sin(Time.get_ticks_msec() / 1000.0 * 4.0 + walker.global_position.x)
	var r := width * swell * (0.8 + 0.2 * depth) * 0.5
	draw_set_transform(Vector2(0, -2), 0.0, Vector2(1.0, 0.5))
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(0.9, 0.97, 1.0, 0.75 * depth), 3.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _wet(feet: Vector2) -> void:
	wading = true
	if shadow != null:
		shadow.visible = false
	_last_ripple = feet
	Ripples.spawn(world, feet, 64.0, 1.0)  # a splash going in


func _dry() -> void:
	wading = false
	body.position = _rest + extra
	_mat.set_shader_parameter("waterline", 1e9)
	if shadow != null:
		shadow.visible = true
	if walker.get("speed_scale") != null:
		walker.set("speed_scale", 1.0)
	queue_redraw()


## Rings spreading on the water and fading (Unity's Ripples): drawn over the water, under everything standing.
class Ripples extends Node2D:
	var rings := []  # [position, width, strength, age]

	static func spawn(w: World, at: Vector2, width: float, strength: float) -> void:
		var fx := w.water_fx()
		var r: Ripples = fx.get_node_or_null("Ripples")
		if r == null:
			r = Ripples.new()
			r.name = "Ripples"
			fx.add_child(r)
		r.rings.append([at, width, strength, 0.0])

	func _process(delta: float) -> void:
		for ring in rings:
			ring[3] += delta
		rings = rings.filter(func(ring): return ring[3] < 1.1)
		queue_redraw()

	func _draw() -> void:
		for ring in rings:
			var t: float = ring[3] / 1.1
			var r: float = ring[1] * (0.5 + 1.1 * t)
			draw_set_transform(ring[0], 0.0, Vector2(1.0, 0.5))
			draw_arc(Vector2.ZERO, r, 0.0, TAU, 36, Color(0.9, 0.97, 1.0, 0.55 * ring[2] * (1.0 - t)), 2.5, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
