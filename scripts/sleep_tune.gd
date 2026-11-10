class_name SleepTune
extends PanelContainer
## Tuning how sleepers lie, by hand: standing by a bed with a villager asleep in it, a little panel shows with X, Y
## (px) and R (degrees) for that villager's look and pose; changing a number moves them at once, and it's kept
## (data/sleep_tune.json: "look:pose" -> [x, y, r]) for every villager of that look. X and R are as seen with the
## sleeper's feet to the left: on a bed turned the other way they're mirrored with the art.

const PATH := "res://data/sleep_tune.json"
const NEAR := 1.8                ## units from Miko to the sleeper

static var _data := {}
static var _loaded := false

var world: World
var miko: Miko
var who: Villager
var _title: Label
var _boxes: Array[SpinBox] = []
var _setting := false


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH)) if FileAccess.file_exists(PATH) else null
	_data = d if d is Dictionary else {}


## The hand adjustment for [param look]'s [param pose] ("sleepDown", "sleepUp"): [x, y (px), r (degrees)].
static func of(look: int, pose: String) -> Array:
	_load()
	var v: Variant = _data.get("%d:%s" % [look, pose])
	return v if v is Array and (v as Array).size() == 3 else [0.0, 0.0, 0.0]


static func put(look: int, pose: String, v: Array) -> void:
	_load()
	_data["%d:%s" % [look, pose]] = v
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_data, "\t") + "\n")


func setup(w: World, m: Miko) -> void:
	world = w
	miko = m
	add_theme_stylebox_override("panel", HudStyle.piece("panelStrong"))
	var col := VBoxContainer.new()
	add_child(col)
	_title = HudStyle.label("", 12, "bold", HudStyle.color("accentLight"))
	col.add_child(_title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)
	for n in ["X", "Y", "R"]:
		row.add_child(HudStyle.label(n, 12, "bold"))
		var b := SpinBox.new()
		b.min_value = -200.0
		b.max_value = 200.0
		b.step = 1.0
		b.allow_greater = true
		b.allow_lesser = true
		b.custom_minimum_size.x = 84
		b.value_changed.connect(func(_v): _changed())
		# Only numbers go in (walking with WASD while its box is picked typed letters into it); Enter lets go of it.
		var edit := b.get_line_edit()
		edit.text_changed.connect(func(t: String) -> void:
			var clean := ""
			for ch in t:
				if ch in "0123456789-.":
					clean += ch
			if clean != t:
				edit.text = clean
				edit.caret_column = clean.length())
		edit.text_submitted.connect(func(_t): edit.release_focus())
		row.add_child(b)
		_boxes.append(b)
	col.add_child(HudStyle.label("Saved for every villager of this look", 10, "bold", HudStyle.color("faint")))
	visible = false


func _process(_delta: float) -> void:
	var best: Villager = null
	var best_d := NEAR * world.px
	for v in Villager.all:
		if is_instance_valid(v) and v.in_bed and v.visible and v.position.distance_to(miko.position) < best_d:
			best_d = v.position.distance_to(miko.position)
			best = v
	if best != who:
		who = best
		if who != null:
			var t := of(int(who.person.look), who.sleep_pose())
			_setting = true
			for i in 3:
				_boxes[i].value = float(t[i])
			_setting = false
			_title.text = "%s asleep  ·  look %d, %s" % [who.person.name, int(who.person.look), "back view" if who.facing_up else "front view"]
	visible = who != null
	if not visible:
		return
	reset_size()
	var at := get_viewport().get_canvas_transform() * (who.position + Vector2(0, -1.9 * world.px))
	var vp := get_viewport_rect().size
	position = Vector2(clampf(at.x - size.x / 2.0, 8.0, vp.x - size.x - 8.0), clampf(at.y - size.y, 8.0, vp.y - size.y - 8.0)).round()


func _changed() -> void:
	if _setting or who == null or not is_instance_valid(who):
		return
	put(int(who.person.look), who.sleep_pose(), [_boxes[0].value, _boxes[1].value, _boxes[2].value])
	# Everyone asleep of that look moves at once.
	for v in Villager.all:
		if is_instance_valid(v) and v.in_bed:
			v.lie_in_bed()
