class_name WorldPrompts
extends Node
## The "press a key" prompts (E Open chest, E Use workbench, Press E to light...) shown in the world beside what they're
## about, not fixed at the bottom of the screen: the text in a dark pill, with an arrow from the pill back to the thing
## ( ◄──── [ E  Town banner ] ). Each prompt label is registered once; [method at] says where it belongs (a point in
## the world, px). One without a point shows beside Miko's head.

const GAP := 54.0         ## screen px from the thing to the pill (the arrow's length)
## The keys a prompt asks for, ringed so they stand out: a capital letter on its own (E, R, Z...), or a named key.
const KEY_WORDS := ["Esc", "Space", "Shift", "Tab", "Enter"]
static var _key_re: RegEx

static var _labels: Array = []
static var _at := {}            ## label -> world point
static var _miko: Node2D

var _arrows: Arrows
var _rings: KeyRings


static func register(label: Label) -> void:
	label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	label.grow_horizontal = Control.GROW_DIRECTION_END
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	var pill := HudStyle.piece("pillPlain", Color(1, 1, 1, 0.94))
	pill.content_margin_left = 12
	pill.content_margin_right = 14
	pill.content_margin_top = 4
	pill.content_margin_bottom = 4
	label.add_theme_stylebox_override("normal", pill)
	label.add_theme_font_size_override("font_size", roundi(13 * HudStyle.SCALE))
	_labels.append(label)


## Puts [param label] beside [param point] (world px) while it shows.
static func at(label: Label, point: Vector2) -> void:
	_at[label] = point


func setup(miko: Node2D) -> void:
	_miko = miko
	_labels.clear()
	_at.clear()
	process_priority = 100000


func _process(_delta: float) -> void:
	if _arrows == null:
		var hud := get_tree().current_scene.get_node_or_null("Hud")
		if hud == null:
			return
		_arrows = Arrows.new()
		_arrows.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hud.add_child(_arrows)
		hud.move_child(_arrows, 0)
		_rings = KeyRings.new()
		_rings.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_rings.z_index = 1                 # over the prompts' pills and text
		hud.add_child(_rings)
	var xf := get_viewport().get_canvas_transform()
	var px := 128.0
	var lines := []
	var keys := []
	var placed: Array[Rect2] = []
	for l in _labels:
		if not is_instance_valid(l) or not l.visible or l.text == "":
			continue
		var p: Vector2 = _at.get(l, _miko.position + Vector2(0, -1.2 * px) if _miko != null else Vector2.ZERO)
		var s := xf * p
		l.reset_size()
		# To the thing's right, its arrow pointing back at it; one that would cover another moves down below it.
		var box := Rect2(Vector2(s.x + GAP * HudStyle.SCALE, s.y - l.size.y / 2.0), l.size)
		var moved := true
		while moved:
			moved = false
			for other in placed:
				if box.grow(2.0).intersects(other):
					box.position.y = other.end.y + 4.0
					moved = true
		placed.append(box)
		l.position = box.position.round()
		lines.append([s + Vector2(6, 0), Vector2(box.position.x, box.position.y + l.size.y / 2.0)])
		keys.append_array(_keys_in(l))
	_arrows.lines = lines
	_arrows.queue_redraw()
	_rings.keys = keys
	_rings.queue_redraw()


# The keys named in [param l]'s text, each as [where its baseline starts on screen, the key, font, size], to be drawn
# again over the label's own letters, highlighted.
static func _keys_in(l: Label) -> Array:
	if _key_re == null:
		_key_re = RegEx.create_from_string("(?<![A-Za-z0-9_'])([A-Z]|F[0-9]{1,2}|" + "|".join(KEY_WORDS) + ")(?![A-Za-z0-9_'])")
	var out := []
	var font := l.get_theme_font("font")
	var size := l.get_theme_font_size("font_size")
	var sb := l.get_theme_stylebox("normal")
	var origin := l.position + Vector2(sb.content_margin_left if sb != null else 0.0, sb.content_margin_top if sb != null else 0.0)
	for m in _key_re.search_all(l.text):
		var x := font.get_string_size(l.text.substr(0, m.get_start()), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		out.append([origin + Vector2(x, font.get_ascent(size)), m.get_string(), font, size])
	return out


## The arrows from each prompt's pill back to its thing (under the prompts).
class Arrows extends Control:
	var lines: Array = []

	func _draw() -> void:
		var c := Color(HudStyle.color("text"), 0.85)
		var dark := Color(0, 0, 0, 0.45)
		for ln in lines:
			var tip: Vector2 = ln[0]
			var end: Vector2 = ln[1]
			var dir := (end - tip).normalized()
			var side := Vector2(-dir.y, dir.x)
			var head := PackedVector2Array([tip, tip + dir * 9 + side * 5, tip + dir * 9 - side * 5])
			draw_line(tip + dir * 6, end, dark, 4.0, true)
			draw_line(tip + dir * 6, end, c, 2.0, true)
			draw_colored_polygon(head, c)


## The keys a prompt asks for, highlighted in its own lettering: the key drawn again over the label's, in the accent
## colour with a dark outline round it.
class KeyRings extends Control:
	var keys: Array = []

	func _draw() -> void:
		var accent := HudStyle.color("accentLight")
		var edge := maxi(3, roundi(4.0 * HudStyle.SCALE))
		for k in keys:
			draw_string_outline(k[2], k[0], k[1], HORIZONTAL_ALIGNMENT_LEFT, -1, k[3], edge, Color(0.07, 0.05, 0.04, 0.95))
			draw_string(k[2], k[0], k[1], HORIZONTAL_ALIGNMENT_LEFT, -1, k[3], accent)
