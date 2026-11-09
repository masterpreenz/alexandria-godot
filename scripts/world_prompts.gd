class_name WorldPrompts
extends Node
## The "press a key" prompts (E Open chest, E Use workbench, Press E to light...) shown in the world beside what they're
## about, not fixed at the bottom of the screen: the text in a dark pill, with an arrow from the pill back to the thing
## ( ◄──── [ E  Town banner ] ). Each prompt label is registered once; [method at] says where it belongs (a point in
## the world, px). One without a point shows beside Miko's head.

const GAP := 54.0         ## screen px from the thing to the pill (the arrow's length)

static var _labels: Array = []
static var _at := {}            ## label -> world point
static var _miko: Node2D

var _arrows: Arrows


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
	var xf := get_viewport().get_canvas_transform()
	var px := 128.0
	var lines := []
	var stacked := 0.0
	for l in _labels:
		if not is_instance_valid(l) or not l.visible or l.text == "":
			continue
		var p: Vector2 = _at.get(l, _miko.position + Vector2(0, -1.2 * px) if _miko != null else Vector2.ZERO)
		var s := xf * p
		l.reset_size()
		# To the thing's right, its arrow pointing back at it; more than one stack downwards.
		var box := Vector2(s.x + GAP * HudStyle.SCALE, s.y - l.size.y / 2.0 + stacked)
		l.position = box.round()
		lines.append([s + Vector2(6, 0), Vector2(box.x, box.y + l.size.y / 2.0)])
		stacked += l.size.y + 4.0
	_arrows.lines = lines
	_arrows.queue_redraw()


## The arrows from each prompt's pill back to its thing.
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
