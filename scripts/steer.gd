class_name Steer
extends RefCounted
## Gets a creature round things instead of stuck on them (from Unity's Steer). Each tick it takes the velocity the
## creature wants and, if something fixed stands a short way ahead (a tree, a rock, a wall; not other creatures or
## Miko, which move), turns it aside to the first clear way, keeping to one side for a while so it doesn't dither. It
## also watches progress: [member stuck] is true for a tick when the creature has tried to move but barely has.

const ANGLES := [25.0, 50.0, 75.0, 100.0, 130.0]

var body: CharacterBody2D
var shape: Shape2D
var shape_at := Vector2.ZERO
var look := 0.4 * 128.0       ## px ahead to look
var side := 0                 ## which way it's going round: 1 left, -1 right, 0 not yet
var side_until := 0.0
var check_from := Vector2.ZERO
var check_at := -1.0
var wanted := 0.0
var stuck := false


func _init(b: CharacterBody2D, s: Shape2D, offset: Vector2, look_px: float) -> void:
	body = b
	shape = s
	shape_at = offset
	look = look_px


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


## The velocity to use instead of [param velocity]: the same speed, turned round anything fixed ahead.
func around(velocity: Vector2, delta: float) -> Vector2:
	var t := Time.get_ticks_usec()
	var r := _around(velocity, delta)
	Perf.add(&"AI: steering", t)
	return r


func _around(velocity: Vector2, delta: float) -> Vector2:
	_track(velocity, delta)
	var speed := velocity.length()
	if speed < 0.001:
		return velocity
	var dir := velocity / speed
	if _clear(dir):
		if _now() >= side_until:
			side = 0
		return velocity
	# Blocked: try turning to the side it's already going round first, then the other.
	if side == 0:
		side = 1 if randf() < 0.5 else -1
	for a in ANGLES:
		for s in 2:
			var sign := side if s == 0 else -side
			var turned := dir.rotated(deg_to_rad(a * sign))
			if not _clear(turned):
				continue
			side = sign
			side_until = _now() + 1.2
			return turned * speed
	# Boxed in on every side ahead: back off a little.
	return -dir * speed * 0.5


## Forgets progress so far (it stopped on purpose, or was carried somewhere).
func reset() -> void:
	check_at = -1.0
	wanted = 0.0
	stuck = false


# Sums how far it meant to go over the last second against how far it got.
func _track(velocity: Vector2, delta: float) -> void:
	stuck = false
	var now := _now()
	if check_at < 0.0:
		check_at = now + 1.0
		check_from = body.position
		wanted = 0.0
	wanted += velocity.length() * delta
	if now < check_at:
		return
	var got := body.position.distance_to(check_from)
	if wanted > 0.3 * 128.0 and got < wanted * 0.25:
		stuck = true
		side = -side  # whichever way it was going round didn't work: try the other next
	check_at = now + 1.0
	check_from = body.position
	wanted = 0.0


func _clear(dir: Vector2) -> bool:
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = shape
	q.transform = Transform2D(0.0, body.global_position + shape_at)
	q.motion = dir * look
	q.collision_mask = 1  # the fixed world only
	q.exclude = [body.get_rid()]
	var r := body.get_world_2d().direct_space_state.cast_motion(q)
	return r.size() == 0 or r[0] >= 1.0
