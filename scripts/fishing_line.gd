class_name FishingLine
extends Node2D
## A fishing line and its float, drawn as they are now: the line from the rod's tip, slack and sagging, down to the
## float; the float (red over white) in the air or sitting in the water with rings spreading round it, tugged under
## when there's a bite. Fishing sets where each is and asks for a redraw.

var tip := Vector2.ZERO          ## the rod's tip (px, the world's)
var float_at := Vector2.ZERO     ## the float
var water_at := Vector2.ZERO     ## where it sits in the water (the rings' middle)
var unit := 128.0                ## px to a tile
var landed := false
var bite := false
var keep := Callable()           ## asked each frame: false, and it's put away (whoever's line it is has stopped)

const LINE := Color(0.93, 0.93, 0.88, 0.85)
const RED := Color(0.86, 0.2, 0.2)
const WHITE := Color(0.97, 0.97, 0.95)
const DARK := Color(0.2, 0.12, 0.1)


func _process(_delta: float) -> void:
	if visible and keep.is_valid() and not keep.call():
		visible = false


func _draw() -> void:
	# (it stands where its float sits, to be sorted there; what it draws is given in the world's own px)
	draw_set_transform(-position)
	# The line: a curve hanging between the two (tauter in the air and on a bite).
	var sag := (0.1 if bite or not landed else 0.32) * unit
	var mid := (tip + float_at) / 2.0 + Vector2(0, sag)
	var pts := PackedVector2Array()
	for i in 13:
		var t := i / 12.0
		pts.append(tip.lerp(mid, t).lerp(mid.lerp(float_at, t), t))
	draw_polyline(pts, LINE, maxf(1.0, unit * 0.012), true)
	var r := unit * 0.055
	if landed:
		# Rings on the water, spreading and fading (quicker on a bite).
		var now := Time.get_ticks_msec() / 1000.0
		for n in 2:
			var age := fmod(now * (1.6 if bite else 0.7) + n * 0.5, 1.0)
			draw_set_transform(water_at - position, 0.0, Vector2(1.0, 0.5))
			draw_arc(Vector2.ZERO, r * (1.5 + age * 4.0), 0.0, TAU, 28, Color(1, 1, 1, 0.5 * (1.0 - age)), maxf(1.0, unit * 0.012), true)
		draw_set_transform(-position)
	# The float: white below, red on top, a dark stalk the line's tied to.
	draw_line(float_at + Vector2(0, -r * 2.2), float_at + Vector2(0, -r), DARK, maxf(1.0, unit * 0.014))
	draw_circle(float_at, r * 1.15, DARK)
	draw_circle(float_at, r, WHITE)
	var top := PackedVector2Array()
	for i in 13:
		var a := PI + i * PI / 12.0
		top.append(float_at + Vector2(cos(a), sin(a)) * r)
	draw_colored_polygon(top, RED)
