class_name Slash
extends Node2D
## A slash: a bright crescent standing upright in front of whoever attacks, swept overhead from just behind straight up,
## over and down to the ground before them (an overhead blow), thick in the middle and tapering to points, its tail
## fading behind it, then gone (drawn by hand, added light). It faces the side they strike towards, narrowing when they
## strike up or down the screen (an upright arc seen more edge-on). Sorted just in front of the attacker's feet.

const TIME := 0.2             ## seconds to sweep
const LINGER := 0.12          ## seconds to fade once swept
const SEGMENTS := 24

var color := Color(1.0, 0.95, 0.75)
var radius := 90.0            ## px
const FROM := -0.35            ## radians from straight up where it starts (a little behind)
const TO := 2.05               ## and where it ends (down in front, near the ground)
var lift := 60.0              ## px above the feet: the arc's middle (the shoulder)
var _side := 1.0
var _wide := 1.0              ## how much of its width shows (less striking up or down the screen)
var _ahead := Vector2.ZERO    ## px: the arc's middle, a little towards the target
var _age := 0.0


## A slash from [param at] (feet, px) towards [param toward] (a direction on screen), [param size] units across.
static func play(w: World, at: Vector2, toward: Vector2, tint: Color, size := 1.0) -> Slash:
	var s := Slash.new()
	s.color = tint
	s.radius = 0.8 * size * w.px
	s.lift = 0.5 * w.px
	s._side = 1.0 if toward.x >= 0.0 else -1.0
	var ground := Vector2(toward.x, toward.y * 2.0).normalized()
	s._wide = maxf(0.4, absf(ground.x))
	s._ahead = Vector2(ground.x, ground.y * 0.5) * 0.25 * w.px
	s.position = at + Vector2(0, 2.0)   # just in front of the attacker in the y-sort
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	s.material = add
	w.things.add_child(s)
	return s


func _process(delta: float) -> void:
	_age += delta
	if _age > TIME + LINGER:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var head := clampf(_age / TIME, 0.0, 1.0)
	head = 1.0 - pow(1.0 - head, 3.0)                    # fast, then easing as it finishes
	var tail := clampf(head - 0.65, 0.0, 1.0)
	var fade := 1.0 - clampf((_age - TIME) / LINGER, 0.0, 1.0)
	if head <= tail:
		return
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	var cols_o := PackedColorArray()
	var cols_i := PackedColorArray()
	for i in SEGMENTS + 1:
		var u := lerpf(tail, head, float(i) / SEGMENTS)
		var a := lerpf(FROM, TO, u)
		var along := (u - tail) / maxf(0.001, head - tail)    # 0 at the tail, 1 at the leading point
		var thick := sin(along * PI) * 0.42 * radius
		var dir := Vector2(_side * sin(a) * _wide, -cos(a))     # upright: up is -y, forward is the side struck
		var mid := _ahead + Vector2(0, -lift)
		outer.append(mid + dir * radius)
		inner.append(mid + dir * (radius - thick))
		var c := Color(color, color.a * fade * smoothstep(0.0, 0.5, along))
		cols_o.append(c)
		cols_i.append(Color(c, c.a * 0.5))
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	for i in SEGMENTS + 1:
		pts.append(outer[i])
		cols.append(cols_o[i])
	for i in range(SEGMENTS, -1, -1):
		pts.append(inner[i])
		cols.append(cols_i[i])
	if Geometry2D.triangulate_polygon(pts).size() > 0:
		# A soft glow a little wider than the blade, then the blade itself.
		var glow := PackedColorArray()
		for c in cols:
			glow.append(Color(c, c.a * 0.35))
		var mid := _ahead + Vector2(0, -lift)
		draw_set_transform(mid * -0.06, 0.0, Vector2(1.06, 1.06))
		draw_polygon(pts, glow)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_polygon(pts, cols)
	# A bright edge along its leading curve.
	var edge := PackedColorArray()
	for c in cols_o:
		edge.append(Color(c.lightened(0.5), minf(1.0, c.a * 1.3)))
	draw_polyline_colors(outer, edge, maxf(2.0, radius * 0.035), true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
