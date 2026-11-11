class_name CharacterPanel
extends Control
## The Character & Bag window (from Unity's CharacterPanel; C or I), in the dark-ink HUD style: tabs along the top
## (Character & Bag; Talents with its points, P), then three columns. Left, Miko between her equipment slots (weapon,
## armour, gloves, pants, shoes; off-hand, necklace, two rings, bag), with her level, XP and her weapon. Middle, her
## vitals, her stats or life skills, and a call to spend talent points. Right, the 8 x 8 bag with its filters and,
## under it, the picked thing: what it is, and buttons to use or wear it, drop it or destroy it. The Talents tab
## ([TalentsWindow]) holds the talent web.

const EQUIP_W := 330.0
const STATS_W := 280.0
const CELL := 42.0
const LEFT_SLOTS := [["LeftHand", "Weapon"], ["Armor", "Armor"], ["Gloves", "Gloves"], ["Pants", "Pants"], ["Shoes", "Shoes"]]
const RIGHT_SLOTS := [["RightHand", "Off-hand"], ["Necklace", "Necklace"], ["Ring1", "Ring 1"], ["Ring2", "Ring 2"], ["Bag", "Bag"]]
const FILTERS := [["All", "All"], ["Equipment", "Gear"], ["Consumables", "Food & drink"], ["Materials", "Materials"]]
const USES := {
	"Meal": "Fills 60 hunger.", "Food": "Fills 20 hunger raw; cook it at a bonfire.", "Seed": "Plant with T to grow a tree.",
	"Tea": "Restores 30 energy.", "Hide": "From boars. For crafting.",
	"Crystal": "Dropped by slimes from the mist. Builds cleansing crystals, which clear it away.",
	"Jelly": "From slimes. Too slimy to eat raw: cook it at a bonfire.", "Candy": "Fills 35 hunger.",
	"Potato": "Fills 10 hunger raw. Plant it in a farm plot, or bake it at a bonfire.", "BakedPotato": "Fills 45 hunger.", "Fish": "Raw fish, caught at a fishing dock. Grill it at a fire. Spoils fast.", "GrilledFish": "Fills 50 hunger.", "SmokedFish": "Fills 40 hunger. Keeps for a very long time: food for the winter.",
	"FishSoup": "Fills 60 hunger, and mana and HP come back faster for a while.", "FishStew": "Fills 65 hunger, with more attack and defense for a while.",
	"Bait": "For fishing: each cast takes one. Turns up when harvesting, or make it at the tool workbench.",
	"Bottle": "From the alchemy workbench: potions are made in it.",
	"Carrot": "Fills 12 hunger raw. Plant it in a farm plot, or cook it with raw meat into a stew.",
	"Cabbage": "Fills 15 hunger raw.", "Wheat": "Ground into flour at the alchemy workbench.",
	"Cotton": "For cloth: the workbench's cloth armour is made from it, or spun into fibre.", "Fiber": "Cotton spun into cord at the tool workbench: strings the crystal necklace.", "CabbageSeed": "Plant in a farm plot to grow cabbages.",
	"WheatSeed": "Plant in a farm plot to grow wheat.", "CottonSeed": "Plant in a farm plot to grow cotton.",
	"Flour": "Baked into bread at a bonfire.", "Bread": "Fills 40 hunger, and keeps well.", "CarrotStew": "Fills 55 hunger.",
	"CabbageSoup": "Fills 50 hunger.", "HpPotion": "Restores HP.", "ManaPotion": "Restores mana.",
	"Rabbit": "Grabbed in the wild. Keep it in a rabbit pen to breed more, or butcher it there for raw meat.",
	"Wood": "Used for most buildings.", "Stone": "Paths, walls and the bonfire.", "Gold": "Coins.",
}

var world: World
var miko: Miko
var stats: CharacterStats
var bag: Bag
var talents: TalentsWindow
static var _active: CharacterPanel
var window: PanelContainer
var filter := "All"
var selected := -1          ## the bag slot picked (as shown), or -1
var picked_slot := ""       ## a worn slot picked, or ""
var stats_tab := 0
var _dirty := true
var _destroy_armed := ""
var _shows: Array = []
var _cells: Array = []
var _slot_cells := {}
var _filter_buttons := {}
var _stat_tabs: Array = []
var _labels := {}
var _bars := {}
var _figure: MikoFigure
var _stats_text: RichTextLabel
var _weapon_icon: ChestWindow.Cell
var _pick_icon: ChestWindow.Cell
var _info_lines: Label            ## the picked thing's details (three lines, all of it in the tooltip)
var _action: Button
var _drop: Button
var _destroy: Button
var _points_button: Button
var _badge: Label


func setup(w: World, who: Miko, _hud: Node) -> void:
	world = w
	miko = who
	stats = who.stats
	bag = who.bag
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()
	talents = TalentsWindow.new()
	talents.name = "Talents"
	add_child(talents)
	talents.setup(w, who, self)
	_active = self
	stats.changed.connect(func(): _dirty = true)
	bag.changed.connect(func(): _dirty = true)
	window.visible = false


func _k(v: float) -> float:
	return v * HudStyle.SCALE


## Whether Miko's window (or the talents) is up: the world's E prompts stand aside.
static func up() -> bool:
	return _active != null and is_instance_valid(_active) and _active.any_open()


func is_open() -> bool:
	return window.visible


## Whether it or the talents are up.
func any_open() -> bool:
	return window.visible or talents.visible


func toggle() -> void:
	talents.visible = false
	window.visible = not window.visible
	_dirty = true


func toggle_talents() -> void:
	talents.visible = not talents.visible
	if talents.visible:
		window.visible = false
		talents.refresh()
	talents.hide_tip()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return
	match event.keycode:
		KEY_C, KEY_I:
			toggle()
		KEY_P:
			toggle_talents()
		KEY_ESCAPE:
			if talents.visible: toggle_talents()
			elif window.visible: toggle()
			else: return
		_:
			return
	get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	var __t := Time.get_ticks_usec()
	_process_timed(delta)
	Perf.add(&"character_panel.process", __t)


func _process_timed(_delta: float) -> void:
	if not window.visible:
		return
	if _dirty:
		_dirty = false
		_refresh()
	_vitals()
	window.reset_size()
	window.position = ((get_viewport_rect().size - window.size) / 2.0).round()


# ---- Building it ----

func _well() -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", HudStyle.piece("well"))
	return p


func _gap() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


## The tabs along the top, shared with the talents window: [param here] is 0 (Character & Bag) or 1 (Talents).
func tabs(here: int, points_badge: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(_k(10)))
	var a := HudStyle.button("Character & Bag   C", 14, "pill", HudStyle.color("text") if here == 0 else HudStyle.color("muted"))
	if here == 0:
		a.add_theme_stylebox_override("normal", HudStyle.piece("pill", Color(HudStyle.color("accent"), 0.6)))
	a.pressed.connect(_to_tab.bind(0, here))
	row.add_child(a)
	var b := HudStyle.button("Talents   P", 14, "pill", HudStyle.color("text") if here == 1 else HudStyle.color("muted"))
	if here == 1:
		b.add_theme_stylebox_override("normal", HudStyle.piece("pill", Color(HudStyle.color("accent"), 0.6)))
	b.pressed.connect(_to_tab.bind(1, here))
	row.add_child(b)
	if points_badge:
		_badge = HudStyle.label("", 12, "bold", HudStyle.color("accentLight"))
		row.add_child(_badge)
	row.add_child(_gap())
	var close := HudStyle.button("×", 18, "slot")
	close.custom_minimum_size = Vector2(_k(34), _k(34))
	close.pressed.connect(_close_tab.bind(here))
	row.add_child(close)
	return row


func _to_tab(want: int, here: int) -> void:
	if want == here:
		return
	if want == 1:
		toggle_talents()
	else:
		toggle_talents()
		toggle()


func _close_tab(here: int) -> void:
	if here == 0:
		toggle()
	else:
		toggle_talents()


func _build() -> void:
	window = PanelContainer.new()
	window.add_theme_stylebox_override("panel", HudStyle.piece("panelStrong"))
	add_child(window)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", int(_k(10)))
	window.add_child(root)
	root.add_child(tabs(0, true))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", int(_k(14)))
	root.add_child(cols)
	cols.add_child(_build_equipment())
	cols.add_child(_build_stats())
	cols.add_child(_build_bag())
	var foot := HBoxContainer.new()
	foot.add_child(HudStyle.label("Click  pick    Double-click  use / wear    Drag  move    Click a worn slot  pick it", 11, "bold", HudStyle.color("faint")))
	foot.add_child(_gap())
	foot.add_child(HudStyle.label("C / I  toggle  ·  Esc  close", 11, "bold", HudStyle.color("faint")))
	root.add_child(foot)


func _label(key: String, sz: float, kind := "bold", c: Variant = null) -> Label:
	var l := HudStyle.label("", sz, kind, c)
	_labels[key] = l
	return l


func _bar(parent: Control, key: String, c: Color, h: float, w: float) -> void:
	var back := Panel.new()
	back.add_theme_stylebox_override("panel", HudStyle.piece("barBack"))
	back.custom_minimum_size = Vector2(_k(w), _k(h))
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fill := Panel.new()
	fill.add_theme_stylebox_override("panel", HudStyle.piece("barFill", c))
	fill.size = Vector2(_k(w), _k(h))
	back.add_child(fill)
	parent.add_child(back)
	_bars[key] = [fill, _k(w)]


func _fill(key: String, share: float) -> void:
	var b: Array = _bars[key]
	b[0].size.x = b[1] * clampf(share, 0.0, 1.0)
	b[0].visible = share > 0.001


# Left: name, level, XP; Miko between her slots; her weapon.
func _build_equipment() -> Control:
	var well := _well()
	well.custom_minimum_size.x = _k(EQUIP_W)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(_k(6)))
	well.add_child(box)
	var head := HBoxContainer.new()
	var nm := HudStyle.label("Miko", 18, "bold")
	head.add_child(nm)
	head.add_child(_gap())
	head.add_child(_label("level", 14, "pixel", HudStyle.color("accentLight")))
	box.add_child(head)
	_bar(box, "xp", HudStyle.color("accent"), 6, EQUIP_W - 24)
	box.add_child(_label("xp", 11, "bold", HudStyle.color("faint")))
	var mid := HBoxContainer.new()
	mid.add_theme_constant_override("separation", 0)
	box.add_child(mid)
	for side in [LEFT_SLOTS, RIGHT_SLOTS]:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", int(_k(8)))
		for s in side:
			var c := SlotCell.new()
			c.panel = self
			c.slot = s[0]
			c.title = s[1]
			c.custom_minimum_size = Vector2(_k(50), _k(50))
			col.add_child(c)
			_slot_cells[s[0]] = c
		mid.add_child(col)
		if side == LEFT_SLOTS:
			_figure = MikoFigure.new()
			_figure.miko = miko
			_figure.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_figure.custom_minimum_size = Vector2(_k(160), _k(260))
			mid.add_child(_figure)
	# Her weapon, named.
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", HudStyle.piece("well", Color(1, 0.91, 0.77, 0.5)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(_k(8)))
	_weapon_icon = ChestWindow.Cell.new()
	_weapon_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_weapon_icon.custom_minimum_size = Vector2(_k(36), _k(36))
	row.add_child(_weapon_icon)
	var texts := VBoxContainer.new()
	texts.add_theme_constant_override("separation", 0)
	texts.add_child(_label("weapon", 13, "bold"))
	var info := _label("weapon_info", 11, "bold", HudStyle.color("green"))
	info.clip_text = true
	info.custom_minimum_size.x = _k(250)
	texts.add_child(info)
	row.add_child(texts)
	card.add_child(row)
	box.add_child(card)
	return well


# Middle: vitals, stats, and the talent points to spend.
func _build_stats() -> Control:
	var col := VBoxContainer.new()
	col.custom_minimum_size.x = _k(STATS_W)
	col.add_theme_constant_override("separation", int(_k(12)))
	var vitals := _well()
	var vb := VBoxContainer.new()
	vitals.add_child(vb)
	vb.add_child(HudStyle.label("VITALS", 11, "bold", HudStyle.color("faint")))
	for v in [["hp", "heart", HudStyle.color("hp")], ["mana", "drop", HudStyle.color("mana")]]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", int(_k(8)))
		var icon := TextureRect.new()
		icon.texture = HudStyle.icon(v[1])
		icon.modulate = v[2]
		icon.custom_minimum_size = Vector2(_k(14), _k(14))
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(icon)
		_bar(row, v[0], v[2], 8, STATS_W - 130)
		row.add_child(_gap())
		row.add_child(_label(v[0], 13, "pixel"))
		vb.add_child(row)
	col.add_child(vitals)
	var list := _well()
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var lb := VBoxContainer.new()
	list.add_child(lb)
	var tabs_row := HBoxContainer.new()
	for i in 2:
		var b := HudStyle.button(["Stats", "Life skills"][i], 12)
		b.pressed.connect(func():
			stats_tab = i
			_dirty = true)
		tabs_row.add_child(b)
		_stat_tabs.append(b)
	lb.add_child(tabs_row)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = _k(240)
	_stats_text = RichTextLabel.new()
	_stats_text.bbcode_enabled = true
	_stats_text.fit_content = true
	_stats_text.scroll_active = false
	_stats_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stats_text.add_theme_font_override("normal_font", HudStyle.font("bold"))
	_stats_text.add_theme_font_size_override("normal_font_size", roundi(_k(13)))
	_stats_text.add_theme_color_override("default_color", HudStyle.color("text"))
	_stats_text.add_theme_constant_override("line_separation", int(_k(4)))
	scroll.add_child(_stats_text)
	lb.add_child(scroll)
	col.add_child(list)
	# Talent points: a call to spend them (opens Talents).
	_points_button = HudStyle.button("", 13, "pill")
	_points_button.custom_minimum_size.y = _k(56)
	_points_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_points_button.pressed.connect(toggle_talents)
	col.add_child(_points_button)
	return col


# Right: the bag, its filters, and the picked thing.
func _build_bag() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", int(_k(8)))
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", int(_k(6)))
	head.add_child(HudStyle.label("Bag", 15, "bold"))
	head.add_child(_label("bag_count", 13, "pixel", HudStyle.color("muted")))
	var sort := HudStyle.button("Sort", 11)
	sort.pressed.connect(func():
		_sort()
		selected = -1)
	head.add_child(sort)
	head.add_child(_gap())
	for f in FILTERS:
		var b := HudStyle.button(f[1], 12)
		b.pressed.connect(func():
			filter = f[0]
			selected = -1
			_dirty = true)
		head.add_child(b)
		_filter_buttons[f[0]] = b
	col.add_child(head)
	var grid := GridContainer.new()
	grid.columns = Bag.COLUMNS
	grid.add_theme_constant_override("h_separation", int(_k(5)))
	grid.add_theme_constant_override("v_separation", int(_k(5)))
	for i in Bag.SIZE:
		var c := BagCell.new()
		c.panel = self
		c.index = i
		c.custom_minimum_size = Vector2(_k(CELL), _k(CELL))
		grid.add_child(c)
		_cells.append(c)
	col.add_child(grid)
	# The picked thing: icon, name and count, what it is, and its buttons.
	var strip := _well()
	var sb := VBoxContainer.new()
	strip.add_child(sb)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", int(_k(10)))
	_pick_icon = ChestWindow.Cell.new()
	_pick_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pick_icon.custom_minimum_size = Vector2(_k(44), _k(44))
	top.add_child(_pick_icon)
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# The same size whatever is picked: the name cut short with "…" rather than widening the panel, the details in
	# three lines (the rest cut with "…", all of it in the tooltip) rather than growing it.
	var nm := _label("pick_name", 14, "bold")
	nm.clip_text = true
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nm.custom_minimum_size.x = _k(300)
	texts.add_child(nm)
	var info := _label("pick_info", 12, "bold", HudStyle.color("muted"))
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size.x = _k(300)
	info.max_lines_visible = 3
	info.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	info.mouse_filter = Control.MOUSE_FILTER_PASS
	texts.add_child(info)
	_info_lines = info
	var f := info.get_theme_font("font")
	var fs := info.get_theme_font_size("font_size")
	info.custom_minimum_size.y = 3.0 * (f.get_height(fs) + info.get_theme_constant("line_spacing")) if f != null else _k(48)
	top.add_child(texts)
	sb.add_child(top)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", int(_k(8)))
	_action = HudStyle.button("", 12, "barFill", HudStyle.color("ink"))
	_action.add_theme_stylebox_override("normal", HudStyle.piece("barFill", HudStyle.color("accent")))
	_action.add_theme_stylebox_override("hover", HudStyle.piece("barFill", HudStyle.color("accentLight")))
	_action.custom_minimum_size = Vector2(_k(90), _k(28))
	_action.pressed.connect(_do_action)
	buttons.add_child(_action)
	_drop = HudStyle.button("Drop", 12)
	_drop.custom_minimum_size = Vector2(_k(70), _k(28))
	_drop.pressed.connect(_do_drop)
	buttons.add_child(_drop)
	buttons.custom_minimum_size.y = _drop.get_combined_minimum_size().y   # its room kept with nothing picked
	_destroy = HudStyle.button("Destroy", 12, "pill", HudStyle.color("coral"))
	_destroy.custom_minimum_size = Vector2(_k(84), _k(28))
	_destroy.pressed.connect(_do_destroy)
	buttons.add_child(_destroy)
	sb.add_child(buttons)
	col.add_child(strip)
	return col


# ---- Filling it in ----

func _refresh() -> void:
	_layout()
	var cap := bag.capacity()
	var keep := filter == "All" or filter == "Equipment"
	for i in Bag.SIZE:
		var c: BagCell = _cells[i]
		c.shut = keep and i >= cap
		c.owned = keep and i >= Bag.BASE_SLOTS and i < cap
		c.on = i == selected and picked_slot == ""
		var what: Array = _shows[i]
		if what.is_empty(): c.show_nothing()
		elif what[0] == "item": c.show_item(bag.items[what[1]])
		else: c.show_stack(what[1], bag.count(what[1]), HudStyle.color("text"))
		c.queue_redraw()
	var used := 0
	for i in cap:
		if bag.items[i] != "" or bag.stack_in(i) != "":
			used += 1
	_labels.bag_count.text = "%d/%d" % [used, cap]
	for f in _filter_buttons:
		_filter_buttons[f].modulate = Color(1.3, 1.15, 0.8) if f == filter else Color(1, 1, 1, 0.7)
	for i in _stat_tabs.size():
		_stat_tabs[i].modulate = Color(1.3, 1.15, 0.8) if i == stats_tab else Color(1, 1, 1, 0.7)
	_character()
	_stats_list()
	for s in _slot_cells:
		var c: SlotCell = _slot_cells[s]
		c.blocked = s == "RightHand" and stats.right_hand_blocked()
		c.on = picked_slot == s
		var it := "" if c.blocked else stats.worn_in(s)
		if it == "": c.show_nothing()
		else: c.show_item(it)
		c.has_item = it != ""
		c.queue_redraw()
	_picked()


func _vitals() -> void:
	var t := stats.total()
	var max_hp := maxf(1.0, float(t.get("maxHp", 100.0)))
	var max_mana := maxf(1.0, float(t.get("maxMana", 50.0)))
	_fill("hp", stats.hp / max_hp)
	_fill("mana", stats.mana / max_mana)
	_labels.hp.text = "%d/%d" % [ceili(stats.hp), roundi(max_hp)]
	_labels.mana.text = "%d/%d" % [floori(stats.mana), roundi(max_mana)]
	_figure.queue_redraw()


func _character() -> void:
	_labels.level.text = "Lv %d" % stats.level
	_labels.xp.text = "XP %d / %d" % [stats.xp, stats.xp_to_next()]
	_fill("xp", float(stats.xp) / maxf(1.0, stats.xp_to_next()))
	var points := stats.talent_points
	_badge.text = str(points) if points > 0 else ""
	_points_button.text = "  %d   talent point%s  ·  %s   ›" % [points, "" if points == 1 else "s", "ready to spend" if points > 0 else "level up to earn more"]
	_points_button.add_theme_stylebox_override("normal", HudStyle.piece("pill", Color(HudStyle.color("accent"), 0.6 if points > 0 else 0.25)))
	var weapon := stats.worn_in("LeftHand")
	if weapon == "":
		_weapon_icon.show_nothing()
		_labels.weapon.text = "No weapon"
		_labels.weapon_info.text = "Wear one from the bag"
	else:
		_weapon_icon.show_item(weapon)
		var it := UiKit.item(weapon)
		_labels.weapon.text = str(it.get("name", weapon))
		_labels.weapon_info.text = "%s · %s" % [it.get("label", ""), CharacterStats.describe(stats.item_stats.get(weapon, {}).get("stats", {}))]
	_weapon_icon.queue_redraw()


# Combat and recovery; anything else she has (from gear or talents) under Other. Or her life skills.
func _stats_list() -> void:
	var muted := HudStyle.color("muted").to_html(false)
	var faint := HudStyle.color("faint").to_html(false)
	var green := HudStyle.color("green").to_html(false)
	var small := roundi(_k(11))
	if stats_tab == 1:
		var t := "[font_size=%d][color=#%s]LIFE SKILLS  ·  MAX LEVEL %d[/color][/font_size]\n" % [small, faint, LifeSkills.MOST]
		for i in LifeSkills.NAMES.size():
			var lv := LifeSkills.get_level(i)
			var need := 8 * maxi(1, lv)
			var done := lv >= LifeSkills.MOST
			var share := 1.0 if done else float(LifeSkills.xp[i]) / need
			var bars := int(round(share * 20))
			t += "[color=#%s]%s[/color]  %d/%d   [font_size=%d][color=#%s]%s[/color][/font_size]\n[color=#%s]%s[/color][color=#%s]%s[/color]\n" % [
				muted, LifeSkills.NAMES[i], lv, LifeSkills.MOST, small, faint, "mastered" if done else "%d / %d xp" % [LifeSkills.xp[i], need],
				HudStyle.color("accent").to_html(false), "▰".repeat(bars), faint, "▱".repeat(20 - bars)]
		_stats_text.text = t
		return
	var total := stats.total()
	var bonus := stats.bonuses()
	var line := func(key: String) -> String:
		for s in CharacterStats.STAT_NAMES:
			if s[0] == key:
				var extra := float(bonus.get(key, 0.0))
				var plus := " [color=#%s](+%s)[/color]" % [green, CharacterStats.fmt(extra)] if absf(extra) > 0.001 else ""
				return "[color=#%s]%s[/color]  %s%s%s\n" % [muted, s[1], CharacterStats.fmt(float(total.get(key, 0.0))), s[2], plus]
		return ""
	var head := func(t: String) -> String: return "[font_size=%d][color=#%s]%s[/color][/font_size]\n" % [small, faint, t]
	var text: String = head.call("COMBAT") + line.call("attack") + line.call("defense") + line.call("magic") + line.call("castSpeed") \
		+ "\n" + head.call("RECOVERY") + line.call("hpRegen") + line.call("manaRegen")
	var shown := ["maxHp", "maxMana", "attack", "defense", "magic", "castSpeed", "hpRegen", "manaRegen"]
	var other := ""
	for s in CharacterStats.STAT_NAMES:
		if not shown.has(s[0]) and absf(float(total.get(s[0], 0.0))) > 0.001:
			other += line.call(s[0])
	if other != "":
		text += "\n" + head.call("OTHER") + other
	_stats_text.text = text.strip_edges()


# What the shown slots hold, by the filter: Gear keeps the bag's layout; the others list their stacks.
func _layout() -> void:
	_shows.clear()
	_shows.resize(Bag.SIZE)
	_shows.fill([])
	if filter == "All" or filter == "Equipment":
		for i in Bag.SIZE:
			if bag.items[i] != "":
				_shows[i] = ["item", i]
			elif filter == "All" and bag.stack_in(i) != "":
				_shows[i] = ["stack", bag.stack_in(i)]
		return
	var n := 0
	for r in Bag.RESOURCES:
		if bag.count(r) > 0 and Bag.slotted(r) and UiKit.data.resources.get(r, {}).get("group", "") == filter:
			_shows[n] = ["stack", r]
			n += 1


func _bag_pick() -> Array:
	return [] if picked_slot != "" or selected < 0 else _shows[selected]


func _picked() -> void:
	var pick := _bag_pick()
	_pick_icon.show_nothing()
	var action := ""
	var muted := HudStyle.color("muted")
	if picked_slot != "" and stats.worn_in(picked_slot) != "":
		var it_name := stats.worn_in(picked_slot)
		_show_item(it_name)
		action = "Take off"
	elif not pick.is_empty() and pick[0] == "item":
		_show_item(bag.items[pick[1]])
		action = "Wear"
	elif not pick.is_empty():
		var r: String = pick[1]
		_pick_icon.show_stack(r, 0, Color.WHITE)
		_pick_icon._count = ""
		_labels.pick_name.text = "%s  ×%d" % [UiKit.resource_name(r), bag.count(r)]
		var usable: bool = UiKit.data.resources.get(r, {}).get("usable", false)
		var kind := "Potion" if r.ends_with("Potion") else ("Drink" if r == "Tea" else ("Seed" if r == "Seed" else ("Food" if UiKit.data.resources.get(r, {}).get("group", "") == "Consumables" else "Material")))
		_set_info("%s · %s" % [kind, USES.get(r, "For building.")])
		if usable:
			action = "Drink" if r == "Tea" or r.ends_with("Potion") else "Eat"
	else:
		_labels.pick_name.text = ""
		_set_info("Pick something in the bag, or a worn slot.")
	_pick_icon.queue_redraw()
	_action.visible = action != ""
	_action.text = action
	var key := str(pick)
	if _destroy_armed != key:
		_destroy_armed = ""
	_drop.visible = not pick.is_empty()
	_destroy.visible = not pick.is_empty()
	var armed := _destroy_armed != "" and not pick.is_empty()
	_destroy.text = "Sure?" if armed else "Destroy"
	_destroy.add_theme_stylebox_override("normal", HudStyle.piece("barFill", HudStyle.color("coral")) if armed else HudStyle.piece("pill"))
	for k in ["font_color", "font_hover_color", "font_pressed_color"]:
		_destroy.add_theme_color_override(k, HudStyle.color("ink") if armed else HudStyle.color("coral"))
	_labels.pick_info.add_theme_color_override("font_color", muted)


func _show_item(it_name: String) -> void:
	var it := UiKit.item(it_name)
	_pick_icon.show_item(it_name)
	_labels.pick_name.text = str(it.get("name", it_name))
	var grants := str(stats.item_stats.get(it_name, {}).get("grantsSpell", ""))
	var desc := CharacterStats.describe(stats.item_stats.get(it_name, {}).get("stats", {}))
	if int(it.get("bagSlots", 0)) > 0:
		desc += ("" if desc == "" else ", ") + "+%d bag slots" % int(it.bagSlots)
	var left := stats.durability_left(it_name)
	if left >= 0.0:
		desc += ("" if desc == "" else ", ") + "%d%% durability" % roundi(left * 100.0)
	_set_info("%s%s%s" % [it.get("label", ""), (" · " + desc) if desc != "" else "", (" · grants " + grants) if grants != "" else ""])


# The picked thing's details: as many as show in its three lines, and all of them when hovered.
func _set_info(text: String) -> void:
	_labels.pick_info.text = text
	_labels.pick_info.tooltip_text = text


func clicked(i: int, double: bool) -> void:
	selected = i
	picked_slot = ""
	_destroy_armed = ""
	if double:
		use(i)
	_dirty = true


func pick_slot(slot: String) -> void:
	picked_slot = slot if stats.worn_in(slot) != "" else ""
	selected = -1
	_dirty = true


## Using shown slot [param i]: wearing gear, or eating (drinking) one of a stack.
func use(i: int) -> void:
	var what: Array = _shows[i]
	if what.is_empty():
		return
	if what[0] == "item":
		stats.equip(bag, what[1])
		selected = -1
		return
	var r: String = what[1]
	if not UiKit.data.resources.get(r, {}).get("usable", false):
		return
	var needs: Needs = miko.get_node_or_null("Needs")
	if needs != null:
		needs.eat(r)


func dropped(from: int, to: int) -> void:
	if filter != "All" and filter != "Equipment":
		return
	bag.move(from, to)
	selected = to
	_dirty = true


func _do_action() -> void:
	if picked_slot != "":
		stats.unequip(bag, picked_slot)
		picked_slot = ""
	elif selected >= 0:
		use(selected)
	_dirty = true


# Drop: the whole stack (or the piece of gear) on the ground at her feet. Gear can't lie on the ground yet, so it stays.
func _do_drop() -> void:
	var pick := _bag_pick()
	if pick.is_empty():
		return
	if pick[0] == "stack":
		var n := bag.count(pick[1])
		if n > 0 and bag.spend(pick[1], n):
			Pickup.drop(world, pick[1], n, miko.position)
	else:
		FloatingText.spawn(world, "Gear can't be dropped yet: store it in a chest", miko.position + Vector2(0, -1.4 * world.px), HudStyle.color("coral"))
	selected = -1
	_dirty = true


# Destroy: "Sure?" on the first click, gone for good on the second.
func _do_destroy() -> void:
	var pick := _bag_pick()
	if pick.is_empty():
		return
	if _destroy_armed != str(pick):
		_destroy_armed = str(pick)
		_dirty = true
		return
	if pick[0] == "item":
		bag.items[pick[1]] = ""
		bag.changed.emit()
	else:
		bag.spend(pick[1], bag.count(pick[1]))
	_destroy_armed = ""
	selected = -1
	_dirty = true


# The bag tidied: its gear first (by kind, then name), then the stacks, food before materials.
func _sort() -> void:
	var gear := []
	for i in Bag.SIZE:
		if bag.items[i] != "":
			gear.append(bag.items[i])
	gear.sort_custom(func(a, b):
		var ka := str(UiKit.item(a).get("kind", ""))
		var kb := str(UiKit.item(b).get("kind", ""))
		return ka < kb if ka != kb else str(UiKit.item(a).get("name", a)) < str(UiKit.item(b).get("name", b)))
	for i in Bag.SIZE:
		bag.items[i] = gear[i] if i < gear.size() else ""
	var next := gear.size()
	for group in ["Consumables", "Materials"]:
		for r in Bag.RESOURCES:
			if Bag.slotted(r) and bag.count(r) > 0 and UiKit.data.resources.get(r, {}).get("group", "Materials") == group:
				bag.stack_slot[r] = next
				next += 1
	bag.changed.emit()


## One of the bag's cells: picked amber, the worn bag's slots ringed, shut ones greyed; click, double-click, drag.
class BagCell extends ChestWindow.Cell:
	var panel: CharacterPanel
	var index := 0
	var on := false
	var owned := false

	func _draw() -> void:
		super._draw()
		var r := Rect2(Vector2.ZERO, size)
		if owned:
			draw_rect(r.grow(-3), Color(0.9, 0.62, 0.2, 0.45), false, 2.0)
		if on:
			draw_rect(r.grow(-1), HudStyle.color("accent"), false, 3.0)

	func _gui_input(event: InputEvent) -> void:
		if shut:
			return
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			panel.clicked(index, event.double_click)
			accept_event()

	func _get_drag_data(_at: Vector2) -> Variant:
		if shut or (_icon == null and _tile.a <= 0.0):
			return null
		var preview := TextureRect.new()
		preview.texture = _icon
		preview.custom_minimum_size = Vector2(40, 40)
		preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		set_drag_preview(preview)
		return {"bag_slot": index}

	func _can_drop_data(_at: Vector2, d: Variant) -> bool:
		return not shut and d is Dictionary and d.has("bag_slot")

	func _drop_data(_at: Vector2, d: Variant) -> void:
		panel.dropped(int(d.bag_slot), index)


## One worn slot: its name when empty ("2H" when a two-handed weapon takes it), the gear in it, amber when picked.
class SlotCell extends ChestWindow.Cell:
	var panel: CharacterPanel
	var slot := ""
	var title := ""
	var on := false
	var blocked := false
	var has_item := false

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_style_box(HudStyle.piece("slotOn" if on else "slot", Color(1, 1, 1, 0.45) if blocked else Color.WHITE), r)
		if has_item:
			var keep := shut
			shut = false
			super._draw()
			shut = keep
		else:
			var f := HudStyle.font("bold")
			var t := "2H" if blocked else title
			var px := roundi(10 * HudStyle.SCALE)
			draw_string(f, Vector2(0, size.y / 2.0 + px / 3.0), t, HORIZONTAL_ALIGNMENT_CENTER, size.x, px, Color(0.56, 0.5, 0.41, 0.5 if blocked else 1.0))
		if on:
			draw_rect(r.grow(-1), HudStyle.color("accent"), false, 3.0)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			panel.pick_slot(slot)
			if event.double_click and has_item:
				panel._do_action()
			accept_event()


## Miko as she is in the world right now (walking, turning, whatever she's doing), drawn big between her slots.
class MikoFigure extends Control:
	var miko: Miko

	func _draw() -> void:
		var art := miko.art
		if art == null or art.texture == null:
			return
		var src := art.region_rect if art.region_enabled else Rect2(Vector2.ZERO, art.texture.get_size())
		var k := minf(size.x / src.size.x, size.y / src.size.y) * 1.25
		var w := src.size * k
		var at := Vector2((size.x - w.x) / 2.0, size.y - w.y)
		var flip := art.flip_h != (art.scale.x < 0.0)
		if flip:
			draw_set_transform(Vector2(size.x, 0), 0.0, Vector2(-1, 1))
		draw_texture_rect_region(art.texture, Rect2(at, w), src)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
