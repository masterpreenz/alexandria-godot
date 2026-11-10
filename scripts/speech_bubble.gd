class_name SpeechBubble
extends Control
## A comic bubble over someone's head with a few words in it, drawn by hand (white, an ink outline): SAY a rounded
## bubble with a tail down to the speaker, THINK a cloud trailing two little puffs (thinking out loud: hungry, tired),
## SHOUT a spiky burst that shakes a little (urgent: hurt, a fight, a raid, "HELP!"). Its bottom middle sits where
## it's placed (the tail's or puffs' tip over the head). Bright whatever the hour.

enum Kind { SAY, THINK, SHOUT }

const INK := Color(0.16, 0.12, 0.1)
const PAPER := Color(1.0, 0.98, 0.94)

var kind := Kind.SAY
var text := ""
var font_size := 15
var _box := Vector2.ZERO          ## the body's size (the words and their margin)
var _born := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_as_relative = false
	z_index = 3999
	World.keep_lit(self)


## Shows [param words] as [param how] (Kind).
func say(words: String, how: int) -> void:
	text = words
	kind = how as Kind
	var f := HudStyle.font("bold")
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x if f else 80.0
	var pad := Vector2(18, 10) if kind == Kind.SAY else (Vector2(26, 16) if kind == Kind.THINK else Vector2(30, 20))
	_box = Vector2(w, font_size * 1.3) + pad * 2.0
	size = _box + Vector2(0, 18)
	_born = Time.get_ticks_msec() / 1000.0
	queue_redraw()


## Where its bottom middle (the tail's tip) goes, in its parent's space.
func place(at: Vector2) -> void:
	position = (at - Vector2(size.x / 2.0, size.y)).round()


func _process(_delta: float) -> void:
	if visible and kind == Kind.SHOUT:
		queue_redraw()   # it shakes


func _draw() -> void:
	var c := Vector2(size.x / 2.0, _box.y / 2.0)
	var shake := Vector2.ZERO
	if kind == Kind.SHOUT:
		var t := Time.get_ticks_msec() / 1000.0 - _born
		shake = Vector2(sin(t * 47.0), cos(t * 39.0)) * 1.5 * clampf(1.0 - t / 1.2, 0.3, 1.0)
	match kind:
		Kind.SAY:
			_say_shape(c)
		Kind.THINK:
			_think_shape(c)
		Kind.SHOUT:
			_shout_shape(c + shake)
	var f := HudStyle.font("bold")
	if f != null:
		var at := c + shake + Vector2(-_box.x / 2.0, font_size * 0.36)
		draw_string(f, at, text, HORIZONTAL_ALIGNMENT_CENTER, _box.x, font_size, INK if kind != Kind.SHOUT else Color(0.75, 0.12, 0.08))


# A rounded bubble with a tail down to the speaker.
func _say_shape(c: Vector2) -> void:
	var r := Rect2(c - _box / 2.0, _box)
	var sb := StyleBoxFlat.new()
	sb.bg_color = PAPER
	sb.border_color = INK
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(int(_box.y / 2.0))
	sb.anti_aliasing = true
	var tail := PackedVector2Array([Vector2(c.x - 7, r.end.y - 2), Vector2(c.x + 7, r.end.y - 2), Vector2(c.x - 2, size.y)])
	draw_colored_polygon(tail, PAPER)
	draw_polyline(PackedVector2Array([tail[0], tail[2], tail[1]]), INK, 2.0, true)
	draw_style_box(sb, r)
	# Paper over the outline where the tail joins.
	draw_line(tail[0] + Vector2(2, -1), tail[1] + Vector2(-2, -1), PAPER, 3.0)


# A cloud: puffs round an oval, and two little puffs trailing down to the thinker.
func _think_shape(c: Vector2) -> void:
	var rx := _box.x / 2.0 - 6.0
	var ry := _box.y / 2.0 - 5.0
	var n := maxi(8, int(_box.x / 16.0))
	var puffs := []
	for i in n:
		var a := i * TAU / n
		puffs.append([c + Vector2(cos(a) * rx, sin(a) * ry), 9.0 + 3.0 * float(i % 2)])
	for p in puffs:
		draw_circle(p[0], p[1] + 2.0, INK)
	draw_circle(c, 1.0, PAPER)
	draw_set_transform(c, 0.0, Vector2(rx, ry) / maxf(rx, ry))
	draw_circle(Vector2.ZERO, maxf(rx, ry), PAPER)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for p in puffs:
		draw_circle(p[0], p[1], PAPER)
	# The trail of little puffs.
	for t in [[Vector2(-4, _box.y / 2.0 + 6.0), 4.5], [Vector2(-8, _box.y / 2.0 + 14.0), 3.0]]:
		draw_circle(c + t[0], t[1] + 2.0, INK)
		draw_circle(c + t[0], t[1], PAPER)


# A spiky burst round the words.
func _shout_shape(c: Vector2) -> void:
	var rx := _box.x / 2.0
	var ry := _box.y / 2.0
	var n := maxi(12, int(_box.x / 9.0)) * 2
	var pts := PackedVector2Array()
	for i in n:
		var a := i * TAU / n
		var k := 1.08 if i % 2 == 0 else 0.82
		pts.append(c + Vector2(cos(a) * rx * k, sin(a) * ry * (k * 1.08 if i % 2 == 0 else k)))
	# A spike down at the shouter.
	var down := int(n / 4.0)
	pts[down] = Vector2(c.x - 3, size.y)
	draw_colored_polygon(pts, PAPER)
	pts.append(pts[0])
	draw_polyline(pts, INK, 2.5, true)
