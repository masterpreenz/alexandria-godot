class_name PartyWindow
extends PanelContainer
## The party window (C, or a click on a party card under Sera's): Sera, then each companion with her: their face and
## level, name, HP and mana, attack, and what they're at (with her, waiting and roughly where, fighting, far behind).
## Each takes the same orders as in a talk: "Follow me", "Wait here" (where they stand now), "Go home" (they leave the
## party). The places left say so, with anyone who'd come along if asked. It steps aside while Sera's talking.

const FAR := 12.0                 ## units behind her a companion's "far behind"

static var active: PartyWindow

var miko: Miko
var _sig := ""
var _rows: Array[Callable] = []   ## each row's own refresh (bars, level, what they're at)
var _next := 0.0


func setup(who: Miko) -> void:
	miko = who
	active = self
	add_theme_stylebox_override("panel", HudStyle.piece("panelStrong"))
	visible = false


func _k(v: float) -> float:
	return v * HudStyle.SCALE


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo) or HudStyle.typing(get_viewport()):
		return
	if event.keycode == KEY_C and (visible or not miko.locked):
		if visible: close()
		else: open()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ESCAPE and visible:
		close()
		get_viewport().set_input_as_handled()


func open() -> void:
	if Party.active == null or miko.locked:
		return
	visible = true
	move_to_front()
	_sig = ""
	_next = 0.0


func close() -> void:
	visible = false


func _process(delta: float) -> void:
	var __t := Time.get_ticks_usec()
	_process_timed(delta)
	Perf.add(&"party_window.process", __t)


func _process_timed(_delta: float) -> void:
	if not visible:
		return
	# (a talk's begun: out of its way)
	if miko.locked:
		close()
		return
	var sig := _signature()
	if sig != _sig:
		_sig = sig
		_build()
	var now := Time.get_ticks_msec() / 1000.0
	if now >= _next:
		_next = now + 0.25
		for r in _rows:
			r.call()


# Who's in it, who's waiting, and who'd come: when that changes, the window's laid out again.
func _signature() -> String:
	var pa := Party.active
	var s := ",".join(PackedStringArray(pa.members)) + "|" + ",".join(PackedStringArray(pa.waiting.keys())) + "|"
	for p in pa.people.people:
		if _would_come(p):
			s += str(p.unique) + ","
	return s


func _would_come(p: Dictionary) -> bool:
	return Traits.has(p, "unique") and not Party.active.has_member(p) and Party.willing(p)


func _body(p: Dictionary) -> Villager:
	for v in Villager.all:
		if is_instance_valid(v) and v.person == p:
			return v
	return null


func _build() -> void:
	for c in get_children():
		c.queue_free()
	_rows.clear()
	var pa := Party.active
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", roundi(_k(6)))
	add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", roundi(_k(10)))
	box.add_child(head)
	head.add_child(HudStyle.label("Party", 16, "pixel", HudStyle.color("accentLight")))
	var count := HudStyle.label("%d of %d companions" % [pa.members.size(), Party.MOST], 11, "body", HudStyle.color("muted"))
	count.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(count)
	box.add_child(_sera_row())
	for id in pa.members:
		var p := Uniques.person(pa.people, str(id))
		if not p.is_empty():
			box.add_child(_companion_row(p))
	# The places left, and who'd fill them.
	var left := Party.MOST - pa.members.size()
	if left > 0:
		var keen: Array = pa.people.people.filter(_would_come)
		var free := _row_panel()
		var lines := VBoxContainer.new()
		lines.add_theme_constant_override("separation", roundi(_k(3)))
		free.add_child(lines)
		lines.add_child(HudStyle.label(("A place free" if left == 1 else "%d places free" % left), 12, "bold", HudStyle.color("muted")))
		if keen.is_empty():
			lines.add_child(_wrapped("Nobody's ready to come along yet. Those who'd go with you can be asked when you talk to them.", 11, HudStyle.color("faint")))
		for p in keen:
			lines.add_child(_wrapped("%s would come: talk to them and ask." % str(p.name), 11, HudStyle.color("text")))
		box.add_child(free)
	box.add_child(HudStyle.label("C or Esc to close", 9, "body", HudStyle.color("faint")))
	for r in _rows:
		r.call()
	reset_size()
	position = ((get_viewport_rect().size - size) / 2.0).round()


func _wrapped(text: String, sz: float, c: Color) -> Label:
	var l := HudStyle.label(text, sz, "body", c)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = _k(440)
	return l


func _row_panel() -> PanelContainer:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", HudStyle.piece("panel"))
	pc.custom_minimum_size.x = _k(460)
	return pc


# The row's middle: name and level, attack, the bars, and what they're at (filled in by the row's refresh).
func _info(row: HBoxContainer, title: String) -> Dictionary:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", roundi(_k(2)))
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", roundi(_k(8)))
	col.add_child(top)
	top.add_child(HudStyle.label(title, 13, "bold", HudStyle.color("text")))
	var lv := HudStyle.label("", 11, "pixel", HudStyle.color("accentLight"))
	top.add_child(lv)
	var atk := HudStyle.label("", 11, "body", HudStyle.color("muted"))
	top.add_child(atk)
	var bars := Bars.new()
	bars.custom_minimum_size = Vector2(_k(230), _k(26))
	col.add_child(bars)
	var doing := HudStyle.label("", 11, "body", HudStyle.color("muted"))
	doing.clip_text = true
	doing.custom_minimum_size.x = _k(230)
	col.add_child(doing)
	return {"lv": lv, "atk": atk, "bars": bars, "doing": doing}


func _sera_row() -> PanelContainer:
	var pc := _row_panel()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", roundi(_k(10)))
	pc.add_child(row)
	var face := Portrait.new()
	face.tex = HudStyle.icon("portrait")
	face.custom_minimum_size = Vector2(_k(48), _k(48))
	face.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(face)
	var ui := _info(row, Miko.NAME)
	var stats := miko.stats
	_rows.append(func():
		var t := stats.total()
		face.level = stats.level
		face.queue_redraw()
		(ui.lv as Label).text = "Lv %d" % stats.level
		(ui.atk as Label).text = "Attack %s" % CharacterStats.fmt(float(t.get("attack", 0.0)))
		var bars: Bars = ui.bars
		bars.hp = stats.hp
		bars.most_hp = maxf(1.0, float(t.get("maxHp", 100.0)))
		bars.mana = stats.mana
		bars.most_mana = maxf(1.0, float(t.get("maxMana", 50.0)))
		bars.queue_redraw()
		(ui.doing as Label).text = "Leading the party")
	return pc


func _companion_row(p: Dictionary) -> PanelContainer:
	var pa := Party.active
	var id := str(p.unique)
	var pc := _row_panel()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", roundi(_k(10)))
	pc.add_child(row)
	var face := Portrait.new()
	face.tex = pa.face(p)
	face.custom_minimum_size = Vector2(_k(48), _k(48))
	face.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(face)
	var ui := _info(row, str(p.name))
	# Their orders, as in a talk.
	var orders := VBoxContainer.new()
	orders.add_theme_constant_override("separation", roundi(_k(3)))
	orders.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(orders)
	var waiting := pa.waiting.has(id)
	var follow := _order("Follow me", not waiting, func(): pa.follow(p))
	var wait := _order("Wait here", waiting, func():
		var body := _body(p)
		if body != null:
			pa.wait_here(p, body.position))
	var home := _order("Go home", false, func():
		var body := _body(p)
		pa.leave(id)
		if body != null:
			body._stand(Villager.now(), 0.5))
	orders.add_child(follow)
	orders.add_child(wait)
	orders.add_child(home)
	_rows.append(func():
		var body := _body(p)
		face.level = int(p.get("level", 1))
		face.queue_redraw()
		(ui.lv as Label).text = "Lv %d" % int(p.get("level", 1))
		(ui.atk as Label).text = "Attack %s" % CharacterStats.fmt(float(p.get("atk", 0.0)))
		var bars: Bars = ui.bars
		bars.hp = body.hit.hp if body != null and body.hit != null else float(p.get("hp", 0.0))
		bars.most_hp = body.hit.max_hp if body != null and body.hit != null else maxf(1.0, float(p.get("maxHp", 1.0)))
		bars.mana = float(p.get("mana", 0.0))
		bars.most_mana = float(p.get("maxMana", 0.0))
		bars.queue_redraw()
		var low := bars.hp / maxf(1.0, bars.most_hp) < 0.3
		(ui.doing as Label).text = _doing(p, body)
		(ui.doing as Label).add_theme_color_override("font_color", HudStyle.color("coral") if low else HudStyle.color("muted"))
		wait.disabled = body == null or pa.waiting.has(id))
	return pc


func _order(text: String, off: bool, act: Callable) -> Button:
	var b := HudStyle.button(text, 11)
	b.custom_minimum_size = Vector2(_k(104), _k(22))
	b.disabled = off
	b.pressed.connect(func():
		act.call()
		_sig = "")
	return b


# What a companion's at, in a few words.
func _doing(p: Dictionary, body: Villager) -> String:
	if body == null:
		return "Away"
	var waiting := Party.active.waiting.has(str(p.unique))
	var gap := body.position - miko.position
	var units := gap.length() / miko.world.px
	if body.state == Villager.State.FIGHT:
		return "Fighting beside you" if units < FAR else "Fighting, " + _where(gap, units)
	if body.state == Villager.State.FLEE:
		return body.activity()
	if waiting:
		var spot: Vector2 = Party.active.waiting[str(p.unique)]
		var off := spot - miko.position
		var away := off.length() / miko.world.px
		return "Waiting right by you" if away < 3.0 else "Waiting " + _where(off, away)
	if body.state == Villager.State.FOLLOW:
		return "Following you" if units < FAR else "Far behind: %d units back, catching up" % roundi(units)
	return body.activity()


# Roughly where [param off] (from Sera) is: "a little way north-east of you", "far off to the west"...
func _where(off: Vector2, units: float) -> String:
	var d := off
	d.y *= 2.0
	var names := ["east", "south-east", "south", "south-west", "west", "north-west", "north", "north-east"]
	var way: String = names[posmod(roundi(d.angle() / (PI / 4.0)), 8)]
	if units < FAR:
		return "a little way %s of you" % way
	if units < 60.0:
		return "%d units %s of you" % [roundi(units), way]
	return "far off to the " + way


## A face in its frame, the level on its corner (as on the party cards).
class Portrait extends Control:
	var tex: Texture2D
	var level := 1

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var k := HudStyle.SCALE
		var fr := Rect2(Vector2.ZERO, size)
		draw_rect(fr, Color(0.08, 0.06, 0.06, 0.9))
		if tex != null:
			draw_texture_rect(tex, fr, false)
		draw_style_box(HudStyle.piece("portraitFrame"), fr)
		var badge := Rect2(fr.end - Vector2(14, 14) * k, Vector2(18, 18) * k)
		var b_tex := HudStyle.icon("badge")
		if b_tex != null:
			draw_texture_rect(b_tex, badge, false)
		var f := HudStyle.font("pixel")
		if f == null:
			f = get_theme_default_font()
		draw_string(f, badge.position + Vector2(0, badge.size.y * 0.75), str(level), HORIZONTAL_ALIGNMENT_CENTER, badge.size.x, roundi(10 * k), HudStyle.color("ink"))


## HP and mana (empty for those who've learned no magic), the numbers at their ends (as on the party cards).
class Bars extends Control:
	var hp := 0.0
	var most_hp := 1.0
	var mana := 0.0
	var most_mana := 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var k := HudStyle.SCALE
		_bar(1 * k, 7 * k, "heart", HudStyle.color("hp"), hp / maxf(1.0, most_hp), str(ceili(hp)))
		_bar(14 * k, 5 * k, "drop", HudStyle.color("mana"), mana / maxf(1.0, most_mana), str(floori(mana)))

	func _bar(y: float, h: float, icon: String, c: Color, frac: float, num: String) -> void:
		var k := HudStyle.SCALE
		var ic := HudStyle.icon(icon)
		if ic != null:
			draw_texture_rect(ic, Rect2(Vector2(0, y + h / 2.0 - 5 * k), Vector2(10, 10) * k), false, c)
		var back := Rect2(Vector2(14 * k, y), Vector2(size.x - 14 * k - 36 * k, h))
		draw_style_box(HudStyle.piece("barBack"), back)
		frac = clampf(frac, 0.0, 1.0)
		if frac > 0.02:
			draw_style_box(HudStyle.piece("barFill", c), Rect2(back.position, Vector2(back.size.x * frac, h)))
		var f := HudStyle.font("pixel")
		if f == null:
			f = get_theme_default_font()
		var at := Vector2(size.x - 32 * k, y + h / 2.0 + 4 * k)
		draw_string_outline(f, at, num, HORIZONTAL_ALIGNMENT_RIGHT, 32 * k, roundi(11 * k), 3, Color(0, 0, 0, 0.5))
		draw_string(f, at, num, HORIZONTAL_ALIGNMENT_RIGHT, 32 * k, roundi(11 * k), HudStyle.color("text"))
