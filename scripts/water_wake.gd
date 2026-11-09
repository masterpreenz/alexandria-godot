class_name WaterWake
extends Node2D
## The river splitting round something standing in it (from Unity's WaterWake): a bridge piling, or someone wading.
## Foam heaped against its upstream face and pushed aside, and a wake of foam streaks trailing away downstream from
## both its sides, opening into a V. It follows the river's own flow where it stands, and is still in a pond (no
## current) or on dry land. Drawn over the water, under the bridge's planks and anyone standing.

const RATE := 70.0      ## foam flecks a second (all four streams together), at full strength
const FLECK := 0.11     ## how big a fleck is, in world units

var world: World
var target: Node2D       ## what stands in the water (its foot); or a fixed spot ([member at])
var at := Vector2.ZERO
var width := 51.2        ## how wide it is in the water, px: where the wake leaves its sides
var strength := 1.0      ## 0-1: a piling always 1, someone wading by how deep they are
var flow_lift := 0.0     ## px above its foot, where the river's flow is read (a point surely in the water)
var foam_lift := 0.0     ## px above its foot, where the foam churns (where it meets the water)

var _flecks := []        # [position, velocity, age, life, size, alpha]
var _owed := 0.0


## Makes one over the water for [param who] (or the spot [param spot]), as wide as [param w] px.
static func make(w: World, who: Node2D, spot: Vector2, w_px: float) -> WaterWake:
	var wake := WaterWake.new()
	wake.world = w
	wake.target = who
	wake.at = spot
	wake.width = w_px
	var fx := w.water_fx()
	fx.add_child(wake)
	return wake


func _process(delta: float) -> void:
	var __t := Time.get_ticks_usec()
	_process_timed(delta)
	Perf.add(&"water_wake.process", __t)


func _process_timed(delta: float) -> void:
	for f in _flecks:
		f[2] += delta
		f[0] += f[1] * delta
	_flecks = _flecks.filter(func(f): return f[2] < f[3])
	_emit(delta)
	queue_redraw()


func _emit(delta: float) -> void:
	if strength <= 0.01:
		return
	var foot: Vector2 = (target.drawn_position() if target.has_method("drawn_position") else target.global_position) if target != null else at
	var flow: Dictionary = world.flow_at(foot + Vector2(0, -flow_lift))
	if flow.is_empty():
		return
	var down: Vector2 = flow.down     # px a second's worth: one cell downstream
	var side: Vector2 = flow.side     # one cell across
	var speed: float = flow.speed     # cells a second
	var dir := down.normalized()
	var side_dir := side.normalized()
	var half := width * 0.5
	var origin := foot + Vector2(0, -foam_lift)
	var fleck_px := FLECK * world.px * (0.7 + 0.6 * width / world.px)
	_owed += RATE * strength * delta
	while _owed >= 1.0 and _flecks.size() < 200:
		_owed -= 1.0
		var flank := 1.0 if randf() < 0.5 else -1.0
		if randf() < 0.35:
			# The bow: foam heaped against the upstream face, pushed out to the sides.
			_flecks.append([origin - dir * half * 0.6 + side_dir * randf_range(-half, half) * 0.6,
				down * speed * randf_range(0.5, 0.8) + side * speed * flank * randf_range(0.12, 0.25),
				0.0, randf_range(0.35, 0.55), fleck_px * randf_range(0.8, 1.3), lerpf(0.6, 1.0, strength)])
		else:
			# The wake: from each side, carried downstream and opening outwards into a V.
			_flecks.append([origin + side_dir * half * flank * randf_range(0.8, 1.1) + dir * randf_range(-0.05, 0.1) * world.px,
				down * speed * randf_range(0.9, 1.2) + side * speed * flank * randf_range(0.04, 0.1),
				0.0, randf_range(0.9, 1.4), fleck_px * randf_range(0.6, 1.0), lerpf(0.6, 1.0, strength)])


func _draw() -> void:
	var tex := Waterfall._dot(32, 0.6)
	for f in _flecks:
		var t: float = f[2] / f[3]
		var grow := lerpf(0.5, 1.0, t / 0.25) if t < 0.25 else lerpf(1.0, 1.5, (t - 0.25) / 0.75)
		var alpha := t / 0.12 if t < 0.12 else (lerpf(1.0, 0.6, (t - 0.12) / 0.43) if t < 0.55 else lerpf(0.6, 0.0, (t - 0.55) / 0.45))
		var size: float = f[4] * grow
		var vel: Vector2 = f[1]
		# A streak drawn along the way it's carried.
		var length := size * 1.4 + vel.length() * 0.08
		draw_set_transform(f[0], vel.angle(), Vector2(length / size, 0.6))
		draw_texture_rect(tex, Rect2(-Vector2(size, size) * 0.5, Vector2(size, size)), false, Color(0.96, 0.99, 1.0, alpha * f[5]))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
