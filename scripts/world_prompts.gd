class_name WorldPrompts
extends Node
## The "press a key" prompts (E Open chest, E Use workbench, Press E to light...) shown in the world beside what they're
## about, not fixed at the bottom of the screen: the text in a dark pill, with an arrow from the pill back to the thing
## ( ◄──── [ E  Town banner ] ). Each prompt label is registered once; [method at] says where it belongs (a point in
## the world, px). One without a point shows beside Miko's head. Several at once go in one list, under the first.
## When two or more of them take E, one row is picked (its pill warmed, the rest dimmed): E goes to it alone, Tab
## picks the next, and clicking a row uses it straight away. Each system asks [method take] whether E went to its prompt this frame.

const GAP := 54.0         ## screen px from the thing to the pill (the arrow's length)
## The keys a prompt asks for, ringed so they stand out: a capital letter on its own (E, R, Z...), or a named key.
const KEY_WORDS := ["Esc", "Space", "Shift", "Tab", "Enter"]
static var _key_re: RegEx

static var _labels: Array = []
static var _at := {}            ## label -> world point
static var _miko: Node2D
static var _choices: Array = []  ## the rows showing that take E, top to bottom
static var _picked: Label        ## the one of them E goes to
static var _press: Label         ## the row E (or a click) went to this frame
static var _by_hand := false     ## whether she picked a row herself (Tab, a click) since the rows last changed
static var _e_re: RegEx

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
	# (the picked one of several: the same pill, warmed)
	var lit := HudStyle.piece("pillPlain", Color(1.0, 0.8, 0.45, 1.0))
	lit.content_margin_left = 12
	lit.content_margin_right = 14
	lit.content_margin_top = 4
	lit.content_margin_bottom = 4
	label.set_meta("pill", pill)
	label.set_meta("pill_lit", lit)
	label.add_theme_font_size_override("font_size", roundi(13 * HudStyle.SCALE))
	label.mouse_filter = Control.MOUSE_FILTER_STOP
	label.gui_input.connect(func(e: InputEvent) -> void: _clicked(label, e))
	_labels.append(label)


## Whether E (or a click) went to [param label] this frame: then it's used up.
static func take(label: Label) -> bool:
	if _press != null and _press == label:
		_press = null
		return true
	return false


## Whether E goes to the list (two or more rows take it), not straight to every system.
static func choosing() -> bool:
	return _choices.size() >= 2


static func _clicked(label: Label, e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and _choices.has(label):
		_picked = label
		_by_hand = true
		_press = label
		label.accept_event()


# Whether [param l]'s text asks for E.
static func _takes_e(l: Label) -> bool:
	if _e_re == null:
		_e_re = RegEx.create_from_string("(?<![A-Za-z0-9_'])E(?![A-Za-z0-9_'])")
	return _e_re.search(l.text) != null


## Puts [param label] beside [param point] (world px) while it shows.
static func at(label: Label, point: Vector2) -> void:
	_at[label] = point


func setup(miko: Node2D) -> void:
	_miko = miko
	_labels.clear()
	_at.clear()
	_choices.clear()
	_picked = null
	_press = null
	process_priority = 100000


func _input(event: InputEvent) -> void:
	if not choosing() or not (event is InputEventKey and event.pressed and not event.echo):
		return
	if Talk.active != null and Talk.active.visible:
		return
	if event.keycode == KEY_E:
		_press = _picked
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_TAB:
		var i := _choices.find(_picked)
		_picked = _choices[(i + (-1 if event.shift_pressed else 1) + _choices.size()) % _choices.size()]
		_by_hand = true
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	_press = null                      # (a press nobody took this frame is gone)
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
	# Every prompt showing, with where its thing is on screen; the highest thing first.
	var shown := []
	for l in _labels:
		if not is_instance_valid(l) or not l.visible or l.text == "":
			continue
		var p: Vector2 = _at.get(l, _miko.position + Vector2(0, -1.2 * px) if _miko != null else Vector2.ZERO)
		l.reset_size()
		shown.append([l, xf * p])
	shown.sort_custom(func(x, y): return (x[1] as Vector2).y < (y[1] as Vector2).y)
	# The rows that take E. Till she picks one herself: the one marked "first" (someone with a story scene waiting),
	# else the one picked before while it's still there, else the top.
	var choices := []
	for sh in shown:
		if _takes_e(sh[0]):
			choices.append(sh[0])
	if choices != _choices:
		_choices = choices
		_by_hand = false
		if not choices.has(_picked):
			_picked = null
	if not _by_hand:
		for c in choices:
			if c.get_meta("first", false):
				_picked = c
	if _picked == null and not choices.is_empty():
		_picked = choices[0]
	var picked: Label = _picked if choosing() else null
	# One column: the first beside its thing, its arrow pointing back at it; the rest straight below it, in a list.
	var col := Vector2.ZERO
	for i in shown.size():
		var l: Label = shown[i][0]
		var s: Vector2 = shown[i][1]
		if i == 0:
			col = Vector2(s.x + GAP * HudStyle.SCALE, s.y - l.size.y / 2.0)
			lines.append([s + Vector2(6, 0), Vector2(col.x, col.y + l.size.y / 2.0)])
		l.position = col.round()
		col.y += l.size.y + 4.0
		keys.append_array(_keys_in(l))
		var on := l == picked
		if l.has_meta("pill"):
			var want: StyleBox = l.get_meta("pill_lit") if on else l.get_meta("pill")
			if l.get_theme_stylebox("normal") != want:
				l.add_theme_stylebox_override("normal", want)
		l.modulate = Color.WHITE if picked == null or on or not _choices.has(l) else Color(0.85, 0.85, 0.85, 0.6)
	_rings.tab_at = Vector2(picked.position.x + picked.size.x + 8.0, picked.position.y + picked.size.y / 2.0) if picked != null else Vector2.ZERO
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
	var tab_at := Vector2.ZERO       ## where "Tab" is said beside the picked row (several to choose from), or zero

	func _draw() -> void:
		var accent := HudStyle.color("accentLight")
		var edge := maxi(3, roundi(4.0 * HudStyle.SCALE))
		if tab_at != Vector2.ZERO:
			var font := get_theme_default_font()
			var fsize := roundi(11 * HudStyle.SCALE)
			var at := tab_at + Vector2(0, font.get_ascent(fsize) / 2.0 - 1.0)
			draw_string_outline(font, at, "◂ Tab", HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, edge, Color(0.07, 0.05, 0.04, 0.95))
			draw_string(font, at, "◂ Tab", HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, accent)
		for k in keys:
			draw_string_outline(k[2], k[0], k[1], HORIZONTAL_ALIGNMENT_LEFT, -1, k[3], edge, Color(0.07, 0.05, 0.04, 0.95))
			draw_string(k[2], k[0], k[1], HORIZONTAL_ALIGNMENT_LEFT, -1, k[3], accent)
