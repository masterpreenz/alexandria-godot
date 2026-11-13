class_name TalentsWindow
extends PanelContainer
## The Talents tab (P): the tree on the left, with a search, a key to its colours and buttons to move along it and
## zoom; on the right the points to spend, the picked talent (what it does, its ranks, what learning it costs, and
## Learn), the skills Miko has from gear and talents (click one to put it on the hotbar) and Reset.
##
## The tree runs left to right as she levels: five groups side by side (Attack Shikigami, Healing Shikigami, Meteor,
## Both Shikigami, Shield Shikigami), each shut until its level. Its rows: Offensive on top, the Core skills in the
## middle (one chain, each needing the one before), Supportive below, each group's hanging off its core skill; and
## along the bottom Life & Body, learnt in any order. Small talents are small dots, notables bigger, the core skills
## the biggest (diamonds, with their skill's icon); a talent with ranks shows how far it's learnt (2/4). Lit in its
## group's colour when learnt, brighter when it can be learnt now. Hovering one lights what learning it takes and says
## what it costs; clicking picks it; right-click a learnt one to give a rank back, for gold. Drag or scroll to move
## along it, Ctrl+scroll to zoom.
##
## Whose talents they are is picked along the top of the right side: Sera's, or a companion's (theirs are spent the
## same way, from their own points; their skills are the ones they cast by themselves in a fight). Each is shown on
## their own tree (Miyu's of ice and water), drawn the same way. A talent that can't be learnt yet at any level (it
## waits on a book, or on something to happen: Miyu's advanced ice) is dimmed with a small lock, and says why.

const SIDE_W := 352.0
const WEB := Vector2(720, 500)

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
	_search.placeholder_text = "Search talents, e.g. meteor, defense"
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
	bar.add_child(HudStyle.label("Drag or scroll to move · Ctrl+scroll zooms · Right-click refunds (%d gold)" % stats.refund_cost(), 11, "bold", HudStyle.color("faint")))
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
	legend.text = "%s Learned   %s Can learn   %s What it takes   %s Locked" % [dot.call(Color(1, 0.5, 0.32)), dot.call(Color(0.6, 0.42, 0.3)), dot.call(HudStyle.color("accent")), dot.call(Color(0.24, 0.2, 0.17))]
	under.add_child(legend)
	for z in [["«", -1.0], ["»", -2.0], ["+", 1.25], ["−", 0.8], ["Fit", 0.0]]:
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
	pl.add_child(HudStyle.label("+%d each level" % stats.points_per_level(), 11, "bold", HudStyle.color("muted")))
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
	var reset := HudStyle.button("Reset all talents · %d gold a rank" % stats.refund_cost(), 12, "pill", HudStyle.color("muted"))
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
	elif f < 0.0:
		web.scroll_to(0.0 if f > -1.5 else 1.0)
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
	return Playable.name_now() if person.is_empty() else str(person.get("name", "?"))


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
		var b := HudStyle.button(Playable.name_now() if p.is_empty() else str(p.name), 12, "pill", HudStyle.color("text") if here else HudStyle.color("muted"))
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
	if (selected == "" or stats.talent(selected).is_empty()) and not stats.character.talents.is_empty():
		selected = stats.character.talents[0].id
	web.selection = selected
	web.queue_redraw()
	_picked()
	_others()


func select(id: String) -> void:
	selected = id
	refresh()
	web.reveal(id)


static func color_from(c: Array) -> Color:
	return Color(float(c[0]), float(c[1]), float(c[2]), 1.0) if c.size() >= 3 else Color.WHITE


## A talent's colour: its group's, or (Life & Body) its line's.
func color_of(t: Dictionary) -> Color:
	var g := int(t.get("group", -1))
	var groups: Array = stats.character.get("groups", [])
	if g >= 0 and g < groups.size():
		return color_from(groups[g].get("color", []))
	var lines: Array = stats.character.get("lifeLines", [])
	var ln := int(t.get("line", 0))
	return color_from(lines[ln].get("color", [])) if ln >= 0 and ln < lines.size() else Color(0.98, 0.92, 0.82)


## The group a talent is in, by name (Life & Body's line for theirs).
func group_name(t: Dictionary) -> String:
	var g := int(t.get("group", -1))
	var groups: Array = stats.character.get("groups", [])
	if g >= 0 and g < groups.size():
		return str(groups[g].name)
	var lines: Array = stats.character.get("lifeLines", [])
	var ln := int(t.get("line", 0))
	return str(lines[ln].name) if ln >= 0 and ln < lines.size() else ""


## What kind of talent it is and where: "Core skill · Meteor", "Offensive · Attack Shikigami", "Life & Body · Hearth".
func place_name(t: Dictionary) -> String:
	var row := str(t.get("row", ""))
	if row == "Core":
		row = "Core skill" if t.kind == "Big" else "Core"
	return "%s · %s" % [row, group_name(t)]


## What it does in words (bbcode): its stats (each rank, and so far), its milestones, the skill it grants.
func effect_text(t: Dictionary) -> String:
	var hex := func(c: Color) -> String: return c.to_html(false)
	var green: String = hex.call(HudStyle.color("green"))
	var faint: String = hex.call(HudStyle.color("faint"))
	var text := ""
	var most := stats.max_rank(t.id)
	var r := stats.rank(t.id)
	var bonus := CharacterStats.describe(t.perRank)
	if most <= 1:
		if bonus != "":
			text += "\n[color=#%s]%s[/color]" % [green, bonus]
	else:
		if bonus != "":
			text += "\n[color=#%s]Each rank: %s[/color]" % [green, bonus]
		if r > 0:
			text += "\n[color=#%s]Now (%d/%d): %s[/color]" % [hex.call(HudStyle.color("muted")), r, most, CharacterStats.describe(CharacterStats.talent_stats(t, r))]
	var ms: Dictionary = t.get("milestones", {})
	for k in ms:
		var got := r >= int(k)
		text += "\n[color=#%s]%s Rank %s: %s[/color]" % [green if got else faint, "●" if got else "○", str(k), CharacterStats.describe(ms[k])]
	var g := str(t.get("grantsSpell", ""))
	if g != "" and caster != null:
		var sp: Dictionary = caster.spells.get(g, {})
		text += "\n[color=#%s]Grants %s · %s mana · %ss cooldown[/color]" % [hex.call(HudStyle.color("mana")), spell_name(g), CharacterStats.fmt(float(sp.get("manaCost", 0))), CharacterStats.fmt(float(sp.get("cooldown", 0)))]
	return text


## The level learning [param id] waits on (its own, or that of something it needs first), or 0 if none.
func waits_on(id: String) -> int:
	var most := 0
	var queue := [id]
	while not queue.is_empty():
		var n: String = queue.pop_front()
		if stats.level_for(n) > stats.level:
			most = maxi(most, stats.level_for(n))
		for need in stats.talent(n).get("needs", []):
			if not stats.unlocked(need):
				queue.append(need)
	return most


func spell_name(id: String) -> String:
	return str(caster.spells.get(id, {}).get("name", id)) if caster != null else id


func _picked() -> void:
	var t := stats.talent(selected)
	if t.is_empty():
		return
	var colour := color_of(t)
	var learned := stats.unlocked(t.id)
	var full := stats.maxed(t.id)
	(_badge as Badge).color = colour if learned else Color(colour * 0.35, 1.0)
	_badge.queue_redraw()
	var most := stats.max_rank(t.id)
	_name.text = str(t.name) + ("" if most <= 1 else "  %d/%d" % [stats.rank(t.id), most])
	_kind.text = place_name(t)
	_kind.add_theme_color_override("font_color", colour)
	_desc.text = (str(t.get("description", "")) + effect_text(t)).strip_edges()
	var path: Variant = stats.path_to(t.id)
	var cost: int = path.size() if path != null else 0
	var can: bool = path != null and cost > 0 and cost <= stats.talent_points
	var why := stats.barred_on_path(t.id) if path == null and not full else ""
	var refund := ("Right-click it to give a rank back (%d gold)." % stats.refund_cost()) if stats.can_refund(t.id) else "Others need it."
	if full:
		_path.text = ("Learned. " if most <= 1 else "Learned in full. ") + refund
	elif why != "":
		_path.text = stats.lock_text(why)
	elif path == null:
		_path.text = "Opens at level %d (you're %d)." % [waits_on(t.id), stats.level]
	elif cost == 1:
		_path.text = ("Rank %d of %d next: 1 point." % [stats.rank(t.id) + 1, most]) if learned else "Learning this takes 1 point."
	else:
		var names := []
		for n in path:
			names.append(str(stats.talent(n).name))
		_path.text = "Learning this takes what it needs first: %s. %d points." % [" → ".join(names), cost]
	if full:
		_learn.text = "Learned"
	elif why != "":
		_learn.text = "Can't learn yet" if not why.begins_with("book:") else "Needs the book"
	elif path == null:
		_learn.text = "Opens at Lv %d" % waits_on(t.id)
	elif not can:
		_learn.text = "Need %d more point%s" % [cost - stats.talent_points, "" if cost - stats.talent_points == 1 else "s"]
	elif learned:
		_learn.text = "Rank up to %d/%d · 1 pt" % [stats.rank(t.id) + 1, most]
	else:
		_learn.text = "Learn · %d pt%s" % [cost, "" if cost == 1 else "s"]
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
		if stats.rank(t.id) > stats.gifted_rank(t.id) and t.kind != "Start":
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


## The hover card: the name in its group's colour (and its ranks), where it is, what it does, its stats and
## milestones, any skill, and what learning it takes.
func describe(id: String) -> String:
	var t := stats.talent(id)
	var hex := func(c: Color) -> String: return c.to_html(false)
	var muted: String = hex.call(HudStyle.color("muted"))
	var faint: String = hex.call(HudStyle.color("faint"))
	var green: String = hex.call(HudStyle.color("green"))
	var tint := color_of(t).lerp(Color.WHITE, 0.25)
	var most := stats.max_rank(id)
	var ranks := "" if most <= 1 else "  [color=#%s]%d/%d[/color]" % [muted, stats.rank(id), most]
	var text := "[b][color=#%s]%s[/color][/b]%s\n[color=#%s]%s[/color]" % [hex.call(tint), t.name, ranks, muted, place_name(t).to_upper()]
	if str(t.get("description", "")) != "":
		text += "\n\n" + str(t.description)
	text += effect_text(t)
	var foot := ""
	var path: Variant = stats.path_to(id)
	if stats.maxed(id):
		foot = ("[color=#%s]Learned[/color][color=#%s] · right-click to give a rank back (%d gold)[/color]" % [green, faint, stats.refund_cost()]) if stats.can_refund(id) \
			else "[color=#%s]Learned[/color][color=#%s] · others need it[/color]" % [green, faint]
	elif path == null and stats.barred_on_path(id) != "":
		foot = "[color=#%s]%s[/color]" % [hex.call(HudStyle.color("coral")), stats.lock_text(stats.barred_on_path(id))]
	elif path == null:
		foot = "[color=#%s]Opens at level %d[/color]" % [hex.call(HudStyle.color("coral")), waits_on(id)]
	else:
		var pts: int = path.size()
		if pts <= stats.talent_points:
			var what := ("Rank %d next" % (stats.rank(id) + 1)) if stats.unlocked(id) else ("%d talent%s" % [pts, "" if pts == 1 else "s"])
			foot = "[color=#%s]%s · %d point%s[/color][color=#%s] · click to pick[/color]" % [hex.call(HudStyle.color("accent")), what, pts, "" if pts == 1 else "s", faint]
		else:
			foot = "[color=#%s]Needs %d point%s · you have %d[/color]" % [hex.call(HudStyle.color("coral")), pts, "" if pts == 1 else "s", stats.talent_points]
	return text + "\n\n" + foot


class Badge extends Panel:
	var color := Color.WHITE

	func _draw() -> void:
		draw_circle(size / 2.0, size.x / 2.0, Color(color * 0.6, 1.0))
		draw_circle(size / 2.0, size.x / 2.0 * 0.8, color)


## The tree itself: drawn, panned (drag, or scroll) and zoomed (Ctrl+scroll).
class TalentWeb extends Control:
	const LOCKED := Color(0.2, 0.17, 0.15)
	const LINE_LOCKED := Color(0.5, 0.45, 0.4, 0.55)
	const RED := Color(1, 0.45, 0.4)
	const SLOT := 72.0              ## a talent's room along a row
	const GAP := 34.0               ## between one group and the next
	const LEFT := 112.0             ## the row names' room, at the left
	const TOP := 54.0               ## the groups' names' room, at the top
	const ROW_Y := {"Offensive": 100.0, "Core": 196.0, "Supportive": 292.0}
	const LIFE_Y := [418.0, 494.0]  ## Life & Body: Hearth's line, Body's
	const LIFE_TOP := 352.0
	const BOTTOM := 534.0
	var window: TalentsWindow
	var stats: CharacterStats
	var caster: SpellCaster
	var selection := ""
	var hovered := ""
	var zoom := 1.0
	var pan := Vector2.ZERO          ## where the tree's top left is, in the view
	var _fitted := false
	var _press := Vector2.ZERO
	var _pressed := false
	var _dragged := false
	var _query := ""
	var _matches: Array = []
	var _focused := -1
	var _pan_to: Variant = null
	var _pos := {}                   ## talent id -> its place on the tree (unscaled)
	var _boxes: Array = []           ## each group's column: {x, w, group}
	var _width := 0.0
	var _laid_for: Array = []        ## the talents laid out (another tree shown: laid out afresh)

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	static func node_size(kind: String) -> float:
		return {"Small": 26.0, "Core": 38.0, "Big": 50.0}.get(kind, 46.0)

	# Where every talent goes: the groups side by side, each as wide as its longest row, left to right by level; Life
	# & Body's two lines along the bottom, evenly across the whole width.
	func _layout() -> void:
		_laid_for = stats.character.talents
		_pos.clear()
		_boxes.clear()
		var groups: Array = stats.character.get("groups", [])
		var cols := []
		cols.resize(groups.size())
		cols.fill(1)
		var life := [0, 0]
		for t in stats.character.talents:
			var g := int(t.get("group", -1))
			if g >= 0 and g < groups.size():
				cols[g] = maxi(cols[g], int(t.col) + 1)
			else:
				var ln := clampi(int(t.get("line", 0)), 0, 1)
				life[ln] = maxi(life[ln], int(t.col) + 1)
		var x := LEFT
		for g in groups.size():
			var w := maxf(3.0, float(cols[g])) * SLOT
			_boxes.append({"x": x, "w": w, "group": g})
			x += w + GAP
		_width = maxf(x - GAP + 24.0, LEFT + float(maxi(life[0], life[1])) * SLOT + 24.0)
		var step := (_width - 24.0 - LEFT) / float(maxi(1, maxi(life[0], life[1])))
		for t in stats.character.talents:
			var g := int(t.get("group", -1))
			if g >= 0 and g < _boxes.size():
				_pos[t.id] = Vector2(float(_boxes[g].x) + SLOT * (float(t.col) + 0.5), float(ROW_Y.get(str(t.row), 196.0)))
			else:
				_pos[t.id] = Vector2(LEFT + step * (float(t.col) + 0.5), LIFE_Y[clampi(int(t.get("line", 0)), 0, 1)])

	func _k() -> float:
		return zoom * HudStyle.SCALE

	# A place on the tree, in the view.
	func _view(p: Vector2) -> Vector2:
		return pan + p * _k()

	func _at(t: Dictionary) -> Vector2:
		if _pos.is_empty() or not is_same(_laid_for, stats.character.talents):
			_layout()
		return _view(_pos.get(t.id, Vector2.ZERO))

	## The tree to its height, from its left end.
	func fit() -> void:
		if _pos.is_empty() or not is_same(_laid_for, stats.character.talents):
			_layout()
		zoom = clampf(size.y / (BOTTOM + 10.0) / HudStyle.SCALE, 0.4, 1.4)
		pan = Vector2(0, maxf(0.0, (size.y - BOTTOM * _k()) / 2.0))
		_pan_to = null
		queue_redraw()

	## Scrolls along to [param frac] of the way (0 its left end, 1 its right).
	func scroll_to(frac: float) -> void:
		pan.x = -clampf(frac, 0.0, 1.0) * maxf(0.0, _width * _k() - size.x)
		_pan_to = null
		queue_redraw()

	# Never let it be dragged off: some of the tree always stays in view.
	func _keep_in() -> void:
		var w := _width * _k()
		var h := BOTTOM * _k()
		pan.x = clampf(pan.x, minf(0.0, size.x - w), maxf(0.0, size.x - w) if w < size.x else 0.0)
		pan.y = clampf(pan.y, minf(0.0, size.y - h), maxf(0.0, size.y - h))

	func zoom_by(f: float, about := Vector2(-1, -1)) -> void:
		var c := size / 2.0 if about.x < 0 else about
		var before := (c - pan) / zoom
		zoom = clampf(zoom * f, 0.4, 2.0)
		pan = c - before * zoom
		_keep_in()
		_pan_to = null
		queue_redraw()

	func search(text: String) -> int:
		_query = text.strip_edges().to_lower()
		_matches.clear()
		_focused = -1
		if _query != "":
			for t in stats.character.talents:
				var hay := ("%s %s %s %s %s %s" % [t.name, t.get("description", ""), t.region, window.group_name(t), CharacterStats.describe(t.perRank), window.spell_name(str(t.get("grantsSpell", "")))]).to_lower()
				if hay.contains(_query):
					_matches.append(t.id)
		queue_redraw()
		return _matches.size()

	func focus_next() -> void:
		if _matches.is_empty():
			return
		_focused = (_focused + 1) % _matches.size()
		var t := stats.talent(_matches[_focused])
		var at: Vector2 = _pos.get(t.id, Vector2.ZERO)
		_pan_to = Vector2(size.x / 2.0 - at.x * _k(), pan.y)

	## Scrolls [param id] into view if it's off to the side (under the row names, or past the right edge).
	func reveal(id: String) -> void:
		if _pos.is_empty() or not is_same(_laid_for, stats.character.talents):
			_layout()
		if not _pos.has(id):
			return
		var x := _view(_pos[id]).x
		if x < LEFT * _k() or x > size.x - 40.0:
			_pan_to = Vector2(size.x / 2.0 - float(_pos[id].x) * _k(), pan.y)

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
			_keep_in()
			if pan.distance_squared_to(_pan_to) < 0.5:
				pan = _pan_to
				_keep_in()
				_pan_to = null
		if _pan_to != null or not _matches.is_empty() or selection != "":   # (the picked one's glow breathes)
			queue_redraw()

	func _node_at(p: Vector2) -> String:
		if p.x < (LEFT - 14.0) * _k():
			return ""   # (under the row names)
		var best := ""
		var best_d := INF
		for t in stats.character.talents:
			var r := node_size(t.kind) * 0.6 * _k() + 4.0
			var d := p.distance_to(_at(t))
			if d < r and d < best_d:
				best_d = d
				best = t.id
		return best

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var wheel: int = [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT].find(event.button_index)
			if wheel >= 0 and event.pressed:
				if event.ctrl_pressed and wheel < 2:
					zoom_by(1.15 if wheel == 0 else 1.0 / 1.15, event.position)
				else:
					# Scrolling runs along the tree.
					pan.x += (90.0 if wheel % 2 == 0 else -90.0) * HudStyle.SCALE
					_keep_in()
					_pan_to = null
					queue_redraw()
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
					if not stats.can_refund(id): say = "Other talents need this one"
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
				_keep_in()
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
		elif what == NOTIFICATION_RESIZED and _fitted:
			_keep_in()

	# Whether [param id] could be learnt now (its group open, what it needs learnt), not yet in full.
	func _open(id: String) -> bool:
		if stats.maxed(id) or stats.level_for(id) > stats.level or stats.barred(id) != "":
			return false
		for n in stats.talent(id).get("needs", []):
			if not stats.unlocked(n):
				return false
		return true

	func _draw() -> void:
		if _pos.is_empty() or not is_same(_laid_for, stats.character.talents):
			_layout()
		var talents: Array = stats.character.talents
		var groups: Array = stats.character.get("groups", [])
		var shown := hovered if hovered != "" else selection
		var path: Variant = stats.path_to(shown) if shown != "" else null
		var on_path := {}
		if path != null:
			for n in path:
				on_path[n] = true
		var affordable: bool = path != null and path.size() <= stats.talent_points
		var k := _k()
		var searching := _query != ""
		var bold := HudStyle.font("bold")
		var px := roundi(12 * k)
		var lw := maxf(1.5, 3.0 * k)
		# Each group's column: a soft panel in its colour, its name, the level it opens at and how much is learnt;
		# dimmed while it's beyond their level.
		for box in _boxes:
			var g: Dictionary = groups[box.group]
			var gc := TalentsWindow.color_from(g.get("color", [1, 1, 1, 1]))
			var shut := int(g.get("level", 1)) > stats.level
			var r := Rect2(_view(Vector2(float(box.x) - 6.0, 8.0)), Vector2(float(box.w) + 12.0, ROW_Y.Supportive + 40.0) * k)
			draw_style_box(HudStyle.piece("well", Color(gc.lerp(Color.WHITE, 0.2), 0.16 if shut else 0.42)), r)
			var n := 0
			var of := 0
			for t in talents:
				if int(t.get("group", -1)) == int(box.group):
					of += stats.max_rank(t.id)
					n += stats.rank(t.id)
			var head := str(g.name).to_upper()
			var tc: Color = HudStyle.color("faint") if shut else gc.lerp(Color.WHITE, 0.35)
			draw_string(bold, r.position + Vector2(10 * k, 22 * k), head, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 20 * k, px, tc)
			var lv := "Lv %d" % int(g.get("level", 1))
			var sub := ("%s · locked" % lv) if shut else ("%s · %d/%d" % [lv, n, of])
			draw_string(bold, r.position + Vector2(10 * k, 38 * k), sub, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 20 * k, roundi(10 * k), HudStyle.color("coral") if shut else HudStyle.color("muted"))
		# Life & Body: one long band under the groups, its two lines named.
		var lifebox := Rect2(_view(Vector2(LEFT - 6.0, LIFE_TOP)), Vector2(_width - LEFT - 12.0, BOTTOM - LIFE_TOP - 6.0) * k)
		draw_style_box(HudStyle.piece("well", Color(0.85, 0.8, 0.7, 0.32)), lifebox)
		var lines: Array = stats.character.get("lifeLines", [])
		# Its levels: where along it the talents of each level begin.
		var marked := {}
		for t in talents:
			if int(t.get("group", -1)) >= 0:
				continue
			var lv := stats.level_for(t.id)
			var key := "%d|%d" % [lv, int(t.get("line", 0))]
			if lv > 1 and not marked.has(key):
				marked[key] = true
				var p: Vector2 = _pos[t.id]
				var at := _view(p + Vector2(-SLOT * 0.42, -30.0))
				draw_line(_view(p + Vector2(-SLOT * 0.5, -26.0)), _view(p + Vector2(-SLOT * 0.5, 26.0)), Color(1, 1, 1, 0.12), maxf(1.0, k))
				draw_string(bold, at, "Lv %d" % lv, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(10 * k), HudStyle.color("coral") if lv > stats.level else HudStyle.color("faint"))
		# The lines: along the core; from each core skill up and down to its own; between a row's chained talents.
		for t in talents:
			for nid in t.get("needs", []):
				var b := stats.talent(nid)
				if b.is_empty():
					continue
				var ua := stats.unlocked(t.id)
				var ub := stats.unlocked(nid)
				var lit: bool = (ua or on_path.has(t.id)) and (ub or on_path.has(nid))
				var c: Color = color_of(b) if ua and ub else ((HudStyle.color("accent") if affordable else RED) if lit else LINE_LOCKED)
				if searching and not (_matches.has(t.id) and _matches.has(nid)):
					c.a *= 0.35
				var a: Vector2 = _pos[nid]
				var e: Vector2 = _pos[t.id]
				if is_equal_approx(a.y, e.y):
					draw_line(_view(a), _view(e), c, lw, true)
				else:
					# Out of the core skill to halfway between the rows, along, then into the talent.
					var mid := (a.y + e.y) / 2.0
					draw_polyline(PackedVector2Array([_view(a), _view(Vector2(a.x, mid)), _view(Vector2(e.x, mid)), _view(e)]), c, lw, true)
		# The talents.
		var pulse := 1.2 + 0.15 * sin(Time.get_ticks_msec() / 1000.0 * 6.0)
		for t in talents:
			var tint := color_of(t)
			var barred := stats.barred(t.id) != ""
			var shut := stats.level_for(t.id) > stats.level or barred
			var c: Color
			if stats.unlocked(t.id): c = tint
			elif on_path.has(t.id): c = HudStyle.color("accent") if affordable else RED
			elif shut: c = LOCKED.lerp(tint, 0.1)
			else: c = LOCKED.lerp(tint, 0.45 if _open(t.id) else 0.2)
			if searching and not _matches.has(t.id):
				c = Color(c.lerp(LOCKED, 0.75), 0.5)
			var sc := 1.08 if t.id == hovered or t.id == selection else 1.0
			if searching and _matches.has(t.id) and t.id != hovered:
				sc = pulse + (0.2 if _matches.find(t.id) == _focused else 0.0)
			var r := node_size(t.kind) * 0.5 * k * sc
			var p := _at(t)
			# Learnt in part: the rim only half lit.
			var rim := Color(c * 0.55, c.a)
			if stats.unlocked(t.id) and not stats.maxed(t.id):
				rim = Color(tint * 0.35, c.a)
			# Picked: a soft glow behind it and a fine outline hugging its own shape, breathing a little.
			if t.id == selection:
				var gold := HudStyle.color("accentLight")
				var breath := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * 3.0)
				if t.kind == "Big":
					draw_colored_polygon(_diamond(p, r * 1.2 * (1.38 + 0.05 * breath)), Color(gold, 0.16 + 0.08 * breath))
					var edge := _diamond(p, r * 1.2 * 1.2)
					edge.append(edge[0])
					draw_polyline(edge, gold, 2.0 * k, true)
				else:
					draw_circle(p, r * (1.42 + 0.05 * breath), Color(gold, 0.16 + 0.08 * breath))
					draw_arc(p, r * 1.18, 0, TAU, 48, gold, 2.0 * k, true)
			if t.kind == "Big":
				var pts := _diamond(p, r * 1.2)
				draw_colored_polygon(pts, rim)
				var inner := PackedVector2Array()
				for q in pts:
					inner.append(p + (q - p) * 0.78)
				draw_colored_polygon(inner, c)
			else:
				draw_circle(p, r, rim)
				draw_circle(p, r * 0.78, c)
			var icons: Array = t.get("icons", [])
			if str(t.get("grantsSpell", "")) != "":
				icons = [t.grantsSpell]
			if caster != null and not icons.is_empty():
				var s := r * (1.24 if icons.size() == 1 else 0.9)
				for i in icons.size():
					var icon := UiKit.sprite_texture(int(caster.spells.get(icons[i], {}).get("icon", -1)))
					if icon != null:
						var off := Vector2((i - (icons.size() - 1) / 2.0) * s * 0.75, 0)
						draw_texture_rect(icon, Rect2(p + off - Vector2(s, s) / 2.0, Vector2(s, s)), false, Color.WHITE if stats.unlocked(t.id) or on_path.has(t.id) else Color(1, 1, 1, 0.4))
			if barred and not stats.unlocked(t.id):
				_lock(p + Vector2(r * 0.72, -r * 0.72), maxf(5.0, r * 0.36))
			elif shut and not stats.unlocked(t.id):
				draw_string(bold, p + Vector2(-r, px * 0.35), "Lv%d" % stats.level_for(t.id), HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, roundi(9 * k), Color(1, 1, 1, 0.35))
			# Ranks: how far it's learnt, under it.
			if stats.max_rank(t.id) > 1:
				var txt := "%d/%d" % [stats.rank(t.id), stats.max_rank(t.id)]
				var fs := roundi(10 * k)
				var tw := bold.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 8.0 * k
				var under := r * (1.2 if t.kind == "Big" else 1.0)
				var pill := Rect2(p + Vector2(-tw / 2.0, under - 4.0 * k), Vector2(tw, fs + 3.0 * k))
				draw_rect(pill, Color(HudStyle.color("ink"), 0.85))
				draw_string(bold, pill.position + Vector2(4.0 * k, fs * 0.92), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, HudStyle.color("accentLight") if stats.maxed(t.id) else (tint.lerp(Color.WHITE, 0.3) if stats.unlocked(t.id) else HudStyle.color("faint")))
		# The rows' names, kept at the left however far along it's scrolled.
		var band := Rect2(Vector2.ZERO, Vector2((LEFT - 14.0) * k, size.y))
		draw_rect(band, Color(HudStyle.color("ink"), 0.97))
		draw_line(Vector2(band.size.x, 0), Vector2(band.size.x, size.y), Color(1, 1, 1, 0.08), 1.0)
		var row_names := {"Offensive": HudStyle.color("coral"), "Core": HudStyle.color("accentLight"), "Supportive": HudStyle.color("green")}
		for row in row_names:
			var y: float = pan.y + float(ROW_Y[row]) * k
			draw_string(bold, Vector2(10 * k, y + px * 0.35), str(row).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, band.size.x - 12 * k, px, row_names[row])
		draw_string(bold, Vector2(10 * k, pan.y + (LIFE_TOP + 22.0) * k), "LIFE & BODY", HORIZONTAL_ALIGNMENT_LEFT, band.size.x - 12 * k, px, HudStyle.color("text"))
		for i in mini(lines.size(), 2):
			draw_string(bold, Vector2(14 * k, pan.y + LIFE_Y[i] * k + px * 0.35), str(lines[i].name), HORIZONTAL_ALIGNMENT_LEFT, band.size.x - 16 * k, roundi(11 * k), TalentsWindow.color_from(lines[i].get("color", [1, 1, 1, 1])))
		# More of it off to the side: a soft edge saying so.
		if pan.x + _width * k > size.x + 2.0:
			_fade(Rect2(size.x - 28.0, 0, 28.0, size.y), false)
		if pan.x < -2.0:
			_fade(Rect2(band.size.x, 0, 28.0, size.y), true)

	# A diamond round [param p], [param half] from its middle to each point.
	# A small padlock at [param p]: a talent that can't be learnt yet, whatever the level (it waits on something).
	func _lock(p: Vector2, sz: float) -> void:
		var ink := HudStyle.color("ink")
		var body := Rect2(p + Vector2(-sz, -sz * 0.2), Vector2(sz * 2.0, sz * 1.5))
		draw_arc(p + Vector2(0, -sz * 0.2), sz * 0.62, PI, TAU, 16, ink, sz * 0.62, true)
		draw_arc(p + Vector2(0, -sz * 0.2), sz * 0.62, PI, TAU, 16, HudStyle.color("coral"), sz * 0.32, true)
		draw_rect(body.grow(sz * 0.18), ink)
		draw_rect(body, HudStyle.color("coral"))
		draw_circle(body.get_center(), sz * 0.22, ink)

	func _diamond(p: Vector2, half: float) -> PackedVector2Array:
		return PackedVector2Array([p + Vector2(0, -half), p + Vector2(half, 0), p + Vector2(0, half), p + Vector2(-half, 0)])

	func _fade(r: Rect2, from_left: bool) -> void:
		var ink := HudStyle.color("ink")
		var a := Color(ink, 0.0)
		var b := Color(ink, 0.7)
		var cs := PackedColorArray([b, a, a, b] if from_left else [a, b, b, a])
		draw_polygon(PackedVector2Array([r.position, r.position + Vector2(r.size.x, 0), r.end, r.position + Vector2(0, r.size.y)]), cs)

	func color_of(t: Dictionary) -> Color:
		return window.color_of(t)
