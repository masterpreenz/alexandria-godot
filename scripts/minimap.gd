class_name Minimap
extends Control
## The minimap, top right over the time card (the upper half of Unity's WorldHud): the land round Miko seen from above
## by a second camera (characters and creatures left off and marked as squares instead), with the fog over what she
## hasn't seen, the town banner, the teleport crystals and the lost bag (on the map's edge, pointing, when they're off
## it), and Miko in the middle. + and − in its corner step the zoom. M opens the world map.

const MAP := 228.0
const RES := 256
const ZOOM_STEPS := [6.0, 10.0, 16.0, 24.0]   ## units from the middle to the edge

var world: World
var miko: Miko
var time_card: TimeCard
var step := 1
var _vp: SubViewport
var _cam: Camera2D
var _crystals: Crystals
var _fps: Label
var _fps_smoothed := 60.0
var _fps_shown_at := 0.0


func setup(w: World, who: Miko, card: TimeCard) -> void:
	world = w
	miko = who
	time_card = card
	_crystals = get_tree().current_scene.get_node_or_null("Crystals")
	size = Vector2(MAP + 12, MAP + 12) * HudStyle.SCALE
	mouse_filter = Control.MOUSE_FILTER_PASS
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_vp = SubViewport.new()
	_vp.size = Vector2i(RES, RES)
	_vp.world_2d = get_viewport().world_2d
	_vp.canvas_cull_mask = 0xFFFFF & ~MapMarks.HIDDEN_LAYER
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	_cam = Camera2D.new()
	_cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_cam.process_callback = Camera2D.CAMERA2D_PROCESS_IDLE
	_vp.add_child(_cam)
	_cam.make_current()
	_zoom()
	if Perf.active != null:
		Perf.active.watch_viewport(_vp, "minimap")
	# Zoom in and out, in the map's bottom right corner.
	for t in [["plus", -1], ["minus", 1]]:
		var b := ZoomButton.new()
		b.plus = t[1] < 0
		b.custom_minimum_size = Vector2(22, 22) * HudStyle.SCALE
		b.size = b.custom_minimum_size
		b.tooltip_text = "Zoom in" if t[1] < 0 else "Zoom out"
		b.pressed.connect(_step.bind(t[1]))
		add_child(b)
		b.position = Vector2(MAP + 6 - 5 - 22, MAP + 6 - 5 - 22 - (25 if t[1] < 0 else 0)) * HudStyle.SCALE
	# The time card sits in the map's top centre.
	card.holder = self
	card.get_parent().remove_child(card)
	add_child(card)
	# Frames per second, small, just under the card.
	_fps = HudStyle.label("", 10, "pixel", HudStyle.color("faint"))
	_fps.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_fps)


func _step(by: int) -> void:
	step = clampi(step + by, 0, ZOOM_STEPS.size() - 1)
	_zoom()


func _zoom() -> void:
	_cam.zoom = Vector2.ONE * (RES / 2.0) / (float(ZOOM_STEPS[step]) * world.px)


func _process(delta: float) -> void:
	var __t := Time.get_ticks_usec()
	_process_timed(delta)
	Perf.add(&"minimap.process", __t)


func _process_timed(_delta: float) -> void:
	position = Vector2(get_viewport_rect().size.x - size.x - 16.0, 16.0)
	MapMarks.hide_characters(world)
	_meter(_delta)
	# Whole map pixels only, so the pixel art doesn't shimmer as it slides; the rest is made up when it's drawn.
	var texel := 2.0 * float(ZOOM_STEPS[step]) * world.px / RES
	var at := miko.drawn_position()
	_cam.position = (at / texel).round() * texel
	queue_redraw()


func _map_rect() -> Rect2:
	return Rect2(Vector2(6, 6) * HudStyle.SCALE, Vector2(MAP, MAP) * HudStyle.SCALE)


# A world point (px) on the map, or on its edge when off it: [where, on the map].
func _to_map(p: Vector2) -> Array:
	var r := _map_rect()
	var half := float(ZOOM_STEPS[step]) * world.px
	var d := (p - miko.drawn_position()) / half
	var on := absf(d.x) <= 1.0 and absf(d.y) <= 1.0
	if not on:
		d /= maxf(absf(d.x), absf(d.y))
		d *= 0.93
	return [r.get_center() + d * r.size / 2.0, on]


func _draw() -> void:
	var k := HudStyle.SCALE
	draw_style_box(HudStyle.piece("panel"), Rect2(Vector2.ZERO, size))
	var r := _map_rect()
	# The picture, nudged by the fraction of a map pixel the camera didn't move.
	var half := float(ZOOM_STEPS[step]) * world.px
	var shift := (miko.drawn_position() - _cam.position) / (2.0 * half) * RES
	var inset := 1.0
	draw_texture_rect_region(_vp.get_texture(), r, Rect2(Vector2(inset, inset) + shift, Vector2(RES - 2 * inset, RES - 2 * inset)))
	# The fog over what she hasn't seen.
	var ex := Exploration.active
	if ex != null:
		var view := Rect2(miko.drawn_position() - Vector2(half, half), Vector2(half, half) * 2.0)
		draw_texture_rect_region(ex.fog(), r, ex.fog_region(view))
	draw_style_box(HudStyle.piece("well", Color(1, 1, 1, 0.0)), r)
	# Creatures and villagers, then the banner, crystals and the lost bag, then her.
	for m in MapMarks.marks(world):
		var at: Array = _to_map(m[0])
		if at[1]:
			_square(at[0], m[2] * k, m[1])
	if world.village.founded():
		var b: Array = _to_map(world.village.centre())
		_square(b[0], 9 * k, MapMarks.BANNER, 12 * k)
	if _crystals != null:
		for c in _crystals.teleports:
			var at: Array = _to_map(c.pos)
			_diamond(at[0], 6 * k, MapMarks.CRYSTAL)
	if Fainting.LostBag.active != null and is_instance_valid(Fainting.LostBag.active):
		var at: Array = _to_map(Fainting.LostBag.active.position)
		_square(at[0], 11 * k, MapMarks.BAG)
	_square(r.get_center(), 10 * k, HudStyle.color("accentLight"))


func _square(at: Vector2, w: float, c: Color, h := -1.0) -> void:
	var s := Vector2(w, w if h < 0 else h)
	var box := Rect2(at - s / 2.0, s)
	draw_rect(box.grow(1.5), Color(0.1, 0.07, 0.06, 0.9))
	draw_rect(box, c)


func _diamond(at: Vector2, r: float, c: Color) -> void:
	var pts := PackedVector2Array([at + Vector2(0, -r), at + Vector2(r, 0), at + Vector2(0, r), at + Vector2(-r, 0)])
	var outer := PackedVector2Array()
	for p in pts:
		outer.append(at + (p - at) * 1.3)
	draw_colored_polygon(outer, Color(0.1, 0.07, 0.06, 0.9))
	draw_colored_polygon(pts, c)


# Smoothed, and redrawn twice a second so it can be read: green at 55 and over, amber at 30, coral under.
func _meter(delta: float) -> void:
	_fps.visible = Settings.show_fps
	if not _fps.visible:
		return
	if delta > 0.0:
		_fps_smoothed = lerpf(_fps_smoothed, 1.0 / delta, 0.1)
	var t := Time.get_ticks_msec() / 1000.0
	if t - _fps_shown_at < 0.5:
		return
	_fps_shown_at = t
	var fps := roundi(_fps_smoothed)
	_fps.text = "%d FPS" % fps
	_fps.add_theme_color_override("font_color", HudStyle.color("green") if fps >= 55 else (HudStyle.color("accent") if fps >= 30 else HudStyle.color("coral")))
	_fps.reset_size()
	_fps.position = Vector2(size.x - _fps.size.x - 4.0, size.y + 2.0)


## A zoom button: a dark key with a bright plus or minus drawn on it (the icons' own art is too dark to read there).
class ZoomButton extends Button:
	var plus := true

	func _init() -> void:
		flat = true
		focus_mode = Control.FOCUS_NONE

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var back := Color(0.2, 0.16, 0.13, 0.95) if is_hovered() else Color(0.11, 0.08, 0.07, 0.88)
		draw_style_box(HudStyle.piece("key", back), r)
		var c := size / 2.0
		var arm := size.x * 0.24
		var w := maxf(2.0, size.x * 0.11)
		var col := HudStyle.color("accentLight") if is_hovered() else HudStyle.color("text")
		draw_line(c - Vector2(arm, 0), c + Vector2(arm, 0), col, w)
		if plus:
			draw_line(c - Vector2(0, arm), c + Vector2(0, arm), col, w)
