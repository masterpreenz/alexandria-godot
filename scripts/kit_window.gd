class_name KitWindow
extends PanelContainer
## Someone's adventure kit (Kit on their row in the party window, or on their page in the Character & Bag window):
## what they mean to carry on the road. At the top the presets (Adventurer, Gatherer, Light, Empty; Custom once it's
## changed by hand), then a row for each thing with its count (- and +, shift for five at a time, x to take it out), and
## a picker to add something. A companion's "Restock at home" has them do it on their own each time they're back in the
## village; "Restock now" does it there and then (in the village). Esc or the cross closes it.

const ABOUT := {
	"Adventurer": "For the road: 5 health potions, 5 mana potions, 10 things to eat and 2 water pouches.",
	"Gatherer": "For a day's work: 5 things to eat, a water pouch and a set of tools.",
	"Light": "Travelling light: 3 things to eat and 2 health potions.",
	"Empty": "Carries nothing: everything in the bag goes into storage at home.",
	"Custom": "Your own: changed by hand from a preset.",
}

static var active: KitWindow

var miko: Miko
var person: Dictionary = {}       ## whose kit ({} the one played)
var back_to_party := false        ## opened from the party window: back to it on closing
var _box: VBoxContainer


func setup(who: Miko) -> void:
	miko = who
	active = self
	add_theme_stylebox_override("panel", HudStyle.piece("panelStrong"))
	visible = false


func _k(v: float) -> float:
	return v * HudStyle.SCALE


## Opens on [param p]'s kit ({} the one played's).
func open_for(p: Dictionary, from_party := true) -> void:
	if miko.locked:
		return
	person = p
	back_to_party = from_party
	Kit.of(p)
	if PartyWindow.active != null:
		PartyWindow.active.close()
	_build()
	visible = true
	move_to_front()


func close() -> void:
	if not visible:
		return
	visible = false
	if back_to_party and PartyWindow.active != null and Party.active != null:
		PartyWindow.active.open()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey and event.pressed and not event.echo) or HudStyle.typing(get_viewport()):
		return
	if event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	var __t := Time.get_ticks_usec()
	_process_timed(delta)
	Perf.add(&"kit_window.process", __t)


func _process_timed(_delta: float) -> void:
	# (stepped aside for a talk, or they've left the party)
	if visible and (miko.locked or (not person.is_empty() and (Party.active == null or not Party.active.has_member(person)))):
		visible = false


func _name() -> String:
	return Playable.name_now() if person.is_empty() else str(person.get("name", "?"))


func _build() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", roundi(_k(8)))
	add_child(_box)
	_fill()


## Everything shown from the kit as it is now.
func _fill() -> void:
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	var k := Kit.of(person)
	var head := HBoxContainer.new()
	_box.add_child(head)
	var title := HudStyle.label("Kit: %s" % _name(), 18, "bold", HudStyle.color("accentLight"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var x := HudStyle.button("x", 12)
	x.custom_minimum_size = Vector2(_k(26), _k(24))
	x.pressed.connect(close)
	head.add_child(x)
	# The presets.
	var pr := HBoxContainer.new()
	pr.add_theme_constant_override("separation", roundi(_k(4)))
	_box.add_child(pr)
	var on := str(k.get("preset", "Custom"))
	for id in Kit.ORDER + ["Custom"]:
		var b := _pill(id, id == on, 88)
		if id == "Custom":
			b.disabled = on != "Custom"
		else:
			b.pressed.connect(func():
				Kit.use_preset(k, id)
				_fill())
		pr.add_child(b)
	var about := HudStyle.label(str(ABOUT.get(on, ABOUT.Custom)), 11, "body", HudStyle.color("muted"))
	about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	about.custom_minimum_size.x = _k(460)
	_box.add_child(about)
	# The rows.
	var well := PanelContainer.new()
	well.add_theme_stylebox_override("panel", HudStyle.piece("well"))
	_box.add_child(well)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", roundi(_k(4)))
	rows.custom_minimum_size = Vector2(_k(460), _k(150))
	well.add_child(rows)
	var bag: Bag = miko.bag if person.is_empty() else Companions.pack_of(person)
	if (k.get("rows", []) as Array).is_empty():
		rows.add_child(HudStyle.label("Nothing: everything goes into storage at home.", 12, "body", HudStyle.color("faint")))
	for r in k.get("rows", []):
		rows.add_child(_row(k, str(r[0]), int(r[1]), Kit.carried(bag, str(r[0])) if bag != null else 0))
	# Adding something.
	var add_row := HBoxContainer.new()
	add_row.add_theme_constant_override("separation", roundi(_k(6)))
	_box.add_child(add_row)
	var choices := _choices(k)
	var pick := [choices[0][0] if not choices.is_empty() else ""]
	var dd := _dropdown(choices, 300, func(id): pick[0] = str(id))
	add_row.add_child(dd)
	var add := HudStyle.button("+ Add", 11)
	add.custom_minimum_size = Vector2(_k(80), _k(22))
	add.disabled = choices.is_empty()
	add.pressed.connect(func():
		if pick[0] != "":
			Kit.set_count(k, pick[0], 1)
			_fill())
	add_row.add_child(add)
	# At home.
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", roundi(_k(8)))
	_box.add_child(foot)
	if not person.is_empty():
		var auto := _pill("Restock at home: " + ("on" if bool(k.get("auto", true)) else "off"), bool(k.get("auto", true)), 170)
		auto.pressed.connect(func():
			k["auto"] = not bool(k.get("auto", true))
			_fill())
		foot.add_child(auto)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(gap)
	var now := HudStyle.button("Restock now", 11)
	now.custom_minimum_size = Vector2(_k(110), _k(22))
	now.disabled = not at_home()
	now.tooltip_text = "In the village: what's not in the kit into storage, then topped up from it." if at_home() else "Only in the village, by its storage."
	now.pressed.connect(func():
		Kit.restock_now(person)
		_fill())
	foot.add_child(now)
	var note := HudStyle.label("At home, anything not in the kit goes into storage, then storage tops the bag up. Shift with - or + for five.", 10, "body", HudStyle.color("faint"))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = _k(460)
	_box.add_child(note)
	reset_size()
	var screen := get_viewport().get_visible_rect().size
	position = ((screen - size) * 0.5).round()


## Whether they're in the village now, where its storage is to hand.
func at_home() -> bool:
	var w := miko.world
	var who: Node2D = miko if person.is_empty() else Companions.body_of(person)
	return who != null and w.village.founded() and w.village.contains(who.position)


# One thing in the kit: its name, what's carried of it, - count +, and x.
func _row(k: Dictionary, what: String, n: int, has: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", roundi(_k(6)))
	var icon := ChestWindow.Cell.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.custom_minimum_size = Vector2(_k(26), _k(26))
	if UiKit.data.items.has(what):
		icon.show_item(what)
	elif what != Kit.FOOD:
		icon.show_stack(what, 0, Color.WHITE)
		icon._count = ""
	else:
		icon.show_stack("Meal", 0, Color.WHITE)
		icon._count = ""
	row.add_child(icon)
	var nm := HudStyle.label(Kit.label(what), 13, "bold")
	nm.custom_minimum_size.x = _k(180)
	row.add_child(nm)
	var carried := HudStyle.label("has %d" % has, 11, "body", HudStyle.color("green") if has >= n else HudStyle.color("muted"))
	carried.custom_minimum_size.x = _k(70)
	row.add_child(carried)
	var minus := HudStyle.button("-", 12)
	minus.custom_minimum_size = Vector2(_k(26), _k(22))
	minus.pressed.connect(func():
		Kit.set_count(k, what, maxi(1, n - (5 if Input.is_key_pressed(KEY_SHIFT) else 1)))
		_fill())
	row.add_child(minus)
	var count := HudStyle.label(str(n), 13, "pixel")
	count.custom_minimum_size.x = _k(30)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(count)
	var plus := HudStyle.button("+", 12)
	plus.custom_minimum_size = Vector2(_k(26), _k(22))
	plus.pressed.connect(func():
		Kit.set_count(k, what, mini(99, n + (5 if Input.is_key_pressed(KEY_SHIFT) else 1)))
		_fill())
	row.add_child(plus)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(gap)
	var x := HudStyle.button("x", 11, "pill", HudStyle.color("coral"))
	x.custom_minimum_size = Vector2(_k(26), _k(22))
	x.pressed.connect(func():
		Kit.set_count(k, what, 0)
		_fill())
	row.add_child(x)
	return row


# What could be added: food of any kind, then each consumable, material and piece of gear not in the kit yet.
func _choices(k: Dictionary) -> Array:
	var out := []
	if Kit.wants(k, Kit.FOOD) == 0:
		out.append([Kit.FOOD, Kit.label(Kit.FOOD)])
	for group in ["Consumables", "Materials"]:
		for r in Bag.RESOURCES:
			if Bag.RETIRED.has(r) or not Bag.slotted(r) or Kit.wants(k, r) > 0:
				continue
			if str(UiKit.data.resources.get(r, {}).get("group", "")) == group:
				out.append([r, "%s  (%s)" % [UiKit.resource_name(r), "food & drink" if group == "Consumables" else "material"]])
	for it in UiKit.data.items:
		if Kit.wants(k, str(it)) == 0:
			out.append([str(it), "%s  (gear)" % str(UiKit.item(str(it)).get("name", it))])
	return out


func _pill(text: String, on: bool, w: float) -> Button:
	var b := HudStyle.button(text, 11)
	b.custom_minimum_size = Vector2(_k(w), _k(22))
	var tint := Color(1.45, 1.2, 0.75) if on else Color.WHITE
	b.add_theme_stylebox_override("normal", HudStyle.piece("pill", tint))
	b.add_theme_stylebox_override("disabled", HudStyle.piece("pill", Color(tint.r, tint.g, tint.b, 0.4)))
	var c := HudStyle.color("accentLight") if on else HudStyle.color("text")
	for key in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(key, c)
	return b


# A drop-down in the HUD's look: [param items] as [id, label].
func _dropdown(items: Array, w: float, picked: Callable) -> OptionButton:
	var o := OptionButton.new()
	o.focus_mode = Control.FOCUS_NONE
	o.custom_minimum_size = Vector2(_k(w), _k(22))
	o.fit_to_longest_item = false
	o.clip_text = true
	for key in ["normal", "hover", "pressed", "disabled", "focus"]:
		o.add_theme_stylebox_override(key, HudStyle.piece("well", Color(1.1, 1.08, 1.0) if key == "hover" else Color.WHITE))
	var f := HudStyle.font("body")
	if f != null:
		o.add_theme_font_override("font", f)
	o.add_theme_font_size_override("font_size", roundi(_k(11)))
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		o.add_theme_color_override(key, HudStyle.color("text"))
	var pop := o.get_popup()
	pop.add_theme_stylebox_override("panel", HudStyle.piece("panelStrong"))
	if f != null:
		pop.add_theme_font_override("font", f)
	pop.add_theme_font_size_override("font_size", roundi(_k(12)))
	pop.add_theme_color_override("font_color", HudStyle.color("text"))
	pop.add_theme_color_override("font_hover_color", HudStyle.color("accentLight"))
	for i in items.size():
		o.add_item(str(items[i][1]))
		o.set_item_metadata(i, items[i][0])
	if not items.is_empty():
		o.select(0)
	o.item_selected.connect(func(i: int): picked.call(o.get_item_metadata(i)))
	return o
