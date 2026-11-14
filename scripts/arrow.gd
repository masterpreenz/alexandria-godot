class_name Arrow
extends Node2D
## A hunter's arrow: loosed from the bow at what they're hunting, it flies in a shallow arc to where it was when they
## let go (a little ahead of it, if it's running) and hurts it if it's still there; a miss sticks in the ground a
## moment and fades.

const SPEED := 16.0               ## units a second
const LENGTH := 0.42              ## units, shaft and head
const STUCK_FOR := 1.2            ## seconds a miss stays in the ground

var world: World
var from := Vector2.ZERO
var to := Vector2.ZERO
var at: Damageable                ## what it's loosed at
var damage := 0.0
var by: Node2D                    ## the hunter who loosed it
var _gone := 0.0                  ## 0..1 of the way
var _flight := 1.0                ## seconds the flight takes
var _stuck_until := -1.0


## Loosed by [param hunter] from [param from_px] (px) at [param target], landing at [param land] (px), hurting [param amount].
static func loose(w: World, hunter: Node2D, from_px: Vector2, target: Damageable, land: Vector2, amount: float) -> Arrow:
	var a := Arrow.new()
	a.world = w
	a.by = hunter
	a.from = from_px
	a.to = land
	a.at = target
	a.damage = amount
	a._flight = maxf(0.08, from_px.distance_to(land) / (SPEED * w.px))
	a.position = from_px
	w.things.add_child(a)
	Sfx.play(w, Sfx.stream("res://assets/Sounds/bow_attack.mp3"), from_px, 0.7, 0.08)
	return a


func _process(delta: float) -> void:
	if _stuck_until >= 0.0:
		modulate.a = clampf((_stuck_until - Time.get_ticks_msec() / 1000.0) / 0.4, 0.0, 1.0)
		if modulate.a <= 0.0:
			queue_free()
		return
	_gone = minf(1.0, _gone + delta / _flight)
	position = from.lerp(to, _gone)
	queue_redraw()
	# (where it is now: still where it was aimed, it's hit; else, landed, it's a miss)
	if at != null and is_instance_valid(at) and at.alive() and at.global_position.distance_to(position) < 0.45 * world.px:
		# (it knows who shot it, before it feels it: a boar turns on the hunter, not on Miko)
		var c := at.get_parent() as Creature
		if c != null and by != null and is_instance_valid(by):
			c.hunter = by
			c.hunted_until = Time.get_ticks_msec() / 1000.0 + 15.0
		at.hurt(damage)
		queue_free()
		return
	if _gone >= 1.0:
		_stuck_until = Time.get_ticks_msec() / 1000.0 + STUCK_FOR
		queue_redraw()


func _draw() -> void:
	var dir := (to - from).normalized()
	if dir == Vector2.ZERO:
		return
	var px := world.px
	# (the arc: higher in the middle of the flight; stuck, it's tilted into the ground)
	var lift := -sin(_gone * PI) * 0.35 * px
	var tilt := dir.rotated(-0.5 * signf(dir.x if dir.x != 0.0 else 1.0) * (1.0 - _gone * 2.0)) if _stuck_until < 0.0 else (dir + Vector2(0, 0.9)).normalized()
	var tip := Vector2(0, lift) + tilt * LENGTH * 0.5 * px
	var tail := Vector2(0, lift) - tilt * LENGTH * 0.5 * px
	var w := maxf(1.0, 0.03 * px)
	draw_line(tail, tip, Color(0.55, 0.38, 0.22), w, true)
	var side := Vector2(-tilt.y, tilt.x) * 0.05 * px
	draw_colored_polygon(PackedVector2Array([tip + tilt * 0.09 * px, tip + side, tip - side]), Color(0.78, 0.8, 0.84))
	draw_line(tail, tail + tilt * 0.08 * px + side * 1.4, Color(0.92, 0.9, 0.85), w, true)
	draw_line(tail, tail + tilt * 0.08 * px - side * 1.4, Color(0.92, 0.9, 0.85), w, true)
