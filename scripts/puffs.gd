class_name Puffs
extends Node2D
## A burst of dust puffs (from Unity's Puffs.Burst): a handful kicked out round a spot, rising a little, swelling and
## fading. Sorted among things standing, just in front of the spot.

const TEX := preload("res://assets/Art/Effects/Dust.png")

var puffs := []  # [position, velocity, age, life, size]


static func burst(w: World, at: Vector2, size := 1.0, count := 10) -> void:
	var p := Puffs.new()
	p.position = at + Vector2(0, 2)
	for i in count:
		var a := randf() * TAU
		var v := Vector2(cos(a), sin(a) * 0.5) * randf_range(0.3, 0.9) * w.px * size
		p.puffs.append([Vector2.ZERO, v + Vector2(0, -0.2 * w.px), 0.0, randf_range(0.5, 0.9), randf_range(0.25, 0.45) * w.px * size])
	w.things.add_child(p)


func _process(delta: float) -> void:
	var __t := Time.get_ticks_usec()
	_process_timed(delta)
	Perf.add(&"puffs.process", __t)


func _process_timed(delta: float) -> void:
	for p in puffs:
		p[2] += delta
		p[1] *= 1.0 - delta * 3.0
		p[0] += p[1] * delta
	puffs = puffs.filter(func(p): return p[2] < p[3])
	if puffs.is_empty():
		queue_free()
	queue_redraw()


func _draw() -> void:
	for p in puffs:
		var t: float = p[2] / p[3]
		var size: float = p[4] * lerpf(0.6, 1.4, t)
		draw_texture_rect(TEX, Rect2(p[0] - Vector2(size, size) * 0.5, Vector2(size, size)), false, Color(0.85, 0.78, 0.68, 0.7 * (1.0 - t)))
