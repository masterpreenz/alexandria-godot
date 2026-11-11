class_name JobsWindow
extends PanelContainer
## The jobs window (from Unity's JobsWindow; J): on the left every villager, what they're doing right now, their
## health, food and rest, and the work they're set to (Any, Mining, Lumbering, Rest, Farming, Building, Cooking,
## Crafting; changed with the arrows). On the right, what the village keeps in storage (the villagers stop once
## there's this much; − and + change it), the crop rotation, and the work waiting. Built when it opens or the villagers
## change; only its words are refreshed while it's open, so its buttons stay put under a click.

const COL := 370.0
const H := 430.0
const RIGHT := 450.0            ## the right side's width: wide enough for either of its pages, so it doesn't grow
const JOB_NAMES := ["Any work", "Mining", "Lumbering", "Rest", "Farming", "Building", "Cooking", "Crafting", "Fishing", "Hauling"]
## The work that can be ticked for a villager, in the order shown: [Job, what it covers, the skill it goes by or -1].
const JOB_LIST := [
	[Villager.Job.LUMBERING, "Felling trees and bringing the wood in", LifeSkills.Skill.LUMBERING],
	[Villager.Job.MINING, "Mining rocks and bringing the stone in", LifeSkills.Skill.MINING],
	[Villager.Job.FARMING, "Planting, watering, weeding and harvesting", LifeSkills.Skill.FARMING],
	[Villager.Job.FISHING, "Fishing at the docks", LifeSkills.Skill.FISHING],
	[Villager.Job.COOKING, "Cooking at fires and the cooking bench", LifeSkills.Skill.COOKING],
	[Villager.Job.BUILDING, "Building, and mending walls and gates", LifeSkills.Skill.BUILDING],
	[Villager.Job.CRAFTING, "Making things at the workbenches", -1],
	[Villager.Job.HAULING, "Bringing in what lies about, food to the cellar", LifeSkills.Skill.STRENGTH],
]
const FILTERS := ["All", "Food", "Potions", "Gear", "Materials"]

var world: World
var villagers: Villagers
var farming: Farming
var _built_for := "-"
var _rows: Array = []        # [{who, name, skills, activity, job, bars: [hp, food, rest]}]
var _keep: Array = []        # [{e, row, line, keep}]
var _chips: Array = []       # [{crop, button}]
var _filter_chips: Array = []
var _query := ""
var _filter := "All"
var _pending: Label
var _waiting_page: VBoxContainer   ## the right side as it stands: the work waiting
var _jobs_page: VBoxContainer      ## ...or the work one villager's set to, to tick
var _editing: Variant = null       ## the villager (Person) whose work is being set, or null
var _people_box: VBoxContainer
var _keep_box: VBoxContainer
var _next_refresh := 0.0
var tab := "Jobs"            ## which page shows: "Jobs" (the villagers and the work waiting) or "Storage Rules"
var _pages := {}             # tab -> its page
var _tab_buttons := {}


func setup(w: World, people: Villagers, farms: Farming) -> void:
	world = w
	villagers = people
	farming = farms
	add_theme_stylebox_override("panel", HudStyle.piece("panelStrong"))
	visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_J:
			visible = not visible
			_built_for = "-"
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE and visible:
			visible = false
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_TAB and visible:
			show_tab("Storage Rules" if tab == "Jobs" else "Jobs")
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	var __t := Time.get_ticks_usec()
	_process_timed(delta)
	Perf.add(&"jobs_window.process", __t)


func _process_timed(_delta: float) -> void:
	if not visible or villagers == null:
		return
	var roster := ""
	for p in villagers.people:
		roster += str(p.name) + "|"
	if roster != _built_for:
		_built_for = roster
		_build()
	if Villager.now() >= _next_refresh:
		_next_refresh = Villager.now() + 0.25
		_refresh()
	reset_size()
	position = ((get_viewport_rect().size - size) / 2.0).round()


func _k(v: float) -> float:
	return v * HudStyle.SCALE


func _scroller(h: float, w := COL) -> Array:
	var s := ScrollContainer.new()
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	s.custom_minimum_size = Vector2(_k(w), _k(h))
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", int(_k(4)))
	s.add_child(box)
	return [s, box]


func _build() -> void:
	for ch in get_children():
		remove_child(ch)
		ch.queue_free()
	_rows.clear()
	_keep.clear()
	_chips.clear()
	_filter_chips.clear()
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", int(_k(6)))
	add_child(root)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", int(_k(8)))
	head.add_child(HudStyle.label("Village", 16, "pixel", HudStyle.color("accentLight")))
	# The tabs.
	_tab_buttons.clear()
	_pages.clear()
	for t in ["Jobs", "Storage Rules"]:
		var tb := HudStyle.button(t, 12)
		tb.pressed.connect(show_tab.bind(t))
		head.add_child(tb)
		_tab_buttons[t] = tb
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(gap)
	head.add_child(HudStyle.label("J or Esc to close  ·  Tab switches", 11, "body", HudStyle.color("muted")))
	root.add_child(head)
	var sides := HBoxContainer.new()
	sides.add_theme_constant_override("separation", int(_k(14)))
	root.add_child(sides)
	# ---- Left: the villagers.
	var left := VBoxContainer.new()
	left.add_child(HudStyle.label("VILLAGERS  ·  %d" % villagers.people.size(), 11, "bold", HudStyle.color("faint")))
	var ls := _scroller(H)
	left.add_child(ls[0])
	_people_box = ls[1]
	sides.add_child(left)
	if villagers.people.is_empty():
		_people_box.add_child(HudStyle.label("No villagers yet: build a house with a bed in the village.", 12, "body", HudStyle.color("muted")))
	for p in villagers.people:
		_person_row(p)
	_people_box.add_child(HudStyle.label("bars: health · food · rest  (hungry, they eat from storage, cooked food first)", 10, "body", HudStyle.color("faint")))
	# ---- Right: what to keep in storage, then the work waiting.
	var right := VBoxContainer.new()
	sides.add_child(right)
	_pages["Jobs"] = sides
	# ---- The other tab: what to keep in storage.
	var rules := VBoxContainer.new()
	rules.add_child(HudStyle.label("KEEP IN STORAGE  ·  the villagers stop once there's this much", 11, "bold", HudStyle.color("faint")))
	var ks := _scroller(H, COL * 2.0 + 14.0)
	rules.add_child(ks[0])
	var stock: VBoxContainer = ks[1]
	root.add_child(rules)
	_pages["Storage Rules"] = rules
	# The crop rotation: what bare plots left to the village are planted with, in turn.
	if farming != null:
		stock.add_child(HudStyle.label("Crop rotation (click to add or remove)", 11, "bold", HudStyle.color("faint")))
		var crops := HBoxContainer.new()
		crops.add_theme_constant_override("separation", int(_k(6)))
		for c in Farming.ORDER:
			var b := HudStyle.button(UiKit.resource_name(c), 11)
			b.pressed.connect(_toggle_crop.bind(c))
			crops.add_child(b)
			_chips.append({"crop": c, "button": b})
		stock.add_child(crops)
	# Search and filters.
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", int(_k(5)))
	var search := LineEdit.new()
	search.placeholder_text = "Search"
	search.text = _query
	search.custom_minimum_size = Vector2(_k(130), _k(26))
	search.add_theme_stylebox_override("normal", HudStyle.piece("well"))
	search.add_theme_stylebox_override("focus", HudStyle.piece("well"))
	search.add_theme_font_size_override("font_size", roundi(_k(12)))
	search.text_changed.connect(func(t: String):
		_query = t
		_lay_keep())
	bar.add_child(search)
	for f in FILTERS:
		var b := HudStyle.button(f, 11)
		b.pressed.connect(_set_filter.bind(f))
		bar.add_child(b)
		_filter_chips.append({"filter": f, "button": b})
	stock.add_child(bar)
	_keep_box = VBoxContainer.new()
	_keep_box.add_theme_constant_override("separation", int(_k(2)))
	stock.add_child(_keep_box)
	for e in _stock_entries():
		_keep_row(e)
	_lay_keep()
	right.custom_minimum_size = Vector2(_k(RIGHT), _k(H + 24))
	_waiting_page = VBoxContainer.new()
	right.add_child(_waiting_page)
	_jobs_page = VBoxContainer.new()
	_jobs_page.add_theme_constant_override("separation", int(_k(4)))
	_jobs_page.custom_minimum_size = Vector2(_k(RIGHT), _k(H))
	_jobs_page.visible = false
	right.add_child(_jobs_page)
	_waiting_page.add_child(HudStyle.label("WORK WAITING", 11, "bold", HudStyle.color("faint")))
	var ws := _scroller(H - 24)
	_waiting_page.add_child(ws[0])
	_pending = HudStyle.label("", 12, "body")
	_pending.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pending.custom_minimum_size.x = _k(COL - 16)
	ws[1].add_child(_pending)
	show_tab(tab)
	# (built again as the roster changed: whoever's work was open stays open, if they're still here)
	edit_jobs(_editing if _editing != null and villagers.people.has(_editing) else null)


## Shows the page [param t] ("Jobs" or "Storage Rules").
func show_tab(t: String) -> void:
	tab = t
	for k in _pages:
		(_pages[k] as Control).visible = k == t
	for k in _tab_buttons:
		(_tab_buttons[k] as Button).modulate = Color.WHITE if k == t else Color(1, 1, 1, 0.55)
	reset_size()


func _bar(parent: Control) -> ColorRect:
	var back := ColorRect.new()
	back.color = Color(0, 0, 0, 0.55)
	back.custom_minimum_size = Vector2(_k(50), _k(5))
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fill := ColorRect.new()
	fill.size = Vector2(_k(50), _k(5))
	back.add_child(fill)
	parent.add_child(back)
	return fill


func _person_row(p: Dictionary) -> void:
	# A card: their face, then their name with the button for their work, what they're doing, their bars, and their
	# skills three to a line.
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", HudStyle.piece("well"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(_k(8)))
	card.add_child(row)
	var face := TextureRect.new()
	face.custom_minimum_size = Vector2(_k(46), _k(46))
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	face.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	face.texture = _portrait(p)
	row.add_child(face)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", int(_k(2)))
	row.add_child(col)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", int(_k(6)))
	col.add_child(top)
	var nm := HudStyle.label("", 13, "bold")
	nm.clip_text = true
	nm.custom_minimum_size.x = _k(40)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(nm)
	# Their work: a button that opens it on the right, to tick.
	var job := HudStyle.button("", 10, "pill", HudStyle.color("accentLight"))
	job.custom_minimum_size = Vector2(_k(104), _k(20))
	job.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	job.clip_text = true
	job.pressed.connect(func():
		if _editing == p: edit_jobs(null)   # (pressed again: back to the work waiting)
		else: edit_jobs(p))
	top.add_child(job)
	var activity := HudStyle.label("", 11, "body", HudStyle.color("muted"))
	activity.clip_text = true
	activity.custom_minimum_size.x = _k(40)
	col.add_child(activity)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", int(_k(6)))
	var bars := [_bar(line), _bar(line), _bar(line)]
	col.add_child(line)
	var skills := GridContainer.new()
	skills.columns = 3
	skills.add_theme_constant_override("h_separation", int(_k(10)))
	skills.add_theme_constant_override("v_separation", 0)
	col.add_child(skills)
	_people_box.add_child(card)
	_rows.append({"who": p, "name": nm, "skills": skills, "shown": "", "activity": activity, "job": job, "bars": bars})


static var _faces := {}


# A villager's face: head and shoulders from their look's standing frame (as when talking with them), by look.
func _portrait(p: Dictionary) -> Texture2D:
	var looks: Array = villagers.d.get("looks", [])
	var look := clampi(int(p.get("look", 0)), 0, maxi(0, looks.size() - 1))
	if _faces.has(look):
		return _faces[look]
	if looks.is_empty():
		return null
	var info: Dictionary = world.sprites[int(looks[look].settings.idleDown)]
	var at := AtlasTexture.new()
	at.atlas = world._texture(info.tex)
	var frame := Rect2i(int(info.rect[0]), int(info.rect[1]), int(info.rect[2]), int(info.rect[3]))
	var used := frame
	var img := at.atlas.get_image() if at.atlas != null else null
	if img != null:
		var r := img.get_region(frame).get_used_rect()
		if r.size.x > 0:
			used = Rect2i(frame.position + r.position, r.size)
	var side := mini(used.size.x, int(used.size.y * 0.5))
	at.region = Rect2(used.position.x + (used.size.x - side) / 2.0, used.position.y, side, side)
	_faces[look] = at
	return at


## What a villager's work comes to, in a few words: "Any work", "Resting", the one job, or how many.
static func jobs_text(p: Dictionary) -> String:
	var js := Villager.jobs_of(p)
	if js.has(Villager.Job.ANY):
		return "Any work"
	if js.is_empty():
		return "Resting"
	if js.size() == 1:
		return JOB_NAMES[int(js[0])]
	if js.size() == 2:
		return "%s, %s" % [JOB_NAMES[int(js[0])], JOB_NAMES[int(js[1])]]
	return "%d jobs" % js.size()


## Opens [param p]'s work on the right, to tick (null: back to the work waiting).
func edit_jobs(p: Variant) -> void:
	_editing = p
	_waiting_page.visible = p == null
	_jobs_page.visible = p != null
	for c in _jobs_page.get_children():
		c.queue_free()
	if p == null:
		_refresh()
		return
	var person: Dictionary = p
	var js := Villager.jobs_of(person)
	var all := js.has(Villager.Job.ANY)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", int(_k(8)))
	head.add_child(HudStyle.label("%s'S WORK" % str(person.name).to_upper(), 11, "bold", HudStyle.color("faint")))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(gap)
	var done := HudStyle.button("Done", 11)
	done.pressed.connect(edit_jobs.bind(null))
	head.add_child(done)
	_jobs_page.add_child(head)
	var hint := HudStyle.label("Tick what they'll do. With all work ticked they take whatever needs doing; tick one or two to keep them to it (a farmer, a fisher).", 11, "body", HudStyle.color("muted"))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = _k(RIGHT - 16)
	_jobs_page.add_child(hint)
	_jobs_page.add_child(_tick("All work", "Whatever needs doing", all, true, func(on: bool):
		person["jobs"] = [Villager.Job.ANY] if on else []
		edit_jobs(person)))
	for j in JOB_LIST:
		var id: int = j[0]
		var lv := Villagers.skill(person, int(j[2])) if int(j[2]) >= 0 else -1
		var can := not (id == Villager.Job.COOKING and lv <= 0)   # (cooking is only for those who can)
		var label: String = JOB_NAMES[id] + (("   %d" % lv) if lv > 0 else "")
		_jobs_page.add_child(_tick(label, str(j[1]) if can else "Can't cook", (all or js.has(id)) and can, can, func(on: bool):
			# (from all work, unticking one leaves the rest ticked; ticking the last one back makes it all work again)
			var now: Array = js.duplicate()
			if all:
				now = JOB_LIST.map(func(e): return int(e[0])).filter(func(e): return e != Villager.Job.COOKING or Villagers.skill(person, LifeSkills.Skill.COOKING) > 0)
			now.erase(id)
			if on:
				now.append(id)
			person["jobs"] = now
			edit_jobs(person)))
	_refresh()


static var _box_icons := {}


# A tick box drawn plainly, so an empty one shows as well as a ticked one: a gold-rimmed square, filled with a tick
# when on; dim when it can't be changed.
static func _box_icon(on: bool, dim: bool) -> Texture2D:
	var key := "%s%s" % [on, dim]
	if not _box_icons.has(key):
		var n := roundi(18 * HudStyle.SCALE)
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		var rim := Color(1.0, 0.82, 0.3, 0.35 if dim else 1.0)
		var fill := Color(1.0, 0.82, 0.3, 0.9) if on else Color(0.1, 0.08, 0.07, 0.9)
		if dim:
			fill.a *= 0.4
		var w := maxi(2, roundi(n / 9.0))
		for y in n:
			for x in n:
				var edge := x < w or y < w or x >= n - w or y >= n - w
				img.set_pixel(x, y, rim if edge else fill)
		if on:
			# (the tick: two strokes, dark on the gold)
			for i in n:
				var t := float(i) / n
				for pt in [Vector2(lerpf(0.22, 0.42, t), lerpf(0.5, 0.74, t)), Vector2(lerpf(0.42, 0.8, t), lerpf(0.74, 0.26, t))]:
					for dx in range(-1, 2):
						for dy in range(-1, 2):
							var px := clampi(roundi(pt.x * n) + dx, 0, n - 1)
							var py := clampi(roundi(pt.y * n) + dy, 0, n - 1)
							img.set_pixel(px, py, Color(0.12, 0.08, 0.05, 0.4 if dim else 1.0))
		_box_icons[key] = ImageTexture.create_from_image(img)
	return _box_icons[key]


# One line of the ticks: a box to tick, its name, and what it covers.
func _tick(title: String, about: String, on: bool, enabled: bool, changed: Callable) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(_k(8)))
	var box := CheckBox.new()
	box.button_pressed = on
	box.disabled = not enabled
	box.text = title
	box.custom_minimum_size = Vector2(_k(150), _k(26))
	box.add_theme_font_override("font", HudStyle.font("bold"))
	box.add_theme_font_size_override("font_size", roundi(_k(12)))
	box.add_theme_color_override("font_color", HudStyle.color("text"))
	box.add_theme_color_override("font_pressed_color", HudStyle.color("accentLight"))
	for icon in ["checked", "unchecked", "checked_disabled", "unchecked_disabled"]:
		box.add_theme_icon_override(icon, _box_icon(icon.begins_with("checked"), icon.ends_with("disabled")))
	box.add_theme_constant_override("h_separation", int(_k(8)))
	box.toggled.connect(changed)
	row.add_child(box)
	var what := HudStyle.label(about, 11, "body", HudStyle.color("muted") if enabled else HudStyle.color("faint"))
	what.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(what)
	return row


func _toggle_crop(c: String) -> void:
	var r := farming.rotation
	if r.has(c):
		if r.size() > 1:
			r.erase(c)
	else:
		r.append(c)
		r.sort_custom(func(a, b): return Farming.ORDER.find(a) < Farming.ORDER.find(b))
	_refresh()


func _set_filter(f: String) -> void:
	_filter = f
	_lay_keep()
	_refresh()


# ---- What can be kept: wood and stone, the fire's dishes, all the workbenches make ----

func _stock_entries() -> Array:
	var list := []
	for r in Kitchen.MATERIALS:
		list.append({"key": r, "resource": r, "name": UiKit.resource_name(r), "kind": "Materials"})
	for r in Kitchen.RECIPES:
		list.append({"key": r[1], "resource": r[1], "raw": r[0], "name": UiKit.resource_name(r[1]), "kind": "Food"})
	var benches: Dictionary = villagers.d.get("workbenches", {})
	for prop in benches:
		for rec in benches[prop].get("recipes", []):
			var key := Villager._recipe_key(rec)
			if list.any(func(e): return e.key == key):
				continue
			if bool(rec.makesResource):
				var r: String = rec.resource
				var kind := "Potions" if r.ends_with("Potion") else ("Food" if UiKit.data.resources.get(r, {}).get("group", "") == "Consumables" else "Materials")
				list.append({"key": key, "resource": r, "recipe": rec, "name": UiKit.resource_name(r), "kind": kind, "made": "made at the %s" % str(benches[prop].title).to_lower()})
			else:
				var it := UiKit.item(rec.item)
				list.append({"key": key, "item": rec.item, "recipe": rec, "name": str(it.get("name", rec.item)), "kind": "Gear", "made": "made at the %s" % str(benches[prop].title).to_lower()})
	return list


func _in_storage(e: Dictionary) -> int:
	return world.village.items.count(e.item) if e.has("item") else world.village.stored(e.resource)


func _keep_row(e: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(_k(6)))
	var icon := TextureRect.new()
	icon.texture = UiKit.sprite_texture(int(UiKit.item(e.item).get("icon", -1))) if e.has("item") else UiKit.resource_icon(e.resource)
	icon.custom_minimum_size = Vector2(_k(22), _k(22))
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(icon)
	var texts := VBoxContainer.new()
	texts.add_theme_constant_override("separation", 0)
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var line := HudStyle.label("", 12, "body")
	line.clip_text = true
	line.custom_minimum_size.x = _k(40)
	texts.add_child(line)
	var note := HudStyle.label("", 10, "body", HudStyle.color("muted"))
	note.clip_text = true
	note.custom_minimum_size.x = _k(40)
	texts.add_child(note)
	row.add_child(texts)
	var step := 10 if e.key in ["Wood", "Stone"] else (1 if e.has("item") else Kitchen.STEP)
	var less := HudStyle.button("−", 12, "slot")
	less.custom_minimum_size = Vector2(_k(26), _k(24))
	less.pressed.connect(_set_keep.bind(e.key, -step))
	row.add_child(less)
	var keep := HudStyle.label("", 12, "bold", HudStyle.color("accentLight"))
	keep.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	keep.custom_minimum_size.x = _k(76)
	row.add_child(keep)
	var more := HudStyle.button("+", 12, "slot")
	more.custom_minimum_size = Vector2(_k(26), _k(24))
	more.pressed.connect(_set_keep.bind(e.key, step))
	row.add_child(more)
	_keep_box.add_child(row)
	_keep.append({"e": e, "row": row, "line": line, "note": note, "keep": keep})


func _set_keep(key: String, by: int) -> void:
	Kitchen.set_target(key, Kitchen.target(key) + by)
	_refresh()


# The keep list's rows that match the search and the filter.
func _lay_keep() -> void:
	var q := _query.strip_edges().to_lower()
	for k in _keep:
		k.row.visible = (_filter == "All" or k.e.kind == _filter) and (q == "" or str(k.e.name).to_lower().contains(q))


func _refresh() -> void:
	for r in _rows:
		var p: Dictionary = r.who
		var body: Villager = null
		for v in Villager.all:
			if v.person == p:
				body = v
		r.name.text = "%s   Lv %d" % [p.name, int(p.get("level", 1))]
		var sk := []
		for i in Villagers.SKILL_NAMES.size():
			var lv := Villagers.skill(p, i)
			if lv > 0:
				sk.append("%s %d" % [Villagers.SKILL_NAMES[i], lv])
		var skills_now := "|".join(sk)
		if skills_now != r.shown:
			r.shown = skills_now
			for c in r.skills.get_children():
				c.queue_free()
			for text in (sk if not sk.is_empty() else ["no skills yet"]):
				var l := HudStyle.label(str(text), 9, "body", HudStyle.color("muted"))
				l.custom_minimum_size.x = _k(78)
				r.skills.add_child(l)
		r.activity.text = body.activity() if body != null else ("Died" if float(p.get("hp", 1.0)) <= 0.0 else "No bed: waiting for one")
		r.job.text = jobs_text(p) + ("  ◀" if _editing == p else "")
		var frac := clampf(float(p.get("hp", 0.0)) / maxf(1.0, float(p.get("maxHp", 1.0))), 0.0, 1.0)
		_set_bar(r.bars[0], frac, Color(0.55, 0.85, 0.4) if frac > 0.6 else (Color(0.95, 0.72, 0.27) if frac > 0.3 else Color(0.9, 0.33, 0.24)))
		var fed := clampf(float(p.get("hunger", 0.0)) / 100.0, 0.0, 1.0)
		_set_bar(r.bars[1], fed, Color(0.95, 0.66, 0.3) if fed > 0.35 else Color(0.9, 0.33, 0.24))
		_set_bar(r.bars[2], clampf(float(p.get("energy", 0.0)) / 100.0, 0.0, 1.0), Color(0.45, 0.65, 1.0))
	var accent := HudStyle.color("accent")
	for c in _chips:
		var on := farming.rotation.has(c.crop)
		c.button.modulate = Color(accent.r * 1.4, accent.g * 1.4, accent.b * 1.4) if on else Color(1, 1, 1, 0.5)
	for c in _filter_chips:
		c.button.modulate = Color(accent.r * 1.4, accent.g * 1.4, accent.b * 1.4) if c.filter == _filter else Color(1, 1, 1, 0.7)
	var v := world.village
	for k in _keep:
		if not k.row.visible:
			continue
		var e: Dictionary = k.e
		var target := Kitchen.target(e.key)
		var have := _in_storage(e)
		var note := ""
		if e.key in Kitchen.MATERIALS:
			var doing := "felling" if e.key == "Wood" else "mining"
			note = ("enough: no " + doing) if Kitchen.stocked(v, e.key) else (doing + " on")
			k.keep.text = "keep %d" % target if target > 0 else "none"
		elif e.has("raw"):
			note = "%d %s to cook" % [v.stored(e.raw), UiKit.resource_name(e.raw).to_lower()]
			k.keep.text = "keep %d" % target if target > 0 else "don't cook"
		else:
			var can_make := true
			for c in e.recipe.cost:
				if v.stored(c.resource) < int(c.amount):
					can_make = false
			note = str(e.made) + (", short of materials" if target > have and not can_make else "")
			k.keep.text = "keep %d" % target if target > 0 else "don't make"
		k.line.text = "%s: %d in storage" % [e.name, have]
		k.note.text = note
	_pending.text = "\n".join(_waiting())


func _set_bar(fill: ColorRect, frac: float, c: Color) -> void:
	fill.size.x = _k(50) * frac
	fill.color = c


# The work waiting: rocks and trees near the village and how many are worked, farm plots, building, cooking, and the
# village's messages.
func _waiting() -> Array:
	var v := world.village
	var rocks := 0
	var trees := 0
	var mining := 0
	var felling := 0
	if v.founded():
		for g in Gatherable.all:
			if not is_instance_valid(g) or g.left <= 0 or g.foot.distance_to(v.centre()) > 20.0 * world.px:
				continue
			if g.axe: trees += 1
			else: rocks += 1
	for g in Villager.claimed:
		if is_instance_valid(g):
			if g.axe: felling += 1
			else: mining += 1
	var lines := [
		"Rocks to mine near the village: %d  ·  being mined: %d" % [rocks, mining],
		"Trees to fell near the village: %d  ·  being felled: %d" % [trees, felling],
	]
	if farming != null:
		var ripe := 0
		var bare := 0
		for p in farming.plots:
			if not v.contains(p.pos):
				continue
			var st := farming.stage(p)
			if st == 2: ripe += 1
			elif st == 0: bare += 1
		if ripe + bare > 0:
			lines.append("Farm plots ripe: %d  ·  bare: %d  ·  seed potatoes in storage: %d" % [ripe, bare, v.stored("Potato")])
	var site := Construction.active
	if site != null and not site.pieces.is_empty():
		lines.append("Construction: %d pieces ready  ·  %d drafts (not started)  ·  being built: %d" % [site.pieces.size() - site.drafts(), site.drafts(), Villager.building.size()])
	var dish := Kitchen.next(v)
	var cooks := Villager.all.filter(func(x): return x.state == Villager.State.COOK or x.state == Villager.State.TO_COOK).size()
	if not dish.is_empty() or cooks > 0:
		lines.append("Cooking: %s  ·  cooks at the fire: %d" % [(UiKit.resource_name(dish[1]).to_lower() + " next") if not dish.is_empty() else "nothing raw to cook", cooks])
	for l in VillageLog.lines():
		lines.append("! " + str(l))
	return lines
