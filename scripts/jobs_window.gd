class_name JobsWindow
extends PanelContainer
## The jobs window (from Unity's JobsWindow; J): on the left every villager, what they're doing right now, their
## health, food and rest, and the work they're set to (Any, Mining, Lumbering, Rest, Farming, Building, Cooking,
## Crafting; changed with the arrows). On the right, what the village keeps in storage (the villagers stop once
## there's this much; − and + change it), the crop rotation, and the work waiting. Built when it opens or the villagers
## change; only its words are refreshed while it's open, so its buttons stay put under a click.

const COL := 370.0
const H := 430.0
const JOB_NAMES := ["Any work", "Mining", "Lumbering", "Rest", "Farming", "Building", "Cooking", "Crafting"]
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
	right.add_child(HudStyle.label("WORK WAITING", 11, "bold", HudStyle.color("faint")))
	var ws := _scroller(H - 24)
	right.add_child(ws[0])
	_pending = HudStyle.label("", 12, "body")
	_pending.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pending.custom_minimum_size.x = _k(COL - 16)
	ws[1].add_child(_pending)
	show_tab(tab)
	_refresh()


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
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(_k(8)))
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 0)
	var nm := HudStyle.label("", 13, "bold")
	nm.clip_text = true
	nm.custom_minimum_size.x = _k(40)
	col.add_child(nm)
	var skills := HudStyle.label("", 9, "body", HudStyle.color("muted"))
	skills.clip_text = true
	skills.custom_minimum_size.x = _k(40)
	col.add_child(skills)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", int(_k(6)))
	var bars := [_bar(line), _bar(line), _bar(line)]
	col.add_child(line)
	var activity := HudStyle.label("", 11, "body", HudStyle.color("muted"))
	activity.clip_text = true
	activity.custom_minimum_size.x = _k(40)
	col.add_child(activity)
	row.add_child(col)
	# The job choice: ◀ Mining ▶
	var back := HudStyle.button("◀", 12, "slot")
	back.custom_minimum_size = Vector2(_k(26), _k(26))
	back.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	back.pressed.connect(_step_job.bind(p, -1))
	row.add_child(back)
	var job := HudStyle.label("", 12, "bold", HudStyle.color("accentLight"))
	job.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	job.custom_minimum_size.x = _k(76)
	job.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(job)
	var on := HudStyle.button("▶", 12, "slot")
	on.custom_minimum_size = Vector2(_k(26), _k(26))
	on.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	on.pressed.connect(_step_job.bind(p, 1))
	row.add_child(on)
	_people_box.add_child(row)
	_rows.append({"who": p, "name": nm, "skills": skills, "activity": activity, "job": job, "bars": bars})


func _step_job(p: Dictionary, by: int) -> void:
	var n := JOB_NAMES.size()
	p.job = ((int(p.get("job", 0)) + by) % n + n) % n
	# Cooking is only for those who can.
	if p.job == Villager.Job.COOKING and Villagers.skill(p, LifeSkills.Skill.COOKING) <= 0:
		p.job = ((int(p.job) + by) % n + n) % n
	_refresh()


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
		r.skills.text = "  ·  ".join(sk) if not sk.is_empty() else "no skills yet"
		r.activity.text = body.activity() if body != null else ("Died" if float(p.get("hp", 1.0)) <= 0.0 else "No bed: waiting for one")
		r.job.text = JOB_NAMES[clampi(int(p.get("job", 0)), 0, JOB_NAMES.size() - 1)]
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
