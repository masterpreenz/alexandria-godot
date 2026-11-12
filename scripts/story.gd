class_name Story
extends Node
## The story's opening (data/intro.json), a beat at a time, on a new game: Sera on the road at the map's south-east,
## learning to move and fight and gather, making camp as night comes, cooking, sleeping; woken by a villager running
## for help; the village overrun in the night, most of its people lost; the crystal set to ward it; the survivors'
## questions; rebuilding, feeding them, the elder's question; a night's rest; then the morning (the elder's rumor about
## Miyu follows from "intro_done"). Each beat: what to do (the card at the top), how (its hint), what happens as it
## starts and ends. Where it's at is saved (world.story); a game that didn't start with it hasn't one.

const FILE := "res://data/intro.json"

static var active: Story

var world: World
var miko: Miko
var people: Villagers
var monster_data: Dictionary
var game: Node2D
var d: Dictionary
var beat := -1                      ## the beat on now (-1: the story isn't running)
var _from := {}                     ## what things were as the beat began (kills, bag, storage...)
var _walked := 0.0
var _last_at := Vector2.INF
var _card: PanelContainer
var _marks: StoryMarks               ## arrows to (and outlines on) the monsters it sends at her
var _title: Label
var _hint: RichTextLabel
var _doomed_left: Array = []        ## the attack's doomed (names), still to fall
var _next_doom := 0.0
var _fires: Array = []              ## the burning houses' smoke and glow
var _panned := false
var _warded := true                 ## whether the village keeps the mist off (not from the attack till the crystal)
var _no_mist := false               ## no mist anywhere yet (the story's first day, till it rolls in that night)
var _breaks: Array = []             ## the attack's walls still to be smashed: [x, y, alongY, type]
const BREAK_GOAL := 10               ## walls down, at least, once the attack's over

static var kills := {}              ## creature kind -> how many have been killed


static func count_kill(c: Node) -> void:
	var kind := str(c.get_script().get_global_name()) if c.get_script() != null else "Creature"
	kills[kind] = int(kills.get(kind, 0)) + 1


## Whether the village keeps the mist off now (the story takes it away between the attack and the crystal).
static func village_warded() -> bool:
	return active == null or active._warded


## Whether there's no mist anywhere yet (a new game's first day: it comes with that night).
static func mist_held() -> bool:
	return active != null and active._no_mist


func setup(w: World, who: Miko, vs: Villagers, md: Dictionary, g: Node2D, hud: Node) -> void:
	world = w
	miko = who
	people = vs
	monster_data = md
	game = g
	active = self
	d = JSON.parse_string(FileAccess.get_file_as_string(FILE))
	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", HudStyle.piece("panel"))
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", int(3 * HudStyle.SCALE))
	_card.add_child(col)
	_title = HudStyle.label("", 15, "bold", HudStyle.color("accentLight"))
	_hint = RichTextLabel.new()
	_hint.bbcode_enabled = true
	_hint.fit_content = true
	_hint.scroll_active = false
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size.x = 340 * HudStyle.SCALE
	_hint.add_theme_font_override("normal_font", HudStyle.font("body"))
	_hint.add_theme_font_size_override("normal_font_size", int(12 * HudStyle.SCALE))
	_hint.add_theme_color_override("default_color", HudStyle.color("text"))
	for l in [_title, _hint]:
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(l)
	_card.visible = false
	hud.add_child(_card)
	var caster := world.get_node_or_null("Caster") as SpellCaster
	if caster != null:
		caster.cast_done.connect(func(_spell: String) -> void: _casts += 1)
	_marks = StoryMarks.new()
	_marks.name = "StoryMarks"
	_marks.setup(world)
	hud.add_child(_marks)


func to_json() -> String:
	return JSON.stringify({"beat": beat, "warded": _warded, "doomed": _doomed_left, "breaks": _breaks, "noMist": _no_mist})


func from_json(json: String) -> void:
	var s: Variant = JSON.parse_string(json)
	if s is Dictionary:
		beat = int(s.get("beat", -1))
		_warded = bool(s.get("warded", true))
		_doomed_left = s.get("doomed", [])
		_breaks = s.get("breaks", [])
		_no_mist = bool(s.get("noMist", false))
		if _no_mist and world.mist != null:
			world.mist.refresh(true)
			world.mist.snap()
		if beat >= 0:
			_begin(beat, true)


## A new game: the story begins (Sera on the road, the clock held, the village's people as the story has them).
func begin_new_game() -> void:
	var st: Dictionary = d.get("start", {})
	var c: Array = st.get("cell", [0, -112])
	miko.place(world.floors.cell_centre(Vector2i(int(c[0]), int(c[1]))))
	world.clock.hours = float(st.get("hour", 14.0))
	world.clock.speed = 0.0 if bool(st.get("frozen", true)) else 1.0
	Villagers.closed = true
	# No mist yet: it comes that night.
	_no_mist = true
	if world.mist != null:
		world.mist.refresh(true)
		world.mist.snap()
	# Her own necklace, on (the mist can't touch her), and her staff in her hands.
	for item in ["ShrineNecklace", "ApprenticeStaff"]:
		var slot := miko.bag.free_slot()
		if slot >= 0:
			miko.bag.items[slot] = item
			miko.stats.equip(miko.bag, slot)
	# What she's carrying on the road: travel food (it keeps), and her water pouch, full.
	var pouch := miko.bag.free_slot()
	if pouch >= 0:
		miko.bag.items[pouch] = "WaterPouch"
	for r in st.get("carrying", {}):
		miko.bag.add(str(r), int(st.carrying[r]))
	for who in d.get("people", []):
		var p := people.add_person(str(who.name), int(who.look))
		p["storyRole"] = str(who.role)
	Chronicle.active.record("intro_started")
	_begin(0, false)


# ---- The card: the beat's objective, and its hint a part at a time, each lit up once she's done it ----

var _did := {}                  ## the hint's parts done this beat: key -> true
var _head_up := 0.0             ## px from her feet to the top of her head (for the card over it)
var _card_at := Vector2.INF     ## where the card over her head is easing to (screen px)
var _swings_from := 0
var _casts := 0                 ## skills she's cast (the caster's cast_done), and how many as the beat began
var _casts_from := 0
var _hunger_was := 0.0


func _needs() -> Needs:
	return miko.get_node_or_null("Needs") as Needs


# The starter guide's card: just over her head (a few px clear of it), kept on the screen. The story's own: at the
# screen's right under the map, as a rumor's (under the rumor's card, when one's shown).
func _place_card() -> void:
	var view_r := get_viewport().get_visible_rect()
	if beat >= 0 and beat < _beats().size() and not bool(_beats()[beat].get("guide", false)):
		var top := 8.0 * HudStyle.SCALE
		if Minimap.active != null:
			top += Minimap.active.get_global_rect().end.y
		var tracker := game.get_node_or_null("Hud/RumorTracker") as Control
		if tracker != null and tracker.visible:
			for c in tracker.get_children():
				if c is Control and (c as Control).visible:
					top = maxf(top, (c as Control).get_global_rect().end.y + 8.0 * HudStyle.SCALE)
		_card.position = Vector2(view_r.size.x - _card.size.x - 12.0 * HudStyle.SCALE, top).round()
		return
	var xf := get_viewport().get_canvas_transform()
	# (a fixed height over her feet, measured the once: not her sprite's top, which bobs with every step and swing; and
	# eased there, so it holds steady as she walks and fights)
	if _head_up <= 0.0 and miko.art != null:
		_head_up = miko.position.y - World.sprite_rect(miko.art).position.y
	var head: Vector2 = xf * (miko.drawn_position() - Vector2(0, maxf(_head_up, 1.8 * world.px)))
	var view := get_viewport().get_visible_rect()
	var at := Vector2(head.x - _card.size.x / 2.0, head.y - _card.size.y - 6.0 * HudStyle.SCALE)
	at = Vector2(clampf(at.x, 8.0, view.size.x - _card.size.x - 8.0), clampf(at.y, 8.0, view.size.y - _card.size.y - 8.0))
	if _card_at == Vector2.INF or _card_at.distance_to(at) > 120.0:
		_card_at = at
	else:
		_card_at = _card_at.lerp(at, 0.12)
	_card.position = _card_at.round()


# The hint as shown: its parts (intro.json's "parts": [text, what does it]) joined by dots, those done in green with a
# tick; or just its text.
func _show_hint() -> void:
	if beat < 0 or beat >= _beats().size():
		return
	var b: Dictionary = _beats()[beat]
	var parts: Array = b.get("parts", [])
	if parts.is_empty():
		_hint.text = str(b.get("hint", ""))
		return
	var bits := []
	for p in parts:
		var key := str(p[1]) if p.size() > 1 else ""
		var text := str(p[0]).replace("{progress}", _progress(key))
		if key != "" and _did.has(key):
			bits.append("[color=#%s]✓ %s[/color]" % [HudStyle.color("green").to_html(false), text])
		else:
			bits.append(text)
	var lead := str(b.get("hint", ""))
	var t := (lead + "  " if lead != "" else "") + "  ·  ".join(bits)
	if t != _hint.text:
		_hint.text = t


# How far along a counted part is ("3/10"): what's in her bag (have:Thing:n), or put in storage since the beat began
# (stored:Thing:n); "" for the rest.
func _progress(key: String) -> String:
	var bits := key.split(":")
	if bits.size() < 3:
		return ""
	var want := int(bits[2])
	var got := 0
	match bits[0]:
		"have": got = world.village.have(miko.bag, miko, bits[1])
		"stored": got = maxi(world.village.stored(bits[1]) - int(_from.stash.get(bits[1], 0)), 0)
	if _did.has(key):
		got = want
	return "%d/%d" % [mini(got, want), want]


# Ticks off what she's done of the hint's parts (walk, run, jump, strike, eat, sleep; have:Thing:n in her bag,
# built:Prop since the beat began, stored:Thing:n more in storage).
func _tick_parts() -> void:
	var parts: Array = _beats()[beat].get("parts", [])
	if parts.is_empty():
		return
	var nd := _needs()
	var changed := false
	for p in parts:
		var key := str(p[1]) if p.size() > 1 else ""
		if key == "" or _did.has(key):
			continue
		var bits := key.split(":")
		var done := false
		match bits[0]:
			"walk": done = _walked >= 1.5
			"run": done = miko.running and miko.velocity.length() > 1.0
			"jump": done = miko.airborne()
			"strike": done = Melee.swings > _swings_from
			"cast": done = _casts > _casts_from
			"eat": done = nd != null and nd.hunger > _hunger_was + 1.0
			"sleep": done = nd != null and nd.sleeping()
			"have": done = world.village.have(miko.bag, miko, bits[1]) >= int(bits[2])
			"built": done = world.props_named(bits[1]).size() > int(_from.props.get(bits[1], 0))
			"stored": done = world.village.stored(bits[1]) - int(_from.stash.get(bits[1], 0)) >= int(bits[2]) or world.village.stored(bits[1]) >= int(bits[2])
		if done:
			_did[key] = true
			changed = true
	if nd != null:
		_hunger_was = minf(_hunger_was, nd.hunger)
	# (the counts kept up to date as she gathers)
	_show_hint()
	if changed:
		_card.reset_size()


func _beats() -> Array:
	return d.get("beats", [])


func _begin(i: int, loading: bool) -> void:
	beat = i
	if beat >= _beats().size():
		_finish()
		return
	var b: Dictionary = _beats()[beat]
	var props := {}
	for nm in ["Bonfire", "LeafBed", "CleansingCrystal"]:
		props[nm] = world.props_named(nm).size()
	_from = {"kills": kills.duplicate(), "bag": miko.bag.counts.duplicate(), "stash": world.village.stash.duplicate(), "cooked": _dishes_in_bag(), "dishes": _dishes_stored(),
		"props": props, "hours": world.clock.hours}
	_walked = 0.0
	_last_at = miko.position
	if _marks != null:
		_marks.unmark_people()   # (who a beat said to go to: marked for that beat only)
	if not loading:
		for a in b.get("start", []):
			_act(a)
	else:
		# (a game loaded part way through a beat: the monsters it sent aren't kept in the save, so they come again, the
		# kills it wants counted afresh)
		for a in b.get("start", []):
			if str(a.get("do", "")) in ["spawn", "mark"]:
				_act(a)
	_title.text = str(b.objective)
	_did = {}
	_swings_from = Melee.swings
	_casts_from = _casts
	_hunger_was = _needs().hunger if _needs() != null else 0.0
	_show_hint()
	_card.visible = true


func _finish() -> void:
	beat = -1
	_card.visible = false
	Villagers.closed = false
	world.clock.speed = 1.0


func _process(delta: float) -> void:
	if beat < 0:
		return
	# (out of the way while a window's open over her: her bag and character, a conversation)
	var talk: Control = game.get_node_or_null("Hud/Talk")
	_card.visible = not CharacterPanel.up() and not (talk != null and talk.visible)
	_card.reset_size()
	_place_card()
	_tick_parts()
	if _last_at != Vector2.INF and miko.position.distance_to(_last_at) < 2.0 * world.px:
		_walked += miko.position.distance_to(_last_at) / world.px
	_last_at = miko.position
	_attack_goes_on(delta)
	var b: Dictionary = _beats()[beat]
	if _done(b.get("done", {})):
		for a in b.get("after", []):
			_act(a)
		Chronicle.active.record("intro:" + str(b.id))
		match str(b.id):
			"mend": Chronicle.active.record("intro_houses_mended")
			"feed": Chronicle.active.record("intro_fed")
		_begin(beat + 1, false)


# ---- What ends a beat ----

func _done(dn: Dictionary) -> bool:
	match str(dn.get("kind", "")):
		"walked":
			return _walked >= float(dn.units)
		"killed":
			var k := str(dn.what)
			return int(kills.get(k, 0)) - int(_from.kills.get(k, 0)) >= int(dn.count)
		"opened":
			var cp: CharacterPanel = CharacterPanel._active
			if cp == null: return false
			return cp.talents.visible if str(dn.what) == "talents" else cp.window.visible
		"have":
			for r in dn.what:
				if world.village.have(miko.bag, miko, str(r)) < int(dn.what[r]):
					return false
			return true
		"built":
			# (one more of each than there was as the beat began: the village's own bonfire doesn't count)
			for nm in dn.what:
				var spots: Array = world.props_named(str(nm))
				if spots.size() <= int(_from.props.get(nm, 0)):
					return false
				if bool(dn.get("in_village", false)) and spots.filter(func(at): return world.village.contains(at, 2.0)).is_empty():
					return false
			return true
		"cooked":
			return _dishes_in_bag() - int(_from.cooked) >= int(dn.count)
		"slept":
			var nd: Needs = miko.get_node_or_null("Needs")
			return nd != null and nd.sleep == Needs.Sleep.ASLEEP
		"scene":
			return Chronicle.active.happened("scene:" + str(dn.id))
		"reach_village":
			return world.village.contains(miko.position, 4.0)
		"raid_over":
			return not Raids.on() and _doomed_left.is_empty()
		"stored":
			for r in dn.what:
				if world.village.stored(str(r)) - int(_from.stash.get(r, 0)) < int(dn.what[r]) and world.village.stored(str(r)) < int(dn.what[r]):
					return false
			return true
		"houses":
			# (the smashed walls built again, and every house mended)
			if Construction.active != null and Construction.active.pieces.any(func(p): return bool(p.get("wall", false))):
				return false
			var up := Upkeep.active
			if up == null: return true
			return up.houses().all(func(h): return float(h.condition) >= float(dn.min))
		"stored_dishes":
			return _dishes_stored() - int(_from.dishes) >= int(dn.count)
		"morning":
			var h := world.clock.hour()
			return h >= 6.0 and h < 10.0 and world.clock.hours - float(_from.get("hours", world.clock.hours)) >= 6.0
	return false


func _dishes_in_bag() -> int:
	var n := 0
	for r in Fires.RECIPES:
		n += miko.bag.count(str(r[1]))
	return n


func _dishes_stored() -> int:
	var n := 0
	for r in Kitchen.RECIPES:
		n += world.village.stored(str(r[1]))
	return n


# ---- What happens ----

func _act(a: Dictionary) -> void:
	match str(a.get("do", "")):
		"spawn":
			for i in int(a.get("count", 1)):
				_spawn(str(a.what), float(a.get("near", 6)))
		"give":
			world.village.give(miko.bag, miko, str(a.what), int(a.n), miko.position)
		"time":
			var h := float(a.hour)
			var day := floorf(world.clock.hours / 24.0)
			world.clock.hours = day * 24.0 + h + (24.0 if h < world.clock.hour() else 0.0)
		"clock":
			world.clock.speed = 1.0 if bool(a.run) else 0.0
		"wake":
			var nd: Needs = miko.get_node_or_null("Needs")
			if nd != null and nd.sleeping():
				nd.get_up()
				if nd.sleep == Needs.Sleep.ASLEEP:
					nd.sleep = Needs.Sleep.AWAKE
		"messenger":
			_messenger()
		"mist_in":
			_warded = false
			_no_mist = false
			if world.mist != null:
				world.mist.refresh(true)
				# (all of it at once: easing every cell of the map in over a few seconds cost a frame its 40-200 ms)
				world.mist.snap()
		"attack":
			_attack(int(a.get("count", 10)))
		"ward":
			_warded = true
			Chronicle.active.record("village_warded")
			# (the horde gone: the elders out of hiding, to see who's left)
			for v in Villager.all:
				if is_instance_valid(v) and v.person.has("unique") and not Traits.has(v.person, "unique"):
					v.person.erase("restUntil")
			if world.mist != null:
				world.mist.refresh(true)
		"record":
			Chronicle.active.record(str(a.event))
		"mark":
			# Someone to go to (a unique: "elder"...): a ring round them and an arrow, till the beat's over.
			if _marks != null:
				_marks.mark_unique(str(a.who))
		"say":
			FloatingText.spawn(world, str(a.text), miko.position + Vector2(0, -2.2 * world.px), Color(1.0, 0.9, 0.7), 18, 3.0)


# A monster near Sera, on open ground (not where she stands).
func _spawn(kind: String, near: float) -> void:
	var at := miko.position
	for tries in 30:
		var ang := randf() * TAU
		var p := miko.position + Vector2(cos(ang), sin(ang) * 0.5) * randf_range(near * 0.6, near) * world.px
		if Wilds.open(world, p, 0.5, 0.3):
			at = p
			break
	var c: Creature = null
	match kind:
		"slime": c = Slime.spawn(world, monster_data.slime, false, at, 1.0)
		"boar": c = Boar.spawn(world, monster_data.boar, at)
		"mutatedVillager": c = MutatedVillager.spawn(world, monster_data.mutatedVillager, at)
	# (marked: an arrow to it, its outline on, so she can find it)
	if c != null and _marks != null:
		_marks.mark(c)


func _villager(role: String) -> Villager:
	for v in Villager.all:
		if is_instance_valid(v) and str(v.person.get("storyRole", "")) == role:
			return v
	return null


# The messenger: a villager running down the road to her; when he reaches her, his news.
func _messenger() -> void:
	var v := _villager("messenger")
	if v == null:
		Chronicle.active.record("scene:messenger")
		return
	# (out of his bed if he was in it, and up the road a way; then running down to her)
	if v.in_bed:
		v._wake_up(Villager.now())
	v.visible = true
	v.held = true
	v._held_moving = true
	var from := miko.position + Vector2(-5.0, 7.0) * world.px
	var to := miko.position + Vector2(-0.9, 0.5) * world.px
	v.position = from
	v.reset_physics_interpolation()
	var dir := to - from
	v.facing_right = dir.x > 0.0
	v.facing_up = dir.y < 0.0
	v.show_mood("alarm", 6.0)
	var tw := create_tween()
	tw.tween_property(v, "position", to, 3.0)
	tw.tween_callback(func(): v._held_moving = false)
	_messenger_v = v


var _messenger_v: Villager


# The attack: the mist rolls in, a horde from it at the village, houses burning, and those who won't make it falling
# one by one while it goes on; the fighters and the girl hold on; the elders are hidden in their house.
func _attack(count: int) -> void:
	_doomed_left = []
	# The village's torches burning as the horde comes (it's night; there's light to fight by).
	var fires: Fires = miko.get_node_or_null("Fires")
	if fires != null:
		for f in fires.fires:
			if bool(f.s.get("torch", false)) and world.village.contains(f.pos, 3.0):
				fires.light(f)
	for v in Villager.all:
		if not is_instance_valid(v):
			continue
		match str(v.person.get("storyRole", "")):
			"doomed": _doomed_left.append(str(v.person.name))
		if v.person.has("unique") and not Traits.has(v.person, "unique"):
			v.person["restUntil"] = world.clock.hours + 6.0   # (the elders, hiding in their house till it's over)
	# (from every side: a few bands, each its own way in)
	var raids: Raids = Raids.active
	if raids != null:
		var bands := 4
		var turn := randf() * TAU
		for i in bands:
			raids.start(maxi(2, int(count / float(bands))), turn + i * TAU / bands + randf_range(-0.3, 0.3), i > 0)
	# Those who'll come through it hold on (hurt, but alive); the elders hide in their house.
	for v in Villager.all:
		if is_instance_valid(v) and v.hit != null and (str(v.person.get("storyRole", "")) in ["fighter", "survivor", "messenger"] or v.person.has("unique")):
			v.hit.unkillable = true
	for h in Upkeep.active.houses() if Upkeep.active != null else []:
		Upkeep.active.condition[h.key] = randf_range(20.0, 45.0)
	# The monsters smash at the houses' walls themselves (Raids.strike_house_wall); these are the ones that go in
	# anyway if the horde's driven off before it's done enough (two to four a house, not their doors): each becomes
	# a plan for the villagers to build again.
	_breaks = []
	for h in Upkeep.active.houses() if Upkeep.active != null else []:
		if randf() > 0.75:
			continue
		var edges := []
		for c in h.cells:
			for e in [WallMap.Edge.new(c, true), WallMap.Edge.new(c + Vector2i(1, 0), true), WallMap.Edge.new(c, false), WallMap.Edge.new(c + Vector2i(0, 1), false)]:
				var t := world.walls.get_wall(e)
				if t != "" and float(world.walls.types[t].opening) == 0.0 and str(world.walls.types[t].toggle) == "" and not bool(world.walls.types[t].get("fence", false)):
					edges.append([e.vertex.x, e.vertex.y, e.along_y, t])
		edges.shuffle()
		_breaks.append_array(edges.slice(0, randi_range(2, 4)))
	_breaks.shuffle()
	var houses: Array = Upkeep.active.houses() if Upkeep.active != null else []
	houses.shuffle()
	for h in houses.slice(0, 3):
		var glow := PointLight2D.new()
		glow.texture = Fires._glow()
		glow.color = Color(1.0, 0.45, 0.2)
		glow.energy = 1.4
		glow.texture_scale = 5.0 * 2.0 * world.px / float(Fires._glow().get_width())
		glow.position = h.middle
		world.add_child(glow)
		_fires.append(glow)
	_next_doom = Time.get_ticks_msec() / 1000.0 + 8.0
	Chronicle.active.record("village_attacked")


func _attack_goes_on(_delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	# The messenger, reaching her: his news (the talk window, his words).
	if _messenger_v != null and is_instance_valid(_messenger_v) and not _messenger_v._held_moving:
		var talk: Talk = game.get_node_or_null("Hud/Talk")
		var scene := Scenes.all().filter(func(s): return str(s.id) == "messenger")
		if talk != null and not scene.is_empty():
			talk.open(_messenger_v)
			talk._play(scene[0], 0)
		_messenger_v.held = false
		_messenger_v = null
	# The fires: smoke going up while it lasts.
	if not _fires.is_empty():
		if randf() < 0.08:
			var f: Node2D = _fires.pick_random()
			Puffs.burst(world, f.position + Vector2(randf_range(-1, 1), randf_range(-0.5, 0.5)) * world.px, 1.4, 6)
		if _warded and not Raids.on():
			for f in _fires:
				if is_instance_valid(f):
					f.queue_free()
			_fires.clear()
	# The horde gone: walls enough down for the village to show it (the monsters' own, then more from the list).
	if not _breaks.is_empty() and not Raids.on():
		while not _breaks.is_empty() and _walls_down() < BREAK_GOAL:
			Raids.smash(world, _breaks.pop_back())
		_breaks.clear()
	# Coming in sight of it: the camera goes over the village a moment.
	if not _panned and Chronicle.active.happened("village_attacked") and world.village.contains(miko.position, 26.0):
		_panned = true
		_pan()
	if _doomed_left.is_empty() or now < _next_doom:
		_hold_survivors()
		return
	# One more falls (while monsters are about and Sera's there to see it).
	if Raids.on() and world.village.contains(miko.position, 20.0):
		_next_doom = now + randf_range(6.0, 11.0)
		var nm: String = _doomed_left.pop_front()
		for v in Villager.all:
			if is_instance_valid(v) and str(v.person.name) == nm and v.hit != null and v.hit.alive():
				v.hit.hurt(v.hit.hp + 999.0)
	elif not Raids.on():
		# (the horde gone before they fell: they're spared after all)
		_doomed_left.clear()
	_hold_survivors()


# Walls down and waiting to be built again.
func _walls_down() -> int:
	return Construction.active.pieces.filter(func(p): return bool(p.get("wall", false))).size() if Construction.active != null else 0


# The fighters, the girl and the messenger hold on through it (badly hurt, maybe, but alive); once it's over they're
# as anyone again.
func _hold_survivors() -> void:
	if not Raids.on():
		for v in Villager.all:
			if is_instance_valid(v) and v.hit != null and v.hit.unkillable:
				v.hit.unkillable = false
		return
	for v in Villager.all:
		if is_instance_valid(v) and str(v.person.get("storyRole", "")) in ["fighter", "survivor", "messenger"] and v.hit != null:
			v.hit.hp = maxf(v.hit.hp, v.hit.max_hp * 0.25)


# Over the village a moment as she arrives: the houses burning, the horde.
func _pan() -> void:
	var cam: Camera2D = game.get("camera")
	if cam == null:
		return
	game.set_meta("warming", true)
	miko.locked = true
	var back := cam.position
	var tw := create_tween()
	tw.tween_property(cam, "position", world.village.centre(), 1.2).set_trans(Tween.TRANS_SINE)
	tw.tween_interval(2.4)
	tw.tween_property(cam, "position", back, 0.9).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func():
		game.remove_meta("warming")
		miko.locked = false)
	FloatingText.spawn(world, "The village is burning.", world.village.centre() + Vector2(0, -2.5 * world.px), Color(1.0, 0.6, 0.4), 22, 3.5)
