class_name RumorTracker
extends Control
## The tracked rumor on screen, as she plays: a small card under the minimap (its name, what's known of it now, which
## way it lies and about how far), and an arrow by Miko pointing towards where it might be (the middle of its ring on
## the maps), gone once she's inside the ring: from there it's hers to find. Shows the rumor tracked last.

const ARROW_OUT := 1.5            ## units from Miko the arrow floats
const CARD_WIDTH := 210.0

var rumors: Rumors
var miko: Miko
var world: World
var minimap: Control
var _card: PanelContainer
var _title: Label
var _note: Label
var _way: Label
var _shown := ""                 ## what the card shows now (rebuilt only when it changes)


func setup(r: Rumors, w: World, who: Miko, map: Control) -> void:
	rumors = r
	world = w
	miko = who
	minimap = map
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_card = PanelContainer.new()
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_theme_stylebox_override("panel", HudStyle.piece("panel"))
	add_child(_card)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", roundi(2 * HudStyle.SCALE))
	_card.add_child(box)
	_title = HudStyle.label("", 11, "bold", HudStyle.color("accentLight"))
	_note = HudStyle.label("", 10, "body", HudStyle.color("text"))
	_way = HudStyle.label("", 9, "body", HudStyle.color("muted"))
	for l in [_title, _note, _way]:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = CARD_WIDTH * HudStyle.SCALE
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(l)
	_card.visible = false


## The rumor shown: the one tracked that was heard last, as [method Rumors.marks] has it, or {}.
func tracked() -> Dictionary:
	var best := {}
	var best_h := -INF
	for m in rumors.marks():
		var h := float(rumors.heard[m.id].from)
		if h > best_h:
			best_h = h
			best = m
	return best


func _process(_delta: float) -> void:
	var m := tracked()
	var up := not m.is_empty() and not Cellars.inside(miko.position)
	_card.visible = up
	if not up:
		if _shown != "":
			_shown = ""
			queue_redraw()
		return
	var d: Vector2 = ((m.at as Vector2) - miko.position) / world.px
	var far := Vector2(d.x, d.y * 2.0).length()
	var inside: bool = far <= float(m.radius) / world.px
	var lines: Array = rumors.lines(str(m.id))
	var now := "%s|%s|%d|%s" % [m.id, lines.size(), roundi(far / 5.0), inside]
	if now != _shown:
		_shown = now
		_title.text = "Rumor  ·  %s" % str(m.title)
		_note.text = str(lines[-1][0]) if not lines.is_empty() else ""
		_way.text = "Somewhere near here" if inside else "About %d tiles to the %s" % [maxi(5, roundi(far / 5.0) * 5), _direction(d)]
		_card.reset_size()
	# Under the minimap, at the screen's right.
	var top := (minimap.get_global_rect().end.y if minimap != null else 0.0) + 8.0 * HudStyle.SCALE
	_card.position = Vector2(get_viewport_rect().size.x - _card.size.x - 12.0 * HudStyle.SCALE, top).round()
	queue_redraw()


func _direction(d: Vector2) -> String:
	var names := ["east", "south-east", "south", "south-west", "west", "north-west", "north", "north-east"]
	return names[posmod(roundi(Vector2(d.x, d.y * 2.0).angle() / (PI / 4.0)), 8)]


# The arrow: out from Miko towards the ring's middle, bobbing a little; none inside the ring.
func _draw() -> void:
	var m := tracked()
	if m.is_empty() or not _card.visible or miko.locked:
		return
	var to: Vector2 = (m.at as Vector2) - miko.position
	var d := to / world.px
	if Vector2(d.x, d.y * 2.0).length() <= float(m.radius) / world.px:
		return
	var view := world.get_viewport().get_canvas_transform()
	var zoom := view.get_scale().x
	var dir := to.normalized()
	var bob := sin(Time.get_ticks_msec() / 1000.0 * 4.0) * 0.06
	var centre: Vector2 = view * (miko.position + Vector2(0, -0.55 * world.px))
	var at := centre + Vector2(dir.x, dir.y) * (ARROW_OUT + bob) * world.px * zoom
	var k := HudStyle.SCALE
	var side := Vector2(-dir.y, dir.x)
	var tip := at + dir * 13.0 * k
	var pts := PackedVector2Array([tip, at - dir * 6.0 * k + side * 9.0 * k, at - dir * 2.0 * k, at - dir * 6.0 * k - side * 9.0 * k])
	var dark := PackedVector2Array()
	for p in pts:
		dark.append(at + (p - at) * 1.3)
	draw_colored_polygon(dark, Color(0.1, 0.07, 0.06, 0.85))
	draw_colored_polygon(pts, Color(1.0, 0.82, 0.3))
