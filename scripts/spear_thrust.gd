class_name SpearThrust
extends Node2D
## The slash a spear thrust leaves (from Unity's SpearThrust): a bright streak shooting out along the line of the
## thrust, sharp at the tip and trailing off behind, a soft glow round it and a flash where the point ends up. It snaps
## out, thins and fades in a quarter of a second.

const LIFE := 0.26
const EXTEND := 0.07

var length := 0.0
var age := 0.0


static func play(w: World, from: Vector2, to: Vector2) -> void:
	var line := to - from
	if line.length_squared() < 1.0:
		return
	var t := SpearThrust.new()
	t.position = to
	t.rotation = line.angle()
	t.length = line.length() + 0.35 * w.px
	t.z_as_relative = false
	t.z_index = 3992
	w.add_child(t)


func _process(delta: float) -> void:
	var __t := Time.get_ticks_usec()
	_process_timed(delta)
	Perf.add(&"spear_thrust.process", __t)


func _process_timed(delta: float) -> void:
	age += delta
	if age >= LIFE:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	# Shoots out to full length, then thins away.
	var out := clampf(age / EXTEND, 0.0, 1.0)
	var fade := clampf((age - EXTEND) / (LIFE - EXTEND), 0.0, 1.0)
	var l := length * (1.0 - (1.0 - out) * (1.0 - out))
	_streak(l, lerpf(1.6, 0.6, fade) * 9.0, Color(0.75, 0.9, 1.0, 0.55 * (1.0 - fade)))
	_streak(l, lerpf(0.7, 0.15, fade) * 9.0, Color(1, 1, 1, 1.0 - fade * fade))
	# A quick flash at the point.
	var s := lerpf(0.35, 1.1, clampf(age / 0.12, 0.0, 1.0)) * 22.0
	var a := (1.0 - clampf(age / 0.18, 0.0, 1.0)) * out
	var c := Color(1, 0.97, 0.85, a)
	draw_circle(Vector2.ZERO, s * 0.45, Color(c, a * 0.6))
	draw_colored_polygon(PackedVector2Array([Vector2(-s, 0), Vector2(0, -s * 0.12), Vector2(s, 0), Vector2(0, s * 0.12)]), c)
	draw_colored_polygon(PackedVector2Array([Vector2(0, -s * 0.7), Vector2(s * 0.12, 0), Vector2(0, s * 0.7), Vector2(-s * 0.12, 0)]), c)


# A streak ending at the tip (here), widest just short of it and tapering away behind.
func _streak(l: float, half: float, c: Color) -> void:
	if l <= 1.0 or c.a <= 0.0:
		return
	var pts := PackedVector2Array([Vector2(0, 0), Vector2(-l * 0.12, -half), Vector2(-l, -half * 0.05), Vector2(-l, half * 0.05), Vector2(-l * 0.12, half)])
	var cols := PackedColorArray([c, c, Color(c, 0.0), Color(c, 0.0), c])
	draw_polygon(pts, cols)
