class_name DustTrail
extends Node2D
## Dust puffs kicked up at a character's feet while moving, more when running (from Unity's DustTrail and its
## particle settings): each rises a little, swells and fades. It sits among the world's y-sorted things just behind
## the character, and draws its puffs where they were kicked up.

const TEX := preload("res://assets/Art/Effects/Dust.png")

var target: Node2D               ## whose feet
var walk_rate := 3.0             ## puffs per unit travelled, walking
var run_rate := 6.0
var unit := 128.0
var puffs := []                  # [world pos, velocity, age, life, size]
var _last := Vector2.INF
var _owed := 0.0


func _process(delta: float) -> void:
	var __t := Time.get_ticks_usec()
	_process_timed(delta)
	Perf.add(&"dust_trail.process", __t)


func _process_timed(delta: float) -> void:
	if target == null:
		return
	var feet: Vector2 = target.drawn_position() if target.has_method("drawn_position") else target.position
	position = feet + Vector2(0, -0.5)  # just behind them in the y-sort
	if _last == Vector2.INF:
		_last = feet
	var moved := feet.distance_to(_last) / unit
	_last = feet
	var running: bool = target.get("running") and target.get("moving")
	_owed += moved * (run_rate if running else walk_rate)
	while _owed >= 1.0 and puffs.size() < 60:
		_owed -= 1.0
		var a := randf() * TAU
		var r := randf() * 0.08 * unit
		var at := feet + Vector2(cos(a) * r, sin(a) * r * 0.5 - 0.04 * unit)
		var dir := Vector2(cos(a), sin(a) * 0.5).normalized()
		puffs.append([at, dir * randf_range(0.05, 0.2) * unit, 0.0, randf_range(0.45, 0.7), randf_range(0.2, 0.34) * unit])
	for p in puffs:
		p[2] += delta
		p[1].y -= 0.03 * 9.81 * unit * delta * 0.1  # a faint lift
		p[0] += p[1] * delta
	puffs = puffs.filter(func(p): return p[2] < p[3])
	queue_redraw()


func _draw() -> void:
	for p in puffs:
		var t: float = p[2] / p[3]
		var grow := lerpf(0.6, 1.0, t / 0.3) if t < 0.3 else lerpf(1.0, 1.5, (t - 0.3) / 0.7)
		var alpha := t / 0.12 if t < 0.12 else (lerpf(1.0, 0.6, (t - 0.12) / 0.38) if t < 0.5 else lerpf(0.6, 0.0, (t - 0.5) / 0.5))
		var size: float = p[4] * grow
		draw_texture_rect(TEX, Rect2(p[0] - position - Vector2(size, size) * 0.5, Vector2(size, size)), false, Color(1, 1, 1, alpha))
