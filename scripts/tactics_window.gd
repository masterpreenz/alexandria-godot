class_name TacticsWindow
extends PanelContainer
## A companion's tactics (the Tactics button on their row in the party window): how they fight beside the one played.
## At the top the presets (Melee, Ranged, Defender, Support; Custom once anything's changed by hand). Then their
## stance: close in or keep their distance, how freely they cast, how much mana they keep back for heals and shields,
## whether they step out of a strip a monster has marked, and whom they look after first. Then their rules, tried top
## to bottom in a fight: "when this, do that", each with how often it may come round; dragged up or down (or moved
## with the arrows), added, taken away, switched off. A rule naming a spell they don't know is greyed and passed over.
## Esc (or P, or the cross) closes it, back to the party window.

const VALUES := {"pct": [5, 10, 15, 20, 25, 30, 35, 40, 50, 60, 70, 80, 90], "count": [1, 2, 3, 4, 5, 6]}

static var active: TacticsWindow

var miko: Miko
var person: Dictionary = {}
var dragging := -1                ## the rule being dragged, or -1 (the scenarios read it)
var _title: Label
var _presets: HBoxContainer
var _about: Label
var _stance: GridContainer
var _rules: VBoxContainer
var _scroll: ScrollContainer
var _rows: Array[RuleRow] = []


func setup(who: Miko) -> void:
	miko = who
	active = self
	add_theme_stylebox_override("panel", HudStyle.piece("panelStrong"))
	visible = false


func _k(v: float) -> float:
	return v * HudStyle.SCALE


## Opens on [param p]'s tactics (the party window steps aside meanwhile).
func open_for(p: Dictionary) -> void:
	if miko.locked:
		return
	person = p
	Tactics.of(p)
	if PartyWindow.active != null:
		PartyWindow.active.close()
	_build()
	visible = true
	move_to_front()


func close() -> void:
	if not visible:
		return
	visible = false
	if PartyWindow.active != null and Party.active != null:
		PartyWindow.active.open()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey and event.pressed and not event.echo) or HudStyle.typing(get_viewport()):
		return
	if event.keycode == KEY_ESCAPE or event.keycode == KEY_P:
		close()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	var __t := Time.get_ticks_usec()
	_process_timed(delta)
	Perf.add(&"tactics_window.process", __t)


func _process_timed(_delta: float) -> void:
	# (stepped aside for a talk, or they've left the party)
	if visible and (miko.locked or Party.active == null or not Party.active.has_member(person)):
		visible = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		dragging = -1
		for r in _rows:
			r.mark = 0
			r.queue_redraw()


func _build() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_rows.clear()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", roundi(_k(8)))
	add_child(box)
	# The head: whose tactics, and the cross.
	var head := HBoxContainer.new()
	box.add_child(head)
	_title = HudStyle.label("Tactics: %s" % str(person.get("name", "")), 18, "bold", HudStyle.color("accentLight"))
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	var x := HudStyle.button("x", 12)
	x.custom_minimum_size = Vector2(_k(26), _k(24))
	x.pressed.connect(close)
	head.add_child(x)
	# The presets.
	var pr := HBoxContainer.new()
	pr.add_theme_constant_override("separation", roundi(_k(6)))
	box.add_child(pr)
	pr.add_child(_heading("Preset", 70))
	_presets = HBoxContainer.new()
	_presets.add_theme_constant_override("separation", roundi(_k(4)))
	pr.add_child(_presets)
	_about = HudStyle.label("", 11, "body", HudStyle.color("muted"))
	_about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_about.custom_minimum_size.x = _k(820)
	box.add_child(_about)
	# The stance.
	box.add_child(_heading("Stance", 0))
	var well := PanelContainer.new()
	well.add_theme_stylebox_override("panel", HudStyle.piece("well"))
	box.add_child(well)
	_stance = GridContainer.new()
	_stance.columns = 3
	_stance.add_theme_constant_override("h_separation", roundi(_k(12)))
	_stance.add_theme_constant_override("v_separation", roundi(_k(5)))
	well.add_child(_stance)
	# The rules.
	var rh := HBoxContainer.new()
	box.add_child(rh)
	var rt := _heading("Rules (tried from the top; drag to reorder)", 0)
	rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rh.add_child(rt)
	var add := HudStyle.button("+ Add rule", 11)
	add.custom_minimum_size = Vector2(_k(96), _k(24))
	add.pressed.connect(add_rule)
	rh.add_child(add)
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(_k(840), _k(318))
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(_scroll)
	_rules = VBoxContainer.new()
	_rules.add_theme_constant_override("separation", roundi(_k(3)))
	_rules.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_rules)
	var foot := HudStyle.label("Weights: Rarely (once in a while, sometimes passed over) to Always (whenever it holds). The first rule that holds and can be done is done.", 10, "body", HudStyle.color("faint"))
	foot.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	foot.custom_minimum_size.x = _k(820)
	box.add_child(foot)
	_fill()
	reset_size()
	var screen := get_viewport().get_visible_rect().size
	position = ((screen - size) * 0.5).round()


# Everything shown from their tactics as they are now.
func _fill() -> void:
	var tac := Tactics.of(person)
	for c in _presets.get_children():
		_presets.remove_child(c)
		c.queue_free()
	var on := str(tac.get("preset", "custom"))
	for p in Tactics.data().get("presets", []):
		var id := str(p.id)
		var b := _pill(str(p.label), id == on, 92)
		b.pressed.connect(func(): use_preset(id))
		_presets.add_child(b)
	var custom := _pill("Custom", on == "custom", 92)
	custom.disabled = on != "custom"
	_presets.add_child(custom)
	_about.text = str(Tactics.preset(on).get("about", "Your own: changed by hand from a preset.")) if on != "custom" else "Your own: changed by hand from a preset."
	_fill_stance(tac.stance)
	_fill_rules(tac.rules)


func _fill_stance(st: Dictionary) -> void:
	for c in _stance.get_children():
		_stance.remove_child(c)
		c.queue_free()
	var td := Tactics.data()
	_choice("Range", td.get("ranges", []), str(st.get("range", "close")), "range")
	_choice("Skill use", td.get("frequencies", []), str(st.get("frequency", "normal")), "frequency")
	# Mana kept back: a slider.
	_stance.add_child(_heading("Mana kept back", 120))
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", roundi(_k(6)))
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 60
	slider.step = 5
	slider.value = float(st.get("reserve", 0))
	slider.custom_minimum_size = Vector2(_k(200), _k(20))
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.focus_mode = Control.FOCUS_NONE
	var val := HudStyle.label("%d%%" % int(slider.value), 12, "pixel")
	val.custom_minimum_size.x = _k(40)
	slider.value_changed.connect(func(v: float):
		val.text = "%d%%" % int(v)
		set_stance("reserve", int(v), false))
	r.add_child(slider)
	r.add_child(val)
	_stance.add_child(r)
	_stance.add_child(_note("Kept for heals and shields; attack spells leave it be."))
	_choice("Dodge strips", [{"id": "on", "label": "On", "about": "Out of a monster's marked strip before it comes, dropping any spell."},
		{"id": "off", "label": "Off", "about": "They keep at what they're doing (a spell finishes)."}], "on" if bool(st.get("dodge", true)) else "off", "dodge")
	_choice("Look after", td.get("protects", []), str(st.get("protect", "lowest")), "protect")


# A stance setting picked from pills, with what the one picked means.
func _choice(title: String, options: Array, now_id: String, key: String) -> void:
	_stance.add_child(_heading(title, 120))
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", roundi(_k(4)))
	var about := ""
	for o in options:
		var id := str(o.id)
		if id == now_id:
			about = str(o.get("about", ""))
		var b := _pill(str(o.label), id == now_id, 104)
		b.pressed.connect(func():
			if key == "dodge":
				set_stance(key, id == "on", true)
			else:
				set_stance(key, id, true))
		r.add_child(b)
	_stance.add_child(r)
	_stance.add_child(_note(about))


func _fill_rules(rules: Array) -> void:
	for c in _rules.get_children():
		_rules.remove_child(c)
		c.queue_free()
	_rows.clear()
	var st := Companions.stats_for(person)
	for i in rules.size():
		var row := RuleRow.new()
		row.window = self
		row.index = i
		_rules.add_child(row)
		row.build(rules[i], Tactics.usable(st, rules[i]), i == 0, i == rules.size() - 1)
		_rows.append(row)


## A preset chosen: its stance and rules in place of theirs.
func use_preset(id: String) -> void:
	Tactics.use_preset(person, id)
	_fill()


## A stance setting changed (by hand: Custom now).
func set_stance(key: String, value: Variant, refill: bool) -> void:
	Tactics.stance(person)[key] = value
	Tactics.edited(person)
	if refill:
		_fill()
	else:
		_fill_presets_only()


func _fill_presets_only() -> void:
	var tac := Tactics.of(person)
	var on := str(tac.get("preset", "custom"))
	var i := 0
	for p in Tactics.data().get("presets", []):
		_light(_presets.get_child(i) as Button, str(p.id) == on)
		i += 1
	var custom := _presets.get_child(i) as Button
	_light(custom, on == "custom")
	custom.disabled = on != "custom"
	_about.text = "Your own: changed by hand from a preset." if on == "custom" else str(Tactics.preset(on).get("about", ""))


## A rule's setting changed.
func set_rule(i: int, key: String, value: Variant) -> void:
	var rules: Array = Tactics.of(person).rules
	if i < 0 or i >= rules.size():
		return
	var r: Dictionary = rules[i]
	r[key] = value
	if key == "when":
		var c := Tactics.condition(str(value))
		if c.has("value"):
			r["value"] = int(c.get("default", 50))
		else:
			r.erase("value")
	elif key == "do":
		if bool(Tactics.action(str(value)).get("spell", false)):
			r["spell"] = str(r.get("spell", "@attack"))
		else:
			r.erase("spell")
	Tactics.edited(person)
	_fill()


## The rule at [param from] moved to [param to] (the others close up round it).
func move_rule(from: int, to: int) -> void:
	var rules: Array = Tactics.of(person).rules
	if from < 0 or from >= rules.size():
		return
	to = clampi(to, 0, rules.size() - 1)
	if to == from:
		return
	var r: Variant = rules[from]
	rules.remove_at(from)
	rules.insert(to, r)
	Tactics.edited(person)
	_fill()


func add_rule() -> void:
	(Tactics.of(person).rules as Array).append({"when": "inFight", "do": "cast", "spell": "@attack", "weight": 3, "on": true})
	Tactics.edited(person)
	_fill()
	await get_tree().process_frame
	if is_instance_valid(_scroll):
		_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


func remove_rule(i: int) -> void:
	var rules: Array = Tactics.of(person).rules
	if i >= 0 and i < rules.size():
		rules.remove_at(i)
		Tactics.edited(person)
		_fill()


# ---- Bits of the look ----

func _heading(text: String, w: float) -> Label:
	var l := HudStyle.label(text, 12, "bold", HudStyle.color("accent"))
	if w > 0.0:
		l.custom_minimum_size.x = _k(w)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


func _note(text: String) -> Label:
	var l := HudStyle.label(text, 10, "body", HudStyle.color("muted"))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = _k(300)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


func _pill(text: String, on: bool, w: float) -> Button:
	var b := HudStyle.button(text, 11)
	b.custom_minimum_size = Vector2(_k(w), _k(22))
	_light(b, on)
	return b


# A pill lit (the one picked) or not.
func _light(b: Button, on: bool) -> void:
	var tint := Color(1.45, 1.2, 0.75) if on else Color.WHITE
	b.add_theme_stylebox_override("normal", HudStyle.piece("pill", tint))
	b.add_theme_stylebox_override("disabled", HudStyle.piece("pill", Color(tint.r, tint.g, tint.b, 0.4)))
	var c := HudStyle.color("accentLight") if on else HudStyle.color("text")
	for k in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(k, c)


## A drop-down in the HUD's look: [param items] as [id, label]; [param now_id] picked.
func dropdown(items: Array, now_id: Variant, w: float, picked: Callable) -> OptionButton:
	var o := OptionButton.new()
	o.focus_mode = Control.FOCUS_NONE
	o.custom_minimum_size = Vector2(_k(w), _k(22))
	o.fit_to_longest_item = false
	o.clip_text = true
	for k in ["normal", "hover", "pressed", "disabled", "focus"]:
		o.add_theme_stylebox_override(k, HudStyle.piece("well", Color(1.1, 1.08, 1.0) if k == "hover" else Color.WHITE))
	var f := HudStyle.font("body")
	if f != null:
		o.add_theme_font_override("font", f)
	o.add_theme_font_size_override("font_size", roundi(_k(11)))
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		o.add_theme_color_override(k, HudStyle.color("text"))
	var pop := o.get_popup()
	pop.add_theme_stylebox_override("panel", HudStyle.piece("panelStrong"))
	if f != null:
		pop.add_theme_font_override("font", f)
	pop.add_theme_font_size_override("font_size", roundi(_k(12)))
	pop.add_theme_color_override("font_color", HudStyle.color("text"))
	pop.add_theme_color_override("font_hover_color", HudStyle.color("accentLight"))
	var sel := 0
	for i in items.size():
		o.add_item(str(items[i][1]))
		o.set_item_metadata(i, items[i][0])
		if items[i][0] == now_id:
			sel = i
	o.select(sel)
	o.item_selected.connect(func(i: int): picked.call(o.get_item_metadata(i)))
	return o


## One rule: its grip (to drag it by), on or off, when, the value, do, the spell, its weight, up, down, and away.
class RuleRow extends PanelContainer:
	var window: TacticsWindow
	var index := 0
	var mark := 0                 ## where a dragged rule would go: -1 above this, 1 below, 0 not here
	var rule: Dictionary

	func build(r: Dictionary, usable: bool, first: bool, last: bool) -> void:
		rule = r
		var k := HudStyle.SCALE
		add_theme_stylebox_override("panel", HudStyle.piece("tile" if bool(r.get("on", true)) else "slot"))
		mouse_filter = Control.MOUSE_FILTER_PASS
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", roundi(5 * k))
		add_child(row)
		var grip := Grip.new()
		grip.custom_minimum_size = Vector2(14 * k, 22 * k)
		grip.tooltip_text = "Drag to move this rule up or down"
		row.add_child(grip)
		var n := HudStyle.label("%d" % (index + 1), 12, "pixel", HudStyle.color("accent"))
		n.custom_minimum_size.x = 18 * k
		n.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(n)
		var on := bool(r.get("on", true))
		var tog := HudStyle.button("On" if on else "Off", 10)
		tog.custom_minimum_size = Vector2(36 * k, 22 * k)
		tog.pressed.connect(func(): window.set_rule(index, "on", not on))
		row.add_child(tog)
		var td := Tactics.data()
		var conds: Array = td.get("conditions", []).map(func(c): return [str(c.id), str(c.label)])
		var when := str(r.get("when", "always"))
		row.add_child(window.dropdown(conds, when, 168, func(id): window.set_rule(index, "when", id)))
		var vk := str(Tactics.condition(when).get("value", ""))
		if VALUES.has(vk):
			var vals: Array = (VALUES[vk] as Array).map(func(v): return [int(v), ("%d%%" % v) if vk == "pct" else str(v)])
			row.add_child(window.dropdown(vals, int(r.get("value", Tactics.condition(when).get("default", 0))), 58, func(v): window.set_rule(index, "value", v)))
		else:
			row.add_child(_gap(58 * k))
		var arrow := HudStyle.label("->", 12, "bold", HudStyle.color("muted"))
		arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(arrow)
		var acts: Array = td.get("actions", []).map(func(a): return [str(a.id), str(a.label)])
		var act := str(r.get("do", "cast"))
		row.add_child(window.dropdown(acts, act, 168, func(id): window.set_rule(index, "do", id)))
		if bool(Tactics.action(act).get("spell", false)):
			row.add_child(window.dropdown(_spells(), str(r.get("spell", "@attack")), 128, func(id): window.set_rule(index, "spell", id)))
		else:
			row.add_child(_gap(128 * k))
		var ws: Array = []
		for i in (td.get("weights", []) as Array).size():
			ws.append([i + 1, str(td.weights[i].label)])
		row.add_child(window.dropdown(ws, int(r.get("weight", 3)), 74, func(v): window.set_rule(index, "weight", v)))
		for b in [["^", -1, first], ["v", 1, last]]:
			var mv := HudStyle.button(str(b[0]), 11)
			mv.custom_minimum_size = Vector2(24 * k, 22 * k)
			mv.disabled = b[2]
			var by: int = b[1]
			mv.pressed.connect(func(): window.move_rule(index, index + by))
			row.add_child(mv)
		var x := HudStyle.button("x", 11, "pill", HudStyle.color("coral"))
		x.custom_minimum_size = Vector2(24 * k, 22 * k)
		x.tooltip_text = "Take this rule away"
		x.pressed.connect(func(): window.remove_rule(index))
		row.add_child(x)
		# (a spell they don't know: greyed, and passed over in a fight)
		if not usable:
			modulate = Color(1, 1, 1, 0.45)
			tooltip_text = "They don't know this spell: this rule is passed over."
		elif not on:
			modulate = Color(1, 1, 1, 0.7)

	# The spells a rule can name: by kind first, then theirs by name.
	func _spells() -> Array:
		var out: Array = Tactics.data().get("spellKinds", []).map(func(s): return [str(s.id), str(s.label)])
		var st := Companions.stats_for(window.person)
		var named := str(rule.get("spell", ""))
		var known: Array = st.known_spells() if st != null else []
		for sp in known:
			if Tactics.kind_of(str(sp)) != "":
				out.append([str(sp), Companions.spell_name(str(sp))])
		# (one they don't know, kept so the rule says what it names)
		if named != "" and not named.begins_with("@") and not known.has(named):
			out.append([named, Companions.spell_name(named)])
		return out

	func _gap(w: float) -> Control:
		var c := Control.new()
		c.custom_minimum_size = Vector2(w, 1)
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return c

	func _get_drag_data(_at: Vector2) -> Variant:
		var p := PanelContainer.new()
		p.add_theme_stylebox_override("panel", HudStyle.piece("tileOn"))
		p.add_child(HudStyle.label(Tactics.rule_text(rule), 12, "bold"))
		p.modulate = Color(1, 1, 1, 0.85)
		set_drag_preview(p)
		window.dragging = index
		return {"tactic_rule": index}

	func _can_drop_data(at: Vector2, d: Variant) -> bool:
		if not (d is Dictionary and d.has("tactic_rule")):
			return false
		var m := -1 if at.y < size.y * 0.5 else 1
		if m != mark:
			for r in window._rows:
				if r != self and r.mark != 0:
					r.mark = 0
					r.queue_redraw()
			mark = m
			queue_redraw()
		return true

	func _drop_data(at: Vector2, d: Variant) -> void:
		var from := int(d.tactic_rule)
		var to := index if at.y < size.y * 0.5 else index + 1
		if from < to:
			to -= 1
		window.move_rule(from, to)

	func _draw() -> void:
		if mark == 0:
			return
		var y := 1.0 if mark < 0 else size.y - 1.0
		draw_line(Vector2(0, y), Vector2(size.x, y), HudStyle.color("accent"), 3.0 * HudStyle.SCALE)


## What a rule's dragged by: three short lines.
class Grip extends Control:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
		mouse_default_cursor_shape = Control.CURSOR_MOVE

	func _draw() -> void:
		var c := HudStyle.color("muted")
		for i in 3:
			var y := size.y * 0.5 + (i - 1) * 5.0 * HudStyle.SCALE
			draw_line(Vector2(2, y), Vector2(size.x - 2, y), c, 2.0 * HudStyle.SCALE)
