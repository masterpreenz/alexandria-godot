class_name WorldMap
extends Control
## The world map (from Unity's WorldMap; M, and M or Esc closes it): the whole world at once, drawn by its own camera
## (characters and creatures left off and marked as squares), with the fog over land Miko hasn't seen, the 8 x 8 grid of
## sections (L shows or hides it), the village's edge and banner, the teleport crystals (named; click one to travel
## while standing at a crystal), the lost bag, and Miko. Zooms (the wheel round the cursor, + and −) up to four times
## and drags to look around while zoomed. F11 shows the whole map without fog (not saved).

const MARGIN := 70.0
const RES := 2800
const ZOOM_STEPS := [1.0, 1.5, 2.0, 3.0, 4.0]

var world: World
var miko: Miko
var zoom := 1.0
var centre := Vector2.ZERO        ## the world point (px) in the middle of the frame
var show_sections := true
var _vp: SubViewport
var _cam: Camera2D
var _area := Rect2()              ## the whole world, px
var _frame := Rect2()             ## the map's frame on screen
var _drawn_stamp := ""
var _drawn_at := -INF
var _pressed := false
var _dragging := false
var _press_at := Vector2.ZERO
var _crystals: Crystals
var _crystal_spots: Array = []    ## [[screen point, crystal]] last drawn


func setup(w: World, who: Miko) -> void:
	world = w
	miko = who
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_crystals = get_tree().current_scene.get_node_or_null("Crystals")
	_area = Exploration.active.px_rect() if Exploration.active != null else Rect2(-20000, -10000, 40000, 20000)
	var aspect := _area.size.x / maxf(1.0, _area.size.y)
	_vp = SubViewport.new()
	_vp.size = Vector2i(RES, roundi(RES / aspect)) if aspect >= 1.0 else Vector2i(roundi(RES * aspect), RES)
	_vp.world_2d = get_viewport().world_2d
	_vp.canvas_cull_mask = 0xFFFFF & ~MapMarks.HIDDEN_LAYER
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	_cam = Camera2D.new()
	_cam.position = _area.get_center()
	_cam.zoom = Vector2.ONE * (_vp.size.x / _area.size.x)
	_vp.add_child(_cam)
	_cam.make_current()
	visible = false


func open() -> void:
	visible = true
	move_to_front()
	centre = miko.position
	_pressed = false
	_dragging = false
	_redraw_picture(true)


func close() -> void:
	visible = false


# The land changes (floors laid, props placed, trees felled): the kept picture is drawn again, or every 30 seconds.
func _stamp() -> String:
	var depleted := 0
	for g in Gatherable.all:
		if is_instance_valid(g) and g.left <= 0:
			depleted += 1
	return "%d|%d|%d|%d" % [world.floors.version, world.props.version, Gatherable.all.size(), depleted]


func _redraw_picture(force := false) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var st := _stamp()
	if force or st != _drawn_stamp or now > _drawn_at + 30.0:
		_drawn_stamp = st
		_drawn_at = now
		MapMarks._next_hide = 0.0
		MapMarks.hide_characters(world)
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == KEY_F11:
		Exploration.show_all = not Exploration.show_all
		if Exploration.active != null:
			Exploration.active.refog()
		FloatingText.spawn(world, "Whole map shown" if Exploration.show_all else "Fog back", miko.position + Vector2(0, -1.9 * world.px), Color(0.6, 0.9, 1.0))
		get_viewport().set_input_as_handled()
		return
	if visible:
		match event.keycode:
			KEY_M, KEY_ESCAPE: close()
			KEY_EQUAL, KEY_KP_ADD: _step(1, null)
			KEY_MINUS, KEY_KP_SUBTRACT: _step(-1, null)
			KEY_L: show_sections = not show_sections
			_: return
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_M and not miko.locked and world.get_node_or_null("Caster") != null and (world.get_node("Caster") as SpellCaster).aiming == "":
		open()
		get_viewport().set_input_as_handled()


# ---- The view: the whole world at 1x, a window of it zoomed in, never past its edges ----

func _view() -> Rect2:
	var s := _area.size / zoom
	var c := Vector2(clampf(centre.x, _area.position.x + s.x / 2.0, _area.end.x - s.x / 2.0),
		clampf(centre.y, _area.position.y + s.y / 2.0, _area.end.y - s.y / 2.0))
	return Rect2(c - s / 2.0, s)


func _to_screen(p: Vector2) -> Vector2:
	var v := _view()
	return _frame.position + (p - v.position) / v.size * _frame.size


func _to_world(s: Vector2) -> Vector2:
	var v := _view()
	return v.position + (s - _frame.position) / _frame.size * v.size


# One zoom step in (+1) or out (-1), keeping the world point under [param about] (a screen point) where it is.
func _step(direction: int, about: Variant) -> void:
	var i := 0
	for k in ZOOM_STEPS.size():
		if absf(ZOOM_STEPS[k] - zoom) < absf(ZOOM_STEPS[i] - zoom):
			i = k
	var next: float = ZOOM_STEPS[clampi(i + direction, 0, ZOOM_STEPS.size() - 1)]
	if is_equal_approx(next, zoom):
		return
	centre = _view().get_center()
	if about != null:
		var under := _to_world(about)
		var u: Vector2 = (about - _frame.position) / _frame.size - Vector2(0.5, 0.5)
		zoom = next
		centre = under - u * _area.size / zoom
	else:
		zoom = next


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var inside := _frame.has_point(event.position)
		if event.pressed and inside and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_step(1, event.position)
		elif event.pressed and inside and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_step(-1, event.position)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_pressed = inside
				_dragging = false
				_press_at = event.position
				_click_buttons(event.position)
			else:
				if _pressed and not _dragging:
					_click_crystal(event.position)
				_pressed = false
				_dragging = false
		accept_event()
	elif event is InputEventMouseMotion and _pressed and zoom > 1.0:
		if not _dragging and event.position.distance_to(_press_at) > 6.0:
			_dragging = true
			centre = _view().get_center()
		if _dragging:
			centre -= event.relative / _frame.size * _view().size
		accept_event()


# Clicking a crystal travels there, standing at a crystal.
func _click_crystal(at: Vector2) -> void:
	if _crystals == null:
		return
	for s in _crystal_spots:
		if at.distance_to(s[0]) < 12.0 * HudStyle.SCALE:
			if _crystals._at_crystal(Crystals.RANGE * 1.8).is_empty():
				FloatingText.spawn(world, "Stand at a crystal to travel", miko.position + Vector2(0, -1.6 * world.px), HudStyle.color("coral"))
			else:
				_crystals._go(s[1])
				close()
			return


var _buttons := {}                # name -> Rect2


func _click_buttons(at: Vector2) -> void:
	for n in _buttons:
		if (_buttons[n] as Rect2).has_point(at):
			match n:
				"close": close()
				"in": _step(1, null)
				"out": _step(-1, null)


func _process(_delta: float) -> void:
	if not visible:
		return
	_redraw_picture()
	# The frame: as big as fits, keeping the world's shape.
	var k := HudStyle.SCALE
	var vp := get_viewport_rect().size
	position = Vector2.ZERO
	size = vp
	var aspect := _area.size.x / maxf(1.0, _area.size.y)
	var avail := vp - Vector2(MARGIN * 2.0, MARGIN + 110.0) * k - Vector2(0, 46 * k)
	var w := minf(avail.x, avail.y * aspect)
	_frame = Rect2(Vector2((vp.x - w) / 2.0, (vp.y - 110.0 * k - w / aspect) / 2.0 + 30 * k), Vector2(w, w / aspect))
	queue_redraw()


func _text(at: Vector2, s: String, px: float, c: Color, kind := "bold", align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	var f := HudStyle.font(kind)
	var size := roundi(px * HudStyle.SCALE)
	draw_string_outline(f, at, s, align, width, size, 4, Color(0, 0, 0, 0.75))
	draw_string(f, at, s, align, width, size, c)


func _draw() -> void:
	var k := HudStyle.SCALE
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.03, 0.03, 0.78))
	var panel := Rect2(_frame.position - Vector2(8, 46) * k, _frame.size + Vector2(16, 54) * k)
	draw_style_box(HudStyle.piece("panelStrong"), panel)
	_text(panel.position + Vector2(12, 28) * k, "Map", 18, HudStyle.color("accentLight"), "pixel")
	var legend := "L sections   ■ Hostile   ■ Calm   ■ Villagers   ◆ Crystals   ■ Banner"
	_text(panel.position + Vector2(90, 28) * k, legend, 11, HudStyle.color("muted"))
	# Zoom and close, top right.
	_buttons.clear()
	var x := panel.end.x - 12 * k
	for b in [["close", "M"], ["out", "−"], ["in", "+"]]:
		var r := Rect2(Vector2(x - 26 * k, panel.position.y + 9 * k), Vector2(26, 26) * k)
		draw_style_box(HudStyle.piece("pill"), r)
		_text(r.position + Vector2(0, 18 * k), b[1], 13, HudStyle.color("text"), "bold", HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		_buttons[b[0]] = r
		x -= 32 * k
	# The kept picture, cropped to the view; the fog the same.
	var view := _view()
	var tex := _vp.get_texture()
	var src := Rect2((view.position - _area.position) / _area.size * Vector2(_vp.size), view.size / _area.size * Vector2(_vp.size))
	draw_texture_rect_region(tex, _frame, src)
	var ex := Exploration.active
	if ex != null:
		draw_texture_rect_region(ex.fog(), _frame, ex.fog_region(view))
	# The sections' grid and names.
	if show_sections:
		var line := Color(1, 1, 1, 0.22)
		var lo := MapMarks.MIN_CELL
		var hi := MapMarks.MAX_CELL + 1
		var f := world.floors
		for c in MapMarks.section_lines():
			_line(f.corner(Vector2(c, lo)), f.corner(Vector2(c, hi)), line, 1.0)
			_line(f.corner(Vector2(lo, c)), f.corner(Vector2(hi, c)), line, 1.0)
		var px := clampf(9.0 * sqrt(maxf(1.0, zoom)), 9.0, 16.0)
		for col in MapMarks.SECTIONS:
			for row in MapMarks.SECTIONS:
				var b := MapMarks.section_bounds(col, row)
				var mid := _to_screen(f.corner(Vector2(b.position) + Vector2(b.size) / 2.0))
				if _frame.has_point(mid):
					_text(mid + Vector2(-40 * k, 4 * k), MapMarks.section_name(col, row), px, Color(1, 1, 1, 0.55), "bold", HORIZONTAL_ALIGNMENT_CENTER, 80 * k)
	# The village's edge and banner.
	var green := HudStyle.color("green")
	for loop in MapMarks.village_loops(world):
		for i in loop.size():
			_line(loop[i], loop[(i + 1) % loop.size()], Color(green, 0.9), 2.0)
	# Creatures and villagers as squares.
	for m in MapMarks.marks(world):
		_square(_to_screen(m[0]), (m[2] + 1.0) * k, m[1])
	if world.village.founded():
		_square(_to_screen(world.village.centre()), 9 * k, MapMarks.BANNER, 12 * k)
	if Fainting.LostBag.active != null and is_instance_valid(Fainting.LostBag.active):
		_square(_to_screen(Fainting.LostBag.active.position), 13 * k, MapMarks.BAG)
	# Crystals, named.
	_crystal_spots.clear()
	if _crystals != null:
		for c in _crystals.teleports:
			var p := _to_screen(c.pos)
			if not _frame.has_point(p):
				continue
			_diamond(p, 7 * k, MapMarks.CRYSTAL)
			_text(p + Vector2(-100 * k, -12 * k), _crystals.name_of(c.pos), 11, HudStyle.color("text"), "bold", HORIZONTAL_ALIGNMENT_CENTER, 200 * k)
			_crystal_spots.append([p, c])
	# Miko on top.
	_square(_to_screen(miko.position), 11 * k, HudStyle.color("accentLight"))


func _line(a: Vector2, b: Vector2, c: Color, width: float) -> void:
	var p := _to_screen(a)
	var q := _to_screen(b)
	# Kept to the frame.
	var clipped := Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([p, q]), PackedVector2Array([_frame.position, Vector2(_frame.end.x, _frame.position.y), _frame.end, Vector2(_frame.position.x, _frame.end.y)]))
	for seg in clipped:
		if seg.size() >= 2:
			draw_line(seg[0], seg[seg.size() - 1], c, width * HudStyle.SCALE, true)


func _square(at: Vector2, w: float, c: Color, h := -1.0) -> void:
	if not _frame.has_point(at):
		return
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
