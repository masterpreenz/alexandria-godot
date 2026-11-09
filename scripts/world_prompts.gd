class_name WorldPrompts
extends Node
## The "press a key" prompts (E Open chest, E Use workbench, Press E to light...) shown in the world beside what they're
## about, not fixed at the bottom of the screen. Each prompt label is registered once; [method at] says where it
## belongs (a point in the world, px). One without a point shows beside Miko's head.

static var _labels: Array = []
static var _at := {}            ## label -> world point
static var _miko: Node2D


static func register(label: Label) -> void:
	label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	label.grow_horizontal = Control.GROW_DIRECTION_END
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
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
	var xf := get_viewport().get_canvas_transform()
	var px := 128.0
	var shown := 0
	for l in _labels:
		if not is_instance_valid(l) or not l.visible or l.text == "":
			continue
		var p: Vector2 = _at.get(l, _miko.position + Vector2(0, -1.2 * px) if _miko != null else Vector2.ZERO)
		var s := xf * p
		l.reset_size()
		# To its right, a little up; stacked when more than one show at once.
		l.position = (s + Vector2(0.45 * px * xf.get_scale().x, -l.size.y / 2.0 + shown * l.size.y)).round()
		shown += 1
