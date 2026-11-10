class_name FieldPanel
extends PanelContainer
## A farm field's control panel (R by a plot; R, Esc or walking away closes it): what the field is growing, how far on it
## is (each plot's growth, the hours to go), what it wants (dry plots, pests), what it should yield, and what it grows
## next: the village rotation's next crop, or one picked here (Rotation or a crop, for the whole field).

var farm: Farming
var field: Array = []             ## the field's plots (Farming's plot dictionaries)
var _at := Vector2.ZERO           ## the plot it was opened from (it closes when she walks off)
var _title: Label
var _lines: Label
var _bar: ProgressBar
var _next: Label
var _choices: HFlowContainer
var _refresh_at := 0.0


func setup(f: Farming) -> void:
	farm = f
	var k := HudStyle.SCALE
	add_theme_stylebox_override("panel", HudStyle.piece("panelStrong"))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(8 * k))
	add_child(box)
	var head := HBoxContainer.new()
	_title = HudStyle.label("", 16, "bold")
	head.add_child(_title)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(gap)
	head.add_child(HudStyle.label("R or Esc to close", 11, "body", HudStyle.color("muted")))
	box.add_child(head)
	var well := PanelContainer.new()
	well.add_theme_stylebox_override("panel", HudStyle.piece("well"))
	box.add_child(well)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", int(6 * k))
	well.add_child(inner)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(340, 10) * k
	var back := StyleBoxFlat.new()
	back.bg_color = Color(1, 1, 1, 0.08)
	back.set_corner_radius_all(5)
	var fill := StyleBoxFlat.new()
	fill.bg_color = HudStyle.color("green")
	fill.set_corner_radius_all(5)
	_bar.add_theme_stylebox_override("background", back)
	_bar.add_theme_stylebox_override("fill", fill)
	inner.add_child(_bar)
	_lines = HudStyle.label("", 12, "body")
	_lines.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lines.custom_minimum_size.x = 340 * k
	inner.add_child(_lines)
	box.add_child(HudStyle.label("NEXT CROP", 11, "bold", HudStyle.color("muted")))
	_next = HudStyle.label("", 12, "body")
	_next.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_next.custom_minimum_size.x = 340 * k
	box.add_child(_next)
	_choices = HFlowContainer.new()
	_choices.add_theme_constant_override("h_separation", int(6 * k))
	_choices.add_theme_constant_override("v_separation", int(6 * k))
	box.add_child(_choices)
	visible = false


## Opens on the field [param p] belongs to.
func open(p: Dictionary) -> void:
	field = farm.field_of(p)
	_at = p.pos
	visible = true
	move_to_front()
	_refresh()


func close() -> void:
	visible = false
	field = []


func _process(_delta: float) -> void:
	if not visible:
		return
	if farm.miko.position.distance_to(_at) > 2.5 * farm.world.px or farm.miko.locked:
		close()
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now >= _refresh_at:
		_refresh()
	reset_size()
	position = ((get_viewport_rect().size - size) / 2.0).round() + Vector2(0, 20)


func _refresh() -> void:
	_refresh_at = Time.get_ticks_msec() / 1000.0 + 0.25
	field = field.filter(func(q): return farm.plots.has(q))
	if field.is_empty():
		close()
		return
	var p: Dictionary = field[0]
	var growing := field.filter(func(q): return farm.stage(q) == 1)
	var ripe := field.filter(func(q): return farm.stage(q) == 2)
	var sown := growing + ripe
	var crop := farm.crop(sown[0]) if not sown.is_empty() else ""
	var info: Dictionary = Farming.CROPS.get(crop, {})
	_title.text = "Field  ·  %d plot%s" % [field.size(), "" if field.size() == 1 else "s"]
	var t := []
	if sown.is_empty():
		var waiting := field.filter(func(q): return farm._state(q).get("waiting", false)).size()
		t.append("Bare: nothing planted" + ("" if waiting == 0 else "  (just harvested)"))
		_bar.value = 0.0
	else:
		# Growth: each plot's share of its growing, averaged; the hours to go for the slowest.
		var share := 0.0
		var most_left := 0.0
		for q in sown:
			share += 1.0 if farm.stage(q) == 2 else clampf(farm._grown(q) / maxf(0.01, farm._grow(q)), 0.0, 1.0)
			most_left = maxf(most_left, farm.hours_left(q))
		share /= sown.size()
		_bar.value = share * 100.0
		var crop_name: String = str(info.get("plural", crop)).capitalize()
		if ripe.size() == sown.size():
			t.append("%s  ·  ripe  ·  E to harvest" % crop_name)
		else:
			t.append("%s  ·  %d%% grown  ·  %s" % [crop_name, roundi(share * 100.0), ("ready in about %d h" % ceili(most_left)) if most_left >= 1.0 else "nearly ready"])
		if ripe.size() > 0 and ripe.size() < sown.size():
			t.append("%d of %d ripe" % [ripe.size(), sown.size()])
		var waiting := field.size() - sown.size()
		if waiting > 0:
			t.append("%d plot%s harvested, waiting for the rest" % [waiting, "" if waiting == 1 else "s"])
		# What it wants.
		var dry := growing.filter(func(q): return farm.dry(q)).size()
		var pests := growing.filter(func(q): return farm.pests(q)).size()
		var care := []
		if dry > 0:
			care.append("%d dry (half speed: water them)" % dry)
		if pests > 0:
			care.append("%d with pests (not growing: clear them)" % pests)
		t.append("Care: " + (", ".join(care) if not care.is_empty() else "all watered, no pests"))
		# Not ripe before winter: lost to the frost.
		if growing.size() > 0 and most_left > farm.hours_to_winter() and not farm.winter():
			t.append("[!] Won't ripen before winter: the frost will kill it")
		# What it should give.
		var y: Array = p.s.yield if crop == "Potato" else info.get("yield", [0, 0])
		var seed_back: Array = info.get("seedBack", [0, 0])
		var line := "Yield: %d to %d %s" % [int(y[0]) * sown.size(), int(y[1]) * sown.size(), str(info.get("plural", crop))]
		if int(seed_back[1]) > 0:
			line += ", and %d to %d seeds back" % [int(seed_back[0]) * sown.size(), int(seed_back[1]) * sown.size()]
		t.append(line)
	t.append(_season_line())
	_lines.text = "\n".join(t)
	_show_next(p, crop)


# When winter comes (nothing planted then; frost kills what's growing), or in winter, when spring does.
func _season_line() -> String:
	if farm.world.clock == null:
		return ""
	if farm.winter():
		return "Winter now: nothing can be planted  ·  spring in %s" % _span(farm.hours_to_spring())
	return "Next winter in %s (frost kills what's still growing)" % _span(farm.hours_to_winter())


static func _span(h: float) -> String:
	if h >= 48.0:
		return "%d days" % floori(h / 24.0)
	if h >= 24.0:
		return "1 day %d h" % floori(h - 24.0)
	return "%d h" % ceili(h)


# What it grows next, and the choices: Rotation, or one crop for good.
func _show_next(p: Dictionary, now_growing: String) -> void:
	var set_to: String = farm._state(p).setTo
	var rot: Array = farm.rotation
	var nxt := set_to
	if nxt == "":
		var last := now_growing if now_growing != "" else farm._field_last(p)
		nxt = rot[(rot.find(last) + 1) % rot.size()] if last != "" and rot.has(last) else rot[farm._next % rot.size()]
	var names := rot.map(func(c): return str(Farming.CROPS[c].plural).capitalize())
	_next.text = ("%s  ·  set for this field" % str(Farming.CROPS[nxt].plural).capitalize()) if set_to != "" else \
		("%s  ·  village rotation: %s" % [str(Farming.CROPS[nxt].plural).capitalize(), " → ".join(names)])
	for c in _choices.get_children():
		c.queue_free()
	for option in [""] + Farming.ORDER:
		var label := "Rotation" if option == "" else str(Farming.CROPS[option].plural).capitalize()
		var b := _choice(label, set_to == option)
		b.pressed.connect(_pick.bind(option))
		_choices.add_child(b)


func _choice(text: String, on: bool) -> Button:
	@warning_ignore("incompatible_ternary")
	var b := HudStyle.button(text, 12, "barFill" if on else "pill", HudStyle.color("ink") if on else null)
	if on:
		b.add_theme_stylebox_override("normal", HudStyle.piece("barFill", HudStyle.color("accent")))
		b.add_theme_stylebox_override("hover", HudStyle.piece("barFill", HudStyle.color("accentLight")))
	b.custom_minimum_size.y = 28 * HudStyle.SCALE
	return b


func _pick(option: String) -> void:
	for q in field:
		farm._state(q).setTo = option
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
