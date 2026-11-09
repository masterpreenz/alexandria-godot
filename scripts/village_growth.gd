class_name VillageGrowth
extends Node2D
## Growing the village where Miko chooses (from Unity's VillageGrowth; "Choose where to grow" on the town banner): the
## next block of land goes on one whole side of the village, whichever side the mouse is towards, running the full
## length of that side. Where a main road crosses it (roads can't be built on), it reaches further out to make up the
## ground the road takes. Green where it can go and is paid for, red with the reason where not. A click adds it and
## pays; right click or Esc stops. The view pulls back while choosing.

var world: World
var miko: Miko
var active := false
var _hint: PanelContainer
var _hint_text: Label
var _rect := Rect2i()
var _ok := false
var _zoom := Vector2.ONE
var _click := false
var _stop := false


func setup(w: World, who: Miko, hud: Node) -> void:
	world = w
	miko = who
	z_as_relative = false
	z_index = 4000
	_hint = PanelContainer.new()
	_hint.add_theme_stylebox_override("panel", HudStyle.piece("pill"))
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_text = HudStyle.label("", 12, "bold")
	_hint_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_child(_hint_text)
	_hint.visible = false
	hud.add_child(_hint)


func begin() -> void:
	var v := world.village
	if not v.founded() or v.max_tier():
		return
	active = true
	miko.locked = true
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		_zoom = cam.zoom
		cam.zoom = _zoom / 2.4


func end() -> void:
	active = false
	miko.locked = false
	_hint.visible = false
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		cam.zoom = _zoom
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT: _click = true
		elif event.button_index == MOUSE_BUTTON_RIGHT: _stop = true
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_stop = true
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	var __t := Time.get_ticks_usec()
	_process_timed(delta)
	Perf.add(&"village_growth.process", __t)


func _process_timed(_delta: float) -> void:
	var click := _click
	var stop := _stop
	_click = false
	_stop = false
	if not active:
		return
	var v := world.village
	if stop or not v.founded() or v.max_tier():
		end()
		return
	var b := v.banner_cell()
	var fit := _fit(world.floors.cell_at(get_global_mouse_position()) - b)
	_rect = fit[0]
	var cost := v.next_upgrade()
	var affordable := v.can_afford(miko.bag, miko, cost)
	var why := v.cant_add(_rect)
	_ok = why == "" and affordable
	var extra := " (+%d for the main road)" % fit[2] if fit[2] > 0 else ""
	_hint_text.text = ("Grow the village %s: %d × %d tiles%s  ·  click to grow (%s)  ·  right-click or Esc stop" % [fit[1], _rect.size.x, _rect.size.y, extra, _price(cost)]) if _ok \
		else ("%s  ·  right-click or Esc stop" % (("Not enough to pay: " + _price(cost)) if why == "" else why))
	_hint_text.add_theme_color_override("font_color", HudStyle.color("text") if _ok else HudStyle.color("coral"))
	_hint.visible = true
	_hint.reset_size()
	var vp := get_viewport_rect().size
	_hint.position = Vector2((vp.x - _hint.size.x) / 2.0, vp.y - 150 * HudStyle.SCALE - _hint.size.y).round()
	queue_redraw()
	if click and _ok and v.grow(miko.bag, miko, _rect):
		var mid := world.floors.corner(world.floors.fractional_cell(v.centre()) + Vector2(_rect.position) + Vector2(_rect.size) / 2.0 - Vector2(0.5, 0.5))
		FloatingText.spawn(world, "The village grows! (%d tiles)" % v.area(), mid + Vector2(0, -0.5 * world.px), HudStyle.color("accentLight"))
		Puffs.burst(world, mid, 1.4)
		end()


# The block for the mouse at tile m (from the banner's): the whole side of the village m is towards, as deep as the
# next block, and deeper where a main road crosses it. [rect, side, road].
func _fit(m: Vector2i) -> Array:
	var v := world.village
	var x_min := 1 << 30
	var x_max := -(1 << 30)
	var y_min := 1 << 30
	var y_max := -(1 << 30)
	for r in v.rects():
		x_min = mini(x_min, r.position.x)
		x_max = maxi(x_max, r.end.x)
		y_min = mini(y_min, r.position.y)
		y_max = maxi(y_max, r.end.y)
	# Which side: measured against the village's own shape, so a long village's ends are as easy to pick as its sides.
	var cx := (x_min + x_max) / 2.0
	var cy := (y_min + y_max) / 2.0
	var dx := (m.x + 0.5 - cx) / maxf(1.0, (x_max - x_min) / 2.0)
	var dy := (m.y + 0.5 - cy) / maxf(1.0, (y_max - y_min) / 2.0)
	var along_x := absf(dx) >= absf(dy)
	var outward := dx >= 0.0 if along_x else dy >= 0.0
	# On screen +x is up-right and +y up-left.
	var side := ("north-east" if outward else "south-west") if along_x else ("north-west" if outward else "south-east")
	var depth := v.next_block().y
	var length := (y_max - y_min) if along_x else (x_max - x_min)
	var want := depth * length
	var b := v.banner_cell()
	var deep := depth
	while deep < depth * 3 and _free(_at(deep, along_x, outward, x_min, x_max, y_min, y_max, length), b) < want:
		deep += 1
	return [_at(deep, along_x, outward, x_min, x_max, y_min, y_max, length), side, deep - depth]


func _at(d: int, along_x: bool, outward: bool, x_min: int, x_max: int, y_min: int, y_max: int, length: int) -> Rect2i:
	if along_x:
		return Rect2i(x_max if outward else x_min - d, y_min, d, length)
	return Rect2i(x_min, y_max if outward else y_min - d, length, d)


# How many of the rect's tiles (from the banner's tile at b) aren't on a main road.
static func _free(rect: Rect2i, b: Vector2i) -> int:
	var n := 0
	var h := FloorMap.ROAD_HALF_WIDTH
	for x in range(rect.position.x, rect.end.x):
		for y in range(rect.position.y, rect.end.y):
			if absi(x + b.x) > h and absi(y + b.y) > h:
				n += 1
	return n


static func _price(cost: Array) -> String:
	if cost.is_empty():
		return "free"
	return ", ".join(Village.sum(cost).map(func(c): return "%d %s" % [c[1], UiKit.resource_name(c[0]).to_lower()]))


func _draw() -> void:
	if not active:
		return
	var b := world.floors.fractional_cell(world.village.centre())
	var lo := b + Vector2(_rect.position) - Vector2(0.5, 0.5)
	var hi := b + Vector2(_rect.end) - Vector2(0.5, 0.5)
	var f := world.floors
	var pts := PackedVector2Array([f.corner(lo), f.corner(Vector2(hi.x, lo.y)), f.corner(hi), f.corner(Vector2(lo.x, hi.y)), f.corner(lo)])
	var c := HudStyle.color("green") if _ok else HudStyle.color("coral")
	c.a = 0.75 + 0.2 * sin(Time.get_ticks_msec() / 1000.0 * 4.0)
	var fill := c
	fill.a = 0.18
	draw_colored_polygon(pts.slice(0, 4), fill)
	draw_polyline(pts, c, 0.09 * world.px, true)
