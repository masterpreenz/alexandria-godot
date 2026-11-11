class_name RumorsWindow
extends PanelContainer
## The rumors journal (K): the rumors Miko's heard down the left (those still open first), and the one picked on the
## right: who told it and when, what's known of it so far a step at a time (nothing of what comes of it), whether
## it's tracked on the maps, and her own notes on it, typed in and kept. Miko stands still while it's open (she'd
## walk as the notes were typed).

var rumors: Rumors
var miko: Miko
var chosen := ""
var _notes: TextEdit
var _was_locked := false


func setup(r: Rumors, who: Miko) -> void:
	rumors = r
	miko = who
	add_theme_stylebox_override("panel", HudStyle.piece("panelStrong"))
	visible = false
	rumors.changed.connect(func():
		if visible:
			_build())


func _k(v: float) -> float:
	return v * HudStyle.SCALE


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_K and (visible or not miko.locked):
			if visible: close()
			else: open()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE and visible:
			close()
			get_viewport().set_input_as_handled()


func open() -> void:
	_was_locked = miko.locked
	miko.locked = true
	visible = true
	move_to_front()
	_build()


func close() -> void:
	if not visible:
		return
	visible = false
	miko.locked = _was_locked
	if _notes != null:
		_notes.release_focus()


func _build() -> void:
	for c in get_children():
		c.queue_free()
	_notes = null
	var ids := rumors.listed()
	if not ids.has(chosen):
		chosen = ids[0] if not ids.is_empty() else ""
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", roundi(_k(12)))
	add_child(row)
	# The list.
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(_k(210), _k(360))
	left.add_theme_constant_override("separation", roundi(_k(4)))
	row.add_child(left)
	left.add_child(HudStyle.label("Rumors", 16, "pixel", HudStyle.color("accentLight")))
	if ids.is_empty():
		var none := HudStyle.label("Nothing heard yet. Villagers with something to tell show it over their heads: talk to them.", 11, "body", HudStyle.color("muted"))
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		none.custom_minimum_size.x = _k(200)
		left.add_child(none)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", roundi(_k(3)))
	scroll.add_child(list)
	for id in ids:
		var st: Dictionary = rumors.heard[id]
		var mark: String = {"open": "", "done": "✓ ", "ignored": "✗ "}.get(st.state, "")
		var b := HudStyle.button(mark + str(rumors.by_id[id].title), 11, "pill", HudStyle.color("accentLight") if id == chosen else (HudStyle.color("text") if st.state == "open" else HudStyle.color("faint")))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.clip_text = true
		b.custom_minimum_size = Vector2(_k(200), _k(26))
		b.pressed.connect(func():
			chosen = id
			_build())
		list.add_child(b)
	# The one picked.
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(_k(380), _k(360))
	right.add_theme_constant_override("separation", roundi(_k(6)))
	row.add_child(right)
	if chosen != "":
		_detail(right)
	reset_size()
	position = ((get_viewport_rect().size - size) / 2.0).round()


func _detail(box: VBoxContainer) -> void:
	var def: Dictionary = rumors.by_id[chosen]
	var st: Dictionary = rumors.heard[chosen]
	box.add_child(HudStyle.label(str(def.title), 15, "bold", HudStyle.color("accentLight")))
	var ch := Chronicle.active
	var how := "Heard from %s  ·  %s" % [str(st.by), ch.date(float(st.heard))]
	if st.state == "done":
		how += "  ·  came to something, %s" % ch.date(float(st.ended))
	elif st.state == "ignored":
		how += "  ·  left too long"
	box.add_child(HudStyle.label(how, 10, "body", HudStyle.color("muted")))
	for l in rumors.lines(chosen):
		var line := HudStyle.label(("✓  " if l[1] else "•  ") + str(l[0]), 12, "body", HudStyle.color("faint") if l[1] else HudStyle.color("text"))
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.custom_minimum_size.x = _k(370)
		box.add_child(line)
	if st.state == "open":
		var has_place := rumors.place_of(st, def, int(st.step)) != Vector2.INF
		var track := HudStyle.button(("✓  Tracked on the map" if bool(st.tracked) else "Track on the map") if has_place else "Nowhere to mark yet", 11)
		track.disabled = not has_place
		track.pressed.connect(func(): rumors.set_tracked(chosen, not bool(st.tracked)))
		box.add_child(track)
	box.add_child(HudStyle.label("Your notes", 11, "bold", HudStyle.color("muted")))
	_notes = TextEdit.new()
	_notes.text = str(st.notes)
	_notes.placeholder_text = "Anything worth remembering about this…"
	_notes.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_notes.custom_minimum_size = Vector2(_k(370), _k(110))
	_notes.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_notes.add_theme_stylebox_override("normal", HudStyle.piece("well"))
	_notes.add_theme_stylebox_override("focus", HudStyle.piece("well"))
	_notes.add_theme_font_override("font", HudStyle.font("body"))
	_notes.add_theme_font_size_override("font_size", roundi(_k(12)))
	_notes.add_theme_color_override("font_color", HudStyle.color("text"))
	var id := chosen
	_notes.text_changed.connect(func(): rumors.set_notes(id, _notes.text))
	box.add_child(_notes)
	box.add_child(HudStyle.label("K or Esc to close", 9, "body", HudStyle.color("faint")))
