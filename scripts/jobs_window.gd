class_name JobsWindow
extends PanelContainer
## The jobs window (from Unity's JobsWindow; J): on the left every villager, what they're doing right now, their
## health, food and rest, and the work they're set to (Any, Mining, Lumbering, Rest, Farming, Building, Cooking,
## Crafting; changed with the arrows). On the right, what the village keeps in storage (the villagers stop once
## there's this much; − and + change it), the crop rotation, and the work waiting. Built when it opens or the villagers
## change; only its words are refreshed while it's open, so its buttons stay put under a click.

const COL := 370.0
const H := 430.0
const NAME_W := 250.0           ## the table's first column: who
const GAP := 10.0               ## between the table's columns
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
const TABS := ["Jobs", "Job Board", "Storage Rules"]
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
var _board_box: VBoxContainer      ## the job board's rows
var _board_people: VBoxContainer   ## ...and its villagers, to drag
var _board_rows: Array = []        # [{job, pending, doing}]
var _board_cards: Array = []       # [{who, doing, first}]
var _board_shown := ""             ## the order and who's put on what, as laid out
var _w := 820.0                    ## the pages' size (as big as the screen allows), before the interface's scale
var _h := 430.0
var _cell := 60.0                  ## a job's column
var _people_box: VBoxContainer
var _keep_box: VBoxContainer
var _next_refresh := 0.0
var tab := "Jobs"            ## which page shows: "Jobs" (the villagers and how much of each job), "Job Board" or "Storage Rules"
var _pages := {}             # tab -> its page
var _tab_buttons := {}


func setup(w: World, people: Villagers, farms: Farming) -> void:
	world = w
	villagers = people
	farming = farms
	add_theme_stylebox_override("panel", HudStyle.piece("panelStrong"))
	visible = false


# Q and E step through the tabs (taken before anything in the world hears the E).
func _input(event: InputEvent) -> void:
	var step := HudStyle.tab_step(event, get_viewport()) if visible else 0
	if step != 0:
		show_tab(TABS[posmod(TABS.find(tab) + step, TABS.size())])
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		# (L; not while the map is open: there L shows its sections)
		var map: Control = get_parent().get_node_or_null("WorldMap") as Control
		if event.keycode == KEY_L and not (map != null and map.visible):
			if not visible and Chronicle.active != null and Chronicle.active.happened("intro_started") and not Chronicle.active.happened("village_given"):
				var w := world
				FloatingText.spawn(w, "The village isn't yours to run yet.", w.player.position + Vector2(0, -2.0 * w.px), Color(0.9, 0.85, 0.75))
				get_viewport().set_input_as_handled()
				return
			visible = not visible
			_built_for = "-"
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE and visible:
			visible = false
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_TAB and visible:
			show_tab(TABS[(TABS.find(tab) + 1) % TABS.size()])
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
	for t in TABS:
		var tb := HudStyle.button(t, 12)
		tb.pressed.connect(show_tab.bind(t))
		head.add_child(tb)
		_tab_buttons[t] = tb
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(gap)
	head.add_child(HudStyle.label("L or Esc to close  ·  Q / E switch tabs", 11, "body", HudStyle.color("muted")))
	root.add_child(head)
	# As big as the screen allows: every villager a row, every job a column.
	var view := get_viewport_rect().size / HudStyle.SCALE
	_w = maxf(820.0, view.x * 0.94 - 40.0)
	_h = maxf(430.0, view.y * 0.84 - 110.0)
	_cell = floorf((_w - NAME_W - 40.0 - GAP * JOB_LIST.size()) / JOB_LIST.size())
	var sides := VBoxContainer.new()
	sides.add_theme_constant_override("separation", int(_k(6)))
	root.add_child(sides)
	# ---- The table: the villagers down, the jobs across.
	var left := VBoxContainer.new()
	var heads := HBoxContainer.new()
	heads.add_theme_constant_override("separation", int(_k(GAP)))
	var count := HudStyle.label("VILLAGERS  ·  %d" % villagers.people.size(), 11, "bold", HudStyle.color("faint"))
	count.custom_minimum_size.x = _k(NAME_W + 12.0)
	heads.add_child(count)
	for j in JOB_LIST:
		var h := HudStyle.label(JOB_NAMES[int(j[0])], 12, "bold", HudStyle.color("accentLight"))
		h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		h.custom_minimum_size.x = _k(_cell)
		h.tooltip_text = str(j[1])
		h.mouse_filter = Control.MOUSE_FILTER_STOP
		heads.add_child(h)
	left.add_child(heads)
	var ls := _scroller(_h - 150.0, _w)
	left.add_child(ls[0])
	_people_box = ls[1]
	sides.add_child(left)
	if villagers.people.is_empty():
		_people_box.add_child(HudStyle.label("No villagers yet: build a house with a bed in the village.", 12, "body", HudStyle.color("muted")))
	for p in villagers.people:
		_person_row(p)
	left.add_child(HudStyle.label("The ten boxes: how much of each job they do. The first is none; the more filled, the more often they take it over their other work.   Bars: health · food · rest.", 10, "body", HudStyle.color("faint")))
	# ---- Right: what to keep in storage, then the work waiting.
	var right := VBoxContainer.new()
	sides.add_child(right)
	_pages["Jobs"] = sides
	# (both pages the same size, so the window doesn't change as the tabs are switched)
	var page_size := Vector2(_k(_w), _k(_h + 24.0))
	sides.custom_minimum_size = page_size
	# ---- The other tab: what to keep in storage.
	var rules := VBoxContainer.new()
	rules.add_child(HudStyle.label("KEEP IN STORAGE  ·  the villagers stop once there's this much", 11, "bold", HudStyle.color("faint")))
	rules.custom_minimum_size = page_size
	var ks := _scroller(_h, _w)
	rules.add_child(ks[0])
	var stock: VBoxContainer = ks[1]
	root.add_child(rules)
	_pages["Storage Rules"] = rules
	# ---- The job board: the villagers down the left, to drag; the jobs in the order they're taken.
	var board := HBoxContainer.new()
	board.custom_minimum_size = page_size
	board.add_theme_constant_override("separation", int(_k(14)))
	var who_col := VBoxContainer.new()
	who_col.add_child(HudStyle.label("VILLAGERS  ·  drag one onto a job", 11, "bold", HudStyle.color("faint")))
	var ps := _scroller(_h, 250.0)
	who_col.add_child(ps[0])
	_board_people = ps[1]
	board.add_child(who_col)
	var jobs_col := VBoxContainer.new()
	jobs_col.add_child(HudStyle.label("JOBS  ·  taken from the top down. Whoever's put on a job does it before anything else, whatever their boxes say.", 11, "bold", HudStyle.color("faint")))
	var bs := _scroller(_h, _w - 250.0 - 14.0)
	jobs_col.add_child(bs[0])
	_board_box = bs[1]
	_board_box.add_theme_constant_override("separation", int(_k(6)))
	board.add_child(jobs_col)
	root.add_child(board)
	_pages["Job Board"] = board
	_board_shown = ""
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
	var ws := _scroller(88.0, _w)
	right.add_child(ws[0])
	_pending = HudStyle.label("", 12, "body")
	_pending.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pending.custom_minimum_size.x = _k(_w - 16.0)
	ws[1].add_child(_pending)
	show_tab(tab)
	_refresh()


## Shows the page [param t] ("Jobs" or "Storage Rules").
func show_tab(t: String) -> void:
	tab = t
	if t == "Job Board":
		_lay_board()
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
	# A row of the table: their face, name, what they're doing and their bars; then for every job their skill at it
	# and ten boxes, how much of it they do (the first: none).
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", HudStyle.piece("well"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(_k(GAP)))
	card.add_child(row)
	var who := HBoxContainer.new()
	who.custom_minimum_size.x = _k(NAME_W)
	who.add_theme_constant_override("separation", int(_k(8)))
	row.add_child(who)
	var face := TextureRect.new()
	face.custom_minimum_size = Vector2(_k(46), _k(46))
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	face.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	face.texture = _portrait(p)
	who.add_child(face)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", int(_k(2)))
	who.add_child(col)
	var nm := HudStyle.label("", 13, "bold")
	nm.clip_text = true
	nm.custom_minimum_size.x = _k(40)
	col.add_child(nm)
	var activity := HudStyle.label("", 11, "body", HudStyle.color("muted"))
	activity.clip_text = true
	activity.custom_minimum_size.x = _k(40)
	col.add_child(activity)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", int(_k(6)))
	var bars := [_bar(line), _bar(line), _bar(line)]
	col.add_child(line)
	var traits := HudStyle.label("", 9, "body", HudStyle.color("accentLight"))
	traits.clip_text = true
	traits.custom_minimum_size.x = _k(40)
	traits.mouse_filter = Control.MOUSE_FILTER_STOP
	col.add_child(traits)
	var pips := {}
	var levels := {}
	for j in JOB_LIST:
		var id: int = j[0]
		var cell := VBoxContainer.new()
		cell.custom_minimum_size.x = _k(_cell)
		cell.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cell.add_theme_constant_override("separation", int(_k(3)))
		var lv := HudStyle.label("", 10, "body", HudStyle.color("muted"))
		lv.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(lv)
		var boxes := Pips.new()
		boxes.custom_minimum_size = Vector2(_k(_cell), _k(16))
		boxes.picked.connect(func(n: int):
			Villager.set_weight(p, id, n)
			_refresh())
		cell.add_child(boxes)
		row.add_child(cell)
		pips[id] = boxes
		levels[id] = lv
	_people_box.add_child(card)
	_rows.append({"who": p, "name": nm, "activity": activity, "bars": bars, "pips": pips, "levels": levels, "traits": traits})


## Ten boxes in a row, one of them picked: how much of a job a villager does. The first alone is none of it (shown
## dull red); otherwise they're filled up to the one picked. Clicked, a box is picked ([signal picked]).
class Pips extends Control:
	signal picked(n: int)

	var weight := 10
	var enabled := true
	var _over := -1

	func _ready() -> void:
		mouse_exited.connect(func():
			_over = -1
			queue_redraw())

	func _box(i: int) -> Rect2:
		var gap := maxf(2.0, size.x * 0.02)
		var bw := (size.x - gap * 9.0) / 10.0
		return Rect2(i * (bw + gap), 0, bw, size.y)

	func _gui_input(event: InputEvent) -> void:
		if not enabled:
			return
		if event is InputEventMouseMotion:
			var now := clampi(int(event.position.x / maxf(1.0, size.x) * 10.0), 0, 9)
			if now != _over:
				_over = now
				queue_redraw()
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			picked.emit(clampi(int(event.position.x / maxf(1.0, size.x) * 10.0), 0, 9) + 1)
			accept_event()

	func _draw() -> void:
		var gold := Color(1.0, 0.82, 0.3)
		for i in 10:
			var box := _box(i)
			var c := Color(0.07, 0.05, 0.05, 0.85)
			if not enabled:
				c = Color(0.07, 0.05, 0.05, 0.4)
			elif weight <= 1:
				c = Color(0.62, 0.2, 0.18) if i == 0 else c
			elif i < weight:
				c = gold.darkened(0.45 - 0.045 * i)
			draw_rect(box, c)
			draw_rect(box, Color(gold, 0.18 if not enabled else (0.9 if i == _over else 0.4)), false, 1.0)


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


## What a villager's work comes to, in a few words: "Any work", "Resting", the one or two jobs, or how many.
static func jobs_text(p: Dictionary) -> String:
	var js := Villager.jobs_of(p)
	var could := Villager.JOBS.filter(func(j): return j != Villager.Job.COOKING or Villagers.skill(p, LifeSkills.Skill.COOKING) > 0)
	if js.is_empty():
		return "Resting"
	if could.all(func(j): return js.has(j)):
		return "Any work"
	if js.size() == 1:
		return JOB_NAMES[int(js[0])]
	if js.size() == 2:
		return "%s, %s" % [JOB_NAMES[int(js[0])], JOB_NAMES[int(js[1])]]
	return "%d jobs" % js.size()


# ---- The job board ----

## A villager's card on the job board: dragged onto a job, they're put on it.
class DragCard extends PanelContainer:
	var person: Dictionary
	var face: Texture2D

	func _get_drag_data(_at: Vector2) -> Variant:
		var shown := HBoxContainer.new()
		var pic := TextureRect.new()
		pic.texture = face
		pic.custom_minimum_size = Vector2(40, 40) * HudStyle.SCALE
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		shown.add_child(pic)
		shown.add_child(HudStyle.label(str(person.name), 13, "bold", HudStyle.color("accentLight")))
		set_drag_preview(shown)
		return {"villager": person}


## A job's row on the board: a villager dropped on it is put on it.
class JobRow extends PanelContainer:
	var job := 0
	var dropped := Callable()

	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return data is Dictionary and (data as Dictionary).has("villager")

	func _drop_data(_at: Vector2, data: Variant) -> void:
		dropped.call((data as Dictionary).villager, job)


## Puts [param p] on job [param j] (they do it before anything else), or takes them off whatever they're on (-1).
func put_on(p: Dictionary, j: int) -> void:
	if j < 0:
		p.erase("first")
	else:
		p["first"] = j
	_lay_board()


## Moves job [param j] up the board ([param by] -1) or down it (1).
func move_job(j: int, by: int) -> void:
	var order: Array = villagers.board
	var i := order.find(j)
	var to := clampi(i + by, 0, order.size() - 1)
	if i < 0 or to == i:
		return
	order.remove_at(i)
	order.insert(to, j)
	_lay_board()


# The board laid out: the villagers' cards and the jobs' rows, in order.
func _lay_board() -> void:
	if _board_box == null:
		return
	for c in _board_box.get_children():
		c.queue_free()
	for c in _board_people.get_children():
		c.queue_free()
	_board_rows.clear()
	_board_cards.clear()
	_board_shown = _board_state()
	for p in villagers.people:
		var card := DragCard.new()
		card.person = p
		card.face = _portrait(p)
		card.add_theme_stylebox_override("panel", HudStyle.piece("well"))
		card.mouse_default_cursor_shape = Control.CURSOR_DRAG
		var line := HBoxContainer.new()
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_theme_constant_override("separation", int(_k(8)))
		card.add_child(line)
		var pic := TextureRect.new()
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pic.texture = card.face
		pic.custom_minimum_size = Vector2(_k(40), _k(40))
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		line.add_child(pic)
		var col := VBoxContainer.new()
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_theme_constant_override("separation", 0)
		line.add_child(col)
		col.add_child(HudStyle.label(str(p.name), 13, "bold"))
		var doing := HudStyle.label("", 10, "body", HudStyle.color("muted"))
		doing.clip_text = true
		doing.custom_minimum_size.x = _k(170)
		col.add_child(doing)
		var first := HudStyle.label("", 10, "bold", HudStyle.color("accentLight"))
		col.add_child(first)
		_board_people.add_child(card)
		_board_cards.append({"who": p, "doing": doing, "first": first})
	var n := 0
	for j in villagers.board:
		n += 1
		var id := int(j)
		var row := JobRow.new()
		row.job = id
		row.dropped = put_on
		row.add_theme_stylebox_override("panel", HudStyle.piece("well"))
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", int(_k(8)))
		row.add_child(line)
		line.add_child(HudStyle.label("%d" % n, 14, "pixel", HudStyle.color("faint")))
		for step in [[-1, "▲"], [1, "▼"]]:
			var b := HudStyle.button(str(step[1]), 10, "slot")
			b.custom_minimum_size = Vector2(_k(24), _k(24))
			b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			b.disabled = (int(step[0]) < 0 and n == 1) or (int(step[0]) > 0 and n == villagers.board.size())
			b.pressed.connect(move_job.bind(id, int(step[0])))
			line.add_child(b)
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", int(_k(1)))
		line.add_child(col)
		col.add_child(HudStyle.label(JOB_NAMES[id], 14, "bold", HudStyle.color("accentLight")))
		var pending := HudStyle.label("", 11, "body", HudStyle.color("text"))
		col.add_child(pending)
		var doing := HudStyle.label("", 10, "body", HudStyle.color("muted"))
		col.add_child(doing)
		# Those put on it: each a button that takes them off.
		var on := HBoxContainer.new()
		on.add_theme_constant_override("separation", int(_k(4)))
		on.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		for p in villagers.people:
			if int(p.get("first", -1)) == id:
				var chip := HudStyle.button("%s  ×" % str(p.name), 11, "pill", HudStyle.color("accentLight"))
				chip.tooltip_text = "Take %s off this job" % str(p.name)
				chip.pressed.connect(put_on.bind(p, -1))
				on.add_child(chip)
		if on.get_child_count() == 0:
			on.add_child(HudStyle.label("drop a villager here", 10, "body", HudStyle.color("faint")))
		line.add_child(on)
		_board_box.add_child(row)
		_board_rows.append({"job": id, "pending": pending, "doing": doing})
	_refresh_board()


func _board_state() -> String:
	return "%s|%s|%s" % [villagers.board, villagers.people.map(func(p): return int(p.get("first", -1))), villagers.people.size()]


# What's waiting for each job, who's at it, and what each villager's doing: as it is now.
func _refresh_board() -> void:
	if _board_box == null or tab != "Job Board":
		return
	if _board_state() != _board_shown:
		_lay_board()
		return
	var v := world.village
	var at := {}
	for x in Villager.all:
		if is_instance_valid(x) and x.doing() >= 0:
			at[x.doing()] = (at.get(x.doing(), []) as Array) + [str(x.person.name)]
	var rocks := 0
	var trees := 0
	if v.founded():
		for g in Gatherable.all:
			if is_instance_valid(g) and g.left > 0 and g.foot.distance_to(v.centre()) <= 20.0 * world.px:
				if g.axe: trees += 1
				else: rocks += 1
	for r in _board_rows:
		var text := ""
		match int(r.job):
			Villager.Job.LUMBERING:
				text = "Enough wood in storage: no felling" if Kitchen.stocked(v, "Wood") else "%d trees to fell near the village  ·  wood %d of %d" % [trees, v.stored("Wood"), Kitchen.target("Wood")]
			Villager.Job.MINING:
				text = "Enough stone in storage: no mining" if Kitchen.stocked(v, "Stone") else "%d rocks to mine near the village  ·  stone %d of %d" % [rocks, v.stored("Stone"), Kitchen.target("Stone")]
			Villager.Job.FARMING:
				var ripe := 0
				var bare := 0
				var growing := 0
				if farming != null:
					for p in farming.plots:
						if v.contains(p.pos, 3.0):
							var st := farming.stage(p)
							if st == 2: ripe += 1
							elif st == 0: bare += 1
							else: growing += 1
				var kept := 0
				for k in v.reserve:
					kept += mini(int(v.reserve[k]), v.stored(k))
				text = "%d plots ripe to harvest  ·  %d bare to plant  ·  %d growing  ·  %d seed kept for planting (not eaten, cooked or spoiled)" % [ripe, bare, growing, kept]
			Villager.Job.FISHING:
				var docks := Fishing.active.village_docks().size() if Fishing.active != null else 0
				text = "No dock the villagers can reach (build one by the water, on cleared ground)" if docks == 0 else ("Enough fish in storage: no fishing" if Kitchen.stocked(v, "Fish") else "%d docks to fish  ·  fish %d of %d" % [docks, v.stored("Fish"), Kitchen.target("Fish")])
			Villager.Job.COOKING:
				var dish := Kitchen.next(v)
				text = "Nothing raw to cook" if dish.is_empty() else "%s to cook into %s  ·  %d raw in storage" % [UiKit.resource_name(dish[0]), UiKit.resource_name(dish[1]).to_lower(), v.spare(dish[0])]
			Villager.Job.BUILDING:
				var site := Construction.active
				var pieces := site.pieces.size() - site.drafts() if site != null else 0
				text = "%d pieces ready to build  ·  walls, gates and houses mended as they wear" % pieces
			Villager.Job.CRAFTING:
				text = "Tools, potions and gear at the workbenches, up to what the storage rules keep"
			Villager.Job.HAULING:
				var move := Cellars.active.to_move() if Cellars.active != null else 0
				text = "%d food to carry down to the cellar  ·  whatever's lying about brought in" % move
		(r.pending as Label).text = text
		var names: Array = at.get(int(r.job), [])
		# (and those put on it who aren't at it: what they're doing in its place)
		var elsewhere := []
		for x in Villager.all:
			if is_instance_valid(x) and int(x.person.get("first", -1)) == int(r.job) and not names.has(str(x.person.name)):
				elsewhere.append("%s (%s)" % [x.person.name, x.activity().to_lower()])
		(r.doing as Label).text = (("At it now: " + ", ".join(names)) if not names.is_empty() else "Nobody at it now") + (("   ·   Put on it, not at it yet: " + ", ".join(elsewhere)) if not elsewhere.is_empty() else "")
	for c in _board_cards:
		var p: Dictionary = c.who
		var body: Villager = null
		for x in Villager.all:
			if x.person == p:
				body = x
		(c.doing as Label).text = body.activity() if body != null else "Away"
		var first := int(p.get("first", -1))
		(c.first as Label).text = ("Put on: " + JOB_NAMES[first]) if first > 0 else ""


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
	icon.texture = UiKit.item_icon(e.item) if e.has("item") else UiKit.resource_icon(e.resource)
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
	_refresh_board()
	for r in _rows:
		var p: Dictionary = r.who
		var body: Villager = null
		for v in Villager.all:
			if v.person == p:
				body = v
		r.name.text = "%s%s   Lv %d%s" % ["★ " if p.has("unique") else "", p.name, int(p.get("level", 1)), ("   " + Intimacy.hearts(p)) if p.has("unique") else ""]
		var traits := Traits.shown(p)
		(r.traits as Label).text = "  ·  ".join(traits.map(func(x): return str(x[0])))
		(r.traits as Label).tooltip_text = "\n".join(traits.map(func(x): return "%s: %s" % [x[0], x[2]]))
		for j in JOB_LIST:
			var id: int = j[0]
			var lv := Villagers.skill(p, int(j[2])) if int(j[2]) >= 0 else -1
			var can := not (id == Villager.Job.COOKING and lv <= 0) and Villager.able(p, id)   # (cooking is only for those who can; the elder only some)
			var boxes: Pips = r.pips[id]
			var weight := Villager.weight_of(p, id) if can else 1
			if boxes.weight != weight or boxes.enabled != can:
				boxes.weight = weight
				boxes.enabled = can
				boxes.queue_redraw()
			(r.levels[id] as Label).text = "can't" if not can else (("skill %d" % lv) if lv > 0 else " ")
		r.activity.text = body.activity() if body != null else ("Died" if float(p.get("hp", 1.0)) <= 0.0 else "No bed: waiting for one")
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
