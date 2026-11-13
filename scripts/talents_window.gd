class_name TalentsWindow
extends PanelContainer
## The Talents tab (from Unity's CharacterPanel talents and TalentWebView; P): the web on the left, with a search, a
## key to its colours and zoom buttons; on the right the points to spend, the picked talent (what it does, what its
## path costs, and Learn), the skills Miko has from gear and talents (click one to put it on the hotbar) and Reset.
##
## The web: every talent at its place, linked by lines, round the start in the middle. Drag to pan, scroll to zoom.
## Small talents are small dots, notables bigger, keystones the biggest (turned to diamonds, with their skill's icon).
## Lit in their region's colour when learnt, brighter when they can be reached. Hovering one lights the cheapest path
## out to it and says what it costs; clicking picks it; right-click a learnt one to give it back, for gold.
##
## Whose talents they are is picked along the top of the right side: Sera's, or a companion's (theirs are spent the
## same way, from their own points; their skills are the ones they cast by themselves in a fight).

const SIDE_W := 352.0
const WEB := Vector2(720, 470)

var world: World
var miko: Miko
var stats: CharacterStats
var panel: CharacterPanel
var caster: SpellCaster
var web: TalentWeb
var selected := ""
var _search: LineEdit
var _found: Label
var _points: Label
var _badge: Panel
var _name: Label
var _kind: Label
var _desc: RichTextLabel
var _path: Label
var _learn: Button
var _skills: VBoxContainer
var _tip: PanelContainer
var _tip_text: RichTextLabel
var _who: HBoxContainer
var _points_label: Label
var person: Dictionary = {}       ## the companion whose talents are shown, or {} for Sera's own


func _k(v: float) -> float:
	return v * HudStyle.SCALE


func setup(w: World, who: Miko, p: CharacterPanel) -> void:
	world = w
	miko = who
	stats = who.stats
	panel = p
	caster = w.get_node_or_null("Caster")
	add_theme_stylebox_override("panel", HudStyle.piece("panelStrong"))
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", int(_k(10)))
	add_child(root)
	root.add_child(p.tabs(1, false))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", int(_k(14)))
	root.add_child(cols)
	# Left: search and a hint, then the web.
	var left := VBoxContainer.new()
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", int(_k(8)))
	_search = LineEdit.new()
	_search.placeholder_text = "Search talents, e.g. fire, defense"
	_search.custom_minimum_size = Vector2(_k(240), _k(30))
	_search.add_theme_stylebox_override("normal", HudStyle.piece("well"))
	_search.add_theme_stylebox_override("focus", HudStyle.piece("well"))
	_search.add_theme_font_size_override("font_size", roundi(_k(12)))
	_search.text_changed.connect(func(t: String):
		var n := web.search(t)
		_found.text = "" if t.strip_edges() == "" else ("none" if n == 0 else "%d found" % n))
	_search.text_submitted.connect(func(_t): web.focus_next())
	bar.add_child(_search)
	_found = HudStyle.label("", 11, "bold", HudStyle.color("accent"))
	bar.add_child(_found)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(gap)
	bar.add_child(HudStyle.label("Drag to pan · Scroll to zoom · Right-click refunds (%d gold)" % stats.refund_cost(), 11, "bold", HudStyle.color("faint")))
	left.add_child(bar)
	var area := PanelContainer.new()
	area.add_theme_stylebox_override("panel", HudStyle.piece("well", Color(0.75, 0.7, 0.66)))
	web = TalentWeb.new()
	web.window = self
	web.stats = stats
	web.caster = caster
	web.custom_minimum_size = WEB * HudStyle.SCALE
	web.clip_contents = true
	area.add_child(web)
	left.add_child(area)
	# A key to the colours, bottom left; zoom, bottom right.
	var under := HBoxContainer.new()
	var legend := RichTextLabel.new()
	legend.bbcode_enabled = true
	legend.fit_content = true
	legend.autowrap_mode = TextServer.AUTOWRAP_OFF
	legend.scroll_active = false
	legend.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	legend.add_theme_font_override("normal_font", HudStyle.font("bold"))
	legend.add_theme_font_size_override("normal_font_size", roundi(_k(11)))
	legend.add_theme_color_override("default_color", HudStyle.color("muted"))
	var dot := func(c: Color) -> String: return "[color=#%s]●[/color]" % c.to_html(false)
	legend.text = "%s Learned   %s Available   %s Path to picked   %s Locked" % [dot.call(Color(1, 0.5, 0.32)), dot.call(Color(0.42, 0.33, 0.26)), dot.call(HudStyle.color("accent")), dot.call(Color(0.24, 0.2, 0.17))]
	under.add_child(legend)
	for z in [["+", 1.25], ["−", 0.8], ["Fit", 0.0]]:
		var b := HudStyle.button(z[0], 12, "slot")
		b.custom_minimum_size = Vector2(_k(34), _k(28))
		b.pressed.connect(_zoom.bind(z[1]))
		under.add_child(b)
	left.add_child(under)
	cols.add_child(left)
	# Right: points, the picked talent, skills, reset.
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = _k(SIDE_W)
	right.add_theme_constant_override("separation", int(_k(12)))
	_who = HBoxContainer.new()
	_who.add_theme_constant_override("separation", int(_k(6)))
	right.add_child(_who)
	var points := PanelContainer.new()
	points.add_theme_stylebox_override("panel", HudStyle.piece("pill", Color(HudStyle.color("accent"), 0.5)))
	var prow := HBoxContainer.new()
	prow.add_theme_constant_override("separation", int(_k(12)))
	_points = HudStyle.label("0", 28, "bold", HudStyle.color("accent"))
	prow.add_child(_points)
	var pl := VBoxContainer.new()
	pl.add_theme_constant_override("separation", 0)
	_points_label = HudStyle.label("talent points", 13, "bold")
	pl.add_child(_points_label)
	pl.add_child(HudStyle.label("+1 each level", 11, "bold", HudStyle.color("muted")))
	prow.add_child(pl)
	points.add_child(prow)
	right.add_child(points)
	var detail := PanelContainer.new()
	detail.add_theme_stylebox_override("panel", HudStyle.piece("well"))
	detail.custom_minimum_size.y = _k(220)
	var db := VBoxContainer.new()
	db.add_theme_constant_override("separation", int(_k(6)))
	detail.add_child(db)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", int(_k(12)))
	_badge = Badge.new()
	_badge.custom_minimum_size = Vector2(_k(48), _k(48))
	top.add_child(_badge)
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 0)
	_name = HudStyle.label("", 16, "bold")
	names.add_child(_name)
	_kind = HudStyle.label("", 12, "bold")
	names.add_child(_kind)
	top.add_child(names)
	db.add_child(top)
	_desc = _rich(13)
	_desc.custom_minimum_size.x = _k(SIDE_W - 30)
	db.add_child(_desc)
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	db.add_child(fill)
	_path = HudStyle.label("", 12, "bold", HudStyle.color("muted"))
	_path.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_path.custom_minimum_size.x = _k(SIDE_W - 30)
	db.add_child(_path)
	_learn = HudStyle.button("", 13, "pill")
	_learn.custom_minimum_size.y = _k(38)
	_learn.pressed.connect(_learn_selected)
	db.add_child(_learn)
	right.add_child(detail)
	var skills := PanelContainer.new()
	skills.add_theme_stylebox_override("panel", HudStyle.piece("well"))
	skills.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var sb := VBoxContainer.new()
	skills.add_child(sb)
	sb.add_child(HudStyle.label("SKILLS", 11, "bold", HudStyle.color("faint")))
	_skills = VBoxContainer.new()
	sb.add_child(_skills)
	right.add_child(skills)
	var reset := HudStyle.button("Reset all talents · %d gold each" % stats.refund_cost(), 12, "pill", HudStyle.color("muted"))
	reset.custom_minimum_size.y = _k(34)
	reset.pressed.connect(_reset)
	right.add_child(reset)
	cols.add_child(right)
	# The hover card.
	_tip = PanelContainer.new()
	_tip.add_theme_stylebox_override("panel", HudStyle.piece("panelStrong"))
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip.top_level = true
	_tip_text = _rich(13)
	_tip_text.custom_minimum_size.x = _k(290)
	_tip.add_child(_tip_text)
	_tip.visible = false
	add_child(_tip)
	stats.changed.connect(_on_changed)
	visible = false


func _zoom(f: float) -> void:
	if f == 0.0:
		web.fit()
	else:
		web.zoom_by(f)


func _on_changed() -> void:
	if visible:
		refresh()


## Shows [param p]'s talents (a companion's), or Sera's own with {}.
func show_for(p: Dictionary) -> void:
	var st: CharacterStats = miko.stats if p.is_empty() else Companions.stats_for(p)
	if st == null:
		return
	person = p
	if st != stats:
		if stats.changed.is_connected(_on_changed):
			stats.changed.disconnect(_on_changed)
		stats = st
		web.stats = st
		stats.changed.connect(_on_changed)
		selected = ""
	refresh()


## Whose talents these are, as a name.
func owner_name() -> String:
	return Miko.NAME if person.is_empty() else str(person.get("name", "?"))


# The row of whose talents to show: Sera, then each companion with her.
func _whose() -> void:
	for ch in _who.get_children():
		_who.remove_child(ch)
		ch.queue_free()
	var all: Array = [{}]
	if Party.active != null:
		for id in Party.active.members:
			var p := Uniques.person(Party.active.people, str(id))
			if not p.is_empty():
				all.append(p)
	if all.size() < 2:
		_who.visible = false
		return
	_who.visible = true
	for p in all:
		var here: bool = (p as Dictionary).is_empty() == person.is_empty() and (p.is_empty() or is_same(p, person))
		var b := HudStyle.button(Miko.NAME if p.is_empty() else str(p.name), 12, "pill", HudStyle.color("text") if here else HudStyle.color("muted"))
		if here:
			b.add_theme_stylebox_override("normal", HudStyle.piece("pill", Color(HudStyle.color("accent"), 0.6)))
		b.custom_minimum_size.y = _k(28)
		b.pressed.connect((panel.show_for if panel != null else show_for).bind(p))
		_who.add_child(b)


func _rich(sz: float) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_theme_font_override("normal_font", HudStyle.font("body"))
	r.add_theme_font_override("bold_font", HudStyle.font("bold"))
	r.add_theme_font_size_override("normal_font_size", roundi(_k(sz)))
	r.add_theme_font_size_override("bold_font_size", roundi(_k(sz + 1)))
	r.add_theme_color_override("default_color", HudStyle.color("text"))
	return r


func _process(delta: float) -> void:
	var __t := Time.get_ticks_usec()
	_process_timed(delta)
	Perf.add(&"talents_window.process", __t)


func _process_timed(_delta: float) -> void:
	if not visible:
		return
	reset_size()
	position = ((get_viewport_rect().size - size) / 2.0).round()
	if _tip.visible:
		_tip.reset_size()
		var m := get_viewport().get_mouse_position()
		var vp := get_viewport_rect().size
		var at := m + Vector2(20, 20)
		if at.x + _tip.size.x > vp.x: at.x = m.x - 20 - _tip.size.x
		if at.y + _tip.size.y > vp.y: at.y = m.y - 20 - _tip.size.y
		_tip.position = at


func show_tip(text: String) -> void:
	_tip_text.text = text
	_tip.visible = true


func hide_tip() -> void:
	_tip.visible = false


func refresh() -> void:
	_whose()
	_points.text = str(stats.talent_points)
	_points_label.text = "talent points" if person.is_empty() else "%s's talent points" % str(person.get("name", "?"))
	if selected == "":
		for t in stats.character.talents:
			if t.kind == "Start":
				selected = t.id
	web.selection = selected
	web.queue_redraw()
	_picked()
	_others()


func select(id: String) -> void:
	selected = id
	refresh()


static func kind_name(k: String) -> String:
	return {"Big": "Keystone", "Core": "Notable", "Start": "Start"}.get(k, "Minor")


static func region_color(region: String) -> Color:
	match region:
		"Spell": return Color(1, 0.5, 0.32)
		"Shikigami": return Color(0.82, 0.68, 1)
		"Hearth": return Color(0.62, 0.86, 0.45)
		"Body": return Color(0.5, 0.74, 1)
	return Color(0.98, 0.92, 0.82)


func spell_name(id: String) -> String:
	return str(caster.spells.get(id, {}).get("name", id)) if caster != null else id


func _picked() -> void:
	var t := stats.talent(selected)
	if t.is_empty():
		return
	var colour := region_color(t.region)
	var learned := stats.unlocked(t.id)
	(_badge as Badge).color = colour if learned or t.kind == "Start" else Color(colour * 0.35, 1.0)
	_badge.queue_redraw()
	_name.text = str(t.name)
	_kind.text = kind_name(t.kind) + ("" if str(t.region) == "" else " · " + str(t.region))
	_kind.add_theme_color_override("font_color", colour)
	var bonus := CharacterStats.describe(t.perRank)
	var text := str(t.get("description", ""))
	if bonus != "":
		text += "\n[color=#%s]%s[/color]" % [HudStyle.color("green").to_html(false), bonus]
	if str(t.get("grantsSpell", "")) != "":
		text += "\n[color=#%s]Grants %s[/color]" % [HudStyle.color("mana").to_html(false), spell_name(t.grantsSpell)]
	_desc.text = text.strip_edges()
	var path: Variant = stats.path_to(t.id)
	var cost: int = path.size() if path != null else 0
	var can: bool = not learned and path != null and cost > 0 and cost <= stats.talent_points
	if learned or t.kind == "Start":
		_path.text = "Where every path begins." if t.kind == "Start" else ("Learned. Right-click it to refund (%d gold)." % stats.refund_cost() if stats.can_refund(t.id) else "Learned. Others hang on it.")
	elif path == null:
		_path.text = "Can't be reached yet."
	else:
		_path.text = "Learning this takes %d talent%s on the path: %d point%s." % [cost, "" if cost == 1 else "s", cost, "" if cost == 1 else "s"]
	_learn.text = "Learned" if learned or t.kind == "Start" else ("Out of reach" if path == null else ("Learn path · %d pt%s" % [cost, "" if cost == 1 else "s"] if can else "Need %d more point%s" % [cost - stats.talent_points, "" if cost - stats.talent_points == 1 else "s"]))
	_learn.disabled = not can
	_learn.add_theme_stylebox_override("normal", HudStyle.piece("barFill", HudStyle.color("accent")) if can else HudStyle.piece("pill"))
	_learn.add_theme_stylebox_override("hover", HudStyle.piece("barFill", HudStyle.color("accentLight")) if can else HudStyle.piece("pill"))
	for k in ["font_color", "font_hover_color", "font_pressed_color"]:
		_learn.add_theme_color_override(k, HudStyle.color("ink") if can else HudStyle.color("muted"))


func _learn_selected() -> void:
	if not stats.learn_path(selected):
		FloatingText.spawn(world, "Not enough talent points", miko.position + Vector2(0, -1.4 * world.px), HudStyle.color("coral"))
	if not person.is_empty():
		Companions.sync(person)
	refresh()


# Gives back every talent (each costs gold), the outermost first so the rest stay joined.
func _reset() -> void:
	var again := true
	while again:
		again = false
		for t in stats.character.talents:
			if stats.can_refund(t.id) and stats.refund(t.id, miko.bag):
				again = true
	var left := 0
	for t in stats.character.talents:
		if stats.unlocked(t.id) and t.kind != "Start":
			left += 1
	if left > 0:
		FloatingText.spawn(world, "Not enough gold to refund %d more" % left, miko.position + Vector2(0, -1.4 * world.px), HudStyle.color("coral"))
	refresh()


# Skills: what her gear and talents give, with the hotbar key each is on (click to put one there).
func _others() -> void:
	for ch in _skills.get_children():
		_skills.remove_child(ch)
		ch.queue_free()
	var all := stats.spell_sources()
	if all.is_empty():
		_skills.add_child(HudStyle.label("Skills from gear and talents show here." if person.is_empty() else "%s knows no spells yet." % owner_name(), 12, "bold", HudStyle.color("faint")))
		return
	if not person.is_empty():
		_companion_skills(all)
		return
	var bar: Hotbar = get_tree().current_scene.get_node_or_null("Hud/Hotbar")
	for s in all:
		var spell: String = s[0]
		var b := Button.new()
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size.y = _k(40)
		var row := HBoxContainer.new()
		row.set_anchors_preset(Control.PRESET_FULL_RECT)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", int(_k(8)))
		var icon := TextureRect.new()
		icon.texture = UiKit.sprite_texture(int(caster.spells.get(spell, {}).get("icon", -1))) if caster != null else null
		icon.custom_minimum_size = Vector2(_k(32), _k(32))
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(icon)
		var names := VBoxContainer.new()
		names.add_theme_constant_override("separation", 0)
		names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		names.add_child(HudStyle.label(spell_name(spell), 13, "bold"))
		names.add_child(HudStyle.label("From " + str(s[1]), 11, "bold", HudStyle.color("muted")))
		row.add_child(names)
		var key := bar.key_name_of(spell) if bar != null else ""
		row.add_child(HudStyle.label(key if key != "" else "Add", 12, "pixel" if key != "" else "bold", HudStyle.color("muted") if key != "" else HudStyle.color("accent")))
		b.add_child(row)
		b.pressed.connect(func():
			if bar != null and not bar.assign(spell):
				FloatingText.spawn(world, "Hotbar is full", miko.position + Vector2(0, -1.4 * world.px), HudStyle.color("coral"))
			_others())
		_skills.add_child(b)


# A companion's skills: what they know and where from, cast by themselves in a fight (not on Sera's hotbar).
func _companion_skills(all: Array) -> void:
	for s in all:
		var spell: String = s[0]
		var row := HBoxContainer.new()
		row.custom_minimum_size.y = _k(40)
		row.add_theme_constant_override("separation", int(_k(8)))
		var icon := TextureRect.new()
		icon.texture = UiKit.sprite_texture(int(Companions.spell(spell).get("icon", -1)))
		icon.custom_minimum_size = Vector2(_k(32), _k(32))
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(icon)
		var names := VBoxContainer.new()
		names.add_theme_constant_override("separation", 0)
		names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		names.add_child(HudStyle.label(Companions.spell_name(spell), 13, "bold"))
		names.add_child(HudStyle.label("From " + str(s[1]), 11, "bold", HudStyle.color("muted")))
		row.add_child(names)
		var sp := Companions.spell(spell)
		row.add_child(HudStyle.label("%s mana" % CharacterStats.fmt(float(sp.get("manaCost", 0))) if not sp.is_empty() else "", 11, "bold", HudStyle.color("mana")))
		_skills.add_child(row)
	_skills.add_child(HudStyle.label("%s casts these in a fight, unasked." % owner_name(), 11, "bold", HudStyle.color("faint")))


## The hover card: the name in its region's colour, kind and region, what it does, its bonus, any skill, what a click does.
func describe(id: String) -> String:
	var t := stats.talent(id)
	var hex := func(c: Color) -> String: return c.to_html(false)
	var muted: String = hex.call(HudStyle.color("muted"))
	var faint: String = hex.call(HudStyle.color("faint"))
	var green: String = hex.call(HudStyle.color("green"))
	var tint := HudStyle.color("text") if str(t.region) == "" else region_color(t.region).lerp(Color.WHITE, 0.25)
	var sub := kind_name(t.kind) + ("" if str(t.region) == "" else " · " + str(t.region))
	var text := "[b][color=#%s]%s[/color][/b]\n[color=#%s]%s[/color]" % [hex.call(tint), t.name, muted, sub.to_upper()]
	if str(t.get("description", "")) != "":
		text += "\n\n" + str(t.description)
	var bonus := CharacterStats.describe(t.perRank)
	if bonus != "":
		text += "\n[color=#%s]%s[/color]" % [green, bonus]
	var g := str(t.get("grantsSpell", ""))
	if g != "" and caster != null:
		var sp: Dictionary = caster.spells.get(g, {})
		text += "\n[color=#%s]Grants %s · %s mana · %ss cooldown[/color]" % [hex.call(HudStyle.color("mana")), spell_name(g), CharacterStats.fmt(float(sp.get("manaCost", 0))), CharacterStats.fmt(float(sp.get("cooldown", 0)))]
	var foot := ""
	if t.kind == "Start":
		foot = "[color=#%s]Where every path begins.[/color]" % faint
	elif stats.unlocked(id):
		foot = ("[color=#%s]Learned[/color][color=#%s] · right-click to refund (%d gold)[/color]" % [green, faint, stats.refund_cost()]) if stats.can_refund(id) \
			else "[color=#%s]Learned[/color][color=#%s] · others hang on it[/color]" % [green, faint]
	else:
		var path: Variant = stats.path_to(id)
		var pts: int = path.size() if path != null else 0
		if path == null:
			foot = "[color=#%s]Can't be reached.[/color]" % faint
		elif pts <= stats.talent_points:
			foot = "[color=#%s]%d talent%s on the path · %d point%s[/color][color=#%s] · click to pick[/color]" % [hex.call(HudStyle.color("accent")), pts, "" if pts == 1 else "s", pts, "" if pts == 1 else "s", faint]
		else:
			foot = "[color=#%s]Needs %d points · you have %d[/color]" % [hex.call(HudStyle.color("coral")), pts, stats.talent_points]
	return text + "\n\n" + foot


class Badge extends Panel:
	var color := Color.WHITE

	func _draw() -> void:
		draw_circle(size / 2.0, size.x / 2.0, Color(color * 0.6, 1.0))
		draw_circle(size / 2.0, size.x / 2.0 * 0.8, color)


## The web itself: drawn, panned and zoomed.
class TalentWeb extends Control:
	const LOCKED := Color(0.2, 0.17, 0.15)
	const LINE_LOCKED := Color(0.5, 0.45, 0.4, 0.55)
	const RED := Color(1, 0.45, 0.4)
	var window: TalentsWindow
	var stats: CharacterStats
	var caster: SpellCaster
	var selection := ""
	var hovered := ""
	var zoom := 1.0
	var pan := Vector2.ZERO          ## where the web's middle is, from the view's middle
	var _fitted := false
	var _press := Vector2.ZERO
	var _pressed := false
	var _dragged := false
	var _query := ""
	var _matches: Array = []
	var _focused := -1
	var _pan_to: Variant = null

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	static func node_size(kind: String) -> float:
		return {"Small": 26.0, "Core": 40.0, "Big": 56.0}.get(kind, 46.0)

	# A talent's place in the view (Unity's y is up).
	func _at(t: Dictionary) -> Vector2:
		return size / 2.0 + pan + Vector2(float(t.position[0]), -float(t.position[1])) * zoom * HudStyle.SCALE

	func fit() -> void:
		var far := Vector2.ZERO
		for t in stats.character.talents:
			far = far.max(Vector2(absf(t.position[0]), absf(t.position[1])))
		far += Vector2(240, 120)
		zoom = clampf(minf(size.x / (2.0 * far.x), size.y / (2.0 * far.y)) / HudStyle.SCALE, 0.25, 1.0)
		pan = Vector2.ZERO
		_pan_to = null
		queue_redraw()

	func zoom_by(f: float, about := Vector2(-1, -1)) -> void:
		var c := size / 2.0 if about.x < 0 else about
		var before := (c - size / 2.0 - pan) / zoom
		zoom = clampf(zoom * f, 0.25, 2.5)
		pan = c - size / 2.0 - before * zoom
		_pan_to = null
		queue_redraw()

	func search(text: String) -> int:
		_query = text.strip_edges().to_lower()
		_matches.clear()
		_focused = -1
		if _query != "":
			for t in stats.character.talents:
				var hay := ("%s %s %s %s %s" % [t.name, t.get("description", ""), t.region, CharacterStats.describe(t.perRank), window.spell_name(str(t.get("grantsSpell", "")))]).to_lower()
				if hay.contains(_query):
					_matches.append(t.id)
		queue_redraw()
		return _matches.size()

	func focus_next() -> void:
		if _matches.is_empty():
			return
		_focused = (_focused + 1) % _matches.size()
		var t := stats.talent(_matches[_focused])
		zoom = maxf(zoom, 0.8)
		_pan_to = -Vector2(float(t.position[0]), -float(t.position[1])) * zoom * HudStyle.SCALE

	func _process(delta: float) -> void:
		var __t := Time.get_ticks_usec()
		_process_timed(delta)
		Perf.add(&"talents_window.TalentWeb.process", __t)


	func _process_timed(delta: float) -> void:
		if not is_visible_in_tree():
			return
		if not _fitted and size.x > 10:
			_fitted = true
			fit()
		if _pan_to != null:
			pan = pan.lerp(_pan_to, 1.0 - exp(-12.0 * delta))
			if pan.distance_squared_to(_pan_to) < 0.5:
				pan = _pan_to
				_pan_to = null
		if _pan_to != null or not _matches.is_empty():
			queue_redraw()

	func _node_at(p: Vector2) -> String:
		var best := ""
		var best_d := INF
		for t in stats.character.talents:
			var r := node_size(t.kind) * 0.5 * zoom * HudStyle.SCALE + 3.0
			var d := p.distance_to(_at(t))
			if d < r and d < best_d:
				best_d = d
				best = t.id
		return best

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
				zoom_by(1.15, event.position)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
				zoom_by(1.0 / 1.15, event.position)
			elif event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE]:
				if event.pressed:
					_pressed = true
					_dragged = false
					_press = event.position
				else:
					_pressed = false
					if not _dragged and event.button_index == MOUSE_BUTTON_LEFT:
						var id := _node_at(event.position)
						if id != "":
							window.select(id)
							window.show_tip(window.describe(id))
			elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
				var id := _node_at(event.position)
				if id != "" and stats.unlocked(id):
					var say := ""
					if not stats.can_refund(id): say = "Other talents hang on this one"
					elif not stats.refund(id, window.miko.bag): say = "Needs %d gold to refund" % stats.refund_cost()
					if say != "":
						FloatingText.spawn(window.world, say, window.miko.position + Vector2(0, -1.4 * window.world.px), Color(1, 0.6, 0.5))
					window.refresh()
					window.show_tip(window.describe(id))
			accept_event()
		elif event is InputEventMouseMotion:
			if _pressed and (_dragged or event.position.distance_to(_press) > 4.0):
				_dragged = true
				pan += event.relative
				_pan_to = null
				queue_redraw()
			var id := _node_at(event.position)
			if id != hovered:
				hovered = id
				if id != "": window.show_tip(window.describe(id))
				else: window.hide_tip()
				queue_redraw()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_MOUSE_EXIT and hovered != "":
			hovered = ""
			window.hide_tip()
			queue_redraw()

	func _draw() -> void:
		var talents: Array = stats.character.talents
		var shown := hovered if hovered != "" else selection
		var path: Variant = stats.path_to(shown) if shown != "" else null
		var on_path := {}
		if path != null:
			for n in path:
				on_path[n] = true
		var affordable: bool = path != null and path.size() <= stats.talent_points
		var k := zoom * HudStyle.SCALE
		var searching := _query != ""
		# Each region's label: its name and how much of it is learnt, past its farthest talent.
		var regions := {}
		for t in talents:
			if str(t.region) == "":
				continue
			var p := Vector2(float(t.position[0]), -float(t.position[1]))
			if not regions.has(t.region): regions[t.region] = {"far": p, "n": 0, "of": 0}
			var g: Dictionary = regions[t.region]
			if p.length_squared() > g.far.length_squared(): g.far = p
			if t.kind != "Start":
				g.of += 1
				if stats.unlocked(t.id): g.n += 1
		var bold := HudStyle.font("bold")
		for region in regions:
			var g: Dictionary = regions[region]
			var dir: Vector2 = g.far.normalized() if g.far.length() > 1.0 else Vector2.UP
			var at: Vector2 = size / 2.0 + pan + (g.far + dir * 40.0) * k
			var text := "%s  %d/%d" % [str(region).to_upper(), g.n, g.of]
			var px := roundi(12 * HudStyle.SCALE * clampf(zoom, 0.6, 1.4))
			var w := bold.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x + 34
			var h := px * 2.4
			var box := Rect2(at - Vector2(w * (0.5 - dir.x * 0.5), h * (0.5 - dir.y * 0.5)), Vector2(w, h))
			draw_style_box(HudStyle.piece("pill"), box)
			draw_circle(box.position + Vector2(14, h / 2.0), 5, TalentsWindow.region_color(region))
			draw_string(bold, box.position + Vector2(26, h / 2.0 + px * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, HudStyle.color("text"))
		# Lines under the talents, one per link.
		var drawn := {}
		for t in talents:
			for n in stats.neighbours(t.id):
				var key: String = t.id + "|" + n if t.id < n else n + "|" + t.id
				if drawn.has(key):
					continue
				drawn[key] = true
				var b := stats.talent(n)
				var ua := stats.unlocked(t.id)
				var ub := stats.unlocked(n)
				var lit: bool = (ua or on_path.has(t.id)) and (ub or on_path.has(n))
				var c: Color = TalentsWindow.region_color(b.region) if ua and ub else ((HudStyle.color("accent") if affordable else RED) if lit else LINE_LOCKED)
				if searching and not (_matches.has(t.id) and _matches.has(n)):
					c.a *= 0.35
				draw_line(_at(t), _at(b), c, maxf(1.5, 4.0 * k), true)
		# The talents.
		var pulse := 1.2 + 0.15 * sin(Time.get_ticks_msec() / 1000.0 * 6.0)
		for t in talents:
			var region := TalentsWindow.region_color(t.region)
			var c: Color
			if stats.unlocked(t.id): c = region
			elif on_path.has(t.id): c = HudStyle.color("accent") if affordable else RED
			else:
				var near := false
				for n in stats.neighbours(t.id):
					if stats.unlocked(n): near = true
				c = LOCKED.lerp(region, 0.55 if near else 0.18)
			if searching and not _matches.has(t.id):
				c = Color(c.lerp(LOCKED, 0.75), 0.5)
			var sc := 1.18 if t.id == hovered else (1.25 if t.id == selection else 1.0)
			if searching and _matches.has(t.id) and t.id != hovered:
				sc = pulse + (0.2 if _matches.find(t.id) == _focused else 0.0)
			var r := node_size(t.kind) * 0.5 * k * sc
			var p := _at(t)
			if t.kind == "Big":
				var pts := PackedVector2Array([p + Vector2(0, -r * 1.2), p + Vector2(r * 1.2, 0), p + Vector2(0, r * 1.2), p + Vector2(-r * 1.2, 0)])
				draw_colored_polygon(pts, Color(c * 0.55, c.a))
				var inner := PackedVector2Array()
				for q in pts:
					inner.append(p + (q - p) * 0.78)
				draw_colored_polygon(inner, c)
			else:
				draw_circle(p, r, Color(c * 0.55, c.a))
				draw_circle(p, r * 0.78, c)
			var g := str(t.get("grantsSpell", ""))
			if g != "" and caster != null:
				var icon := UiKit.sprite_texture(int(caster.spells.get(g, {}).get("icon", -1)))
				if icon != null:
					var s := r * 1.24
					draw_texture_rect(icon, Rect2(p - Vector2(s, s) / 2.0, Vector2(s, s)), false, Color.WHITE if stats.unlocked(t.id) or on_path.has(t.id) else Color(1, 1, 1, 0.45))
			if t.id == selection:
				draw_arc(p, r + 3, 0, TAU, 32, HudStyle.color("accentLight"), 2.0, true)
