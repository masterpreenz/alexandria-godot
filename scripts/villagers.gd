class_name Villagers
extends Node2D
## Keeps the village peopled (from Unity's Villagers): every bed in a house inside the village has someone living in
## it. Villagers are people with names who keep their beds: the first time a bed is lived in, the next person without
## a home takes it, or a newcomer arrives (for now no one new comes once there are two). Who lives where is saved
## (village.people). Take a bed or its house away and its person waits, homeless, by the banner for the next free one.
## It also keeps an eye on the village for its messages: storage full, beds outside or not in a house, monsters inside.
## Hold Alt to see who's who: their name, level and HP over each (VillagerTags).
##
## A person (Unity's Villagers.Person, as saved): name, look (0 a man, 1 and 2 women), hasBed, bedX, bedY (units), level,
## xp, maxHp, hp, atk, skills {level, xp}, hunger, energy, job, toolsLeft, bag, bagSlots, bagLeft.

const NAMES := [["Taro", "Kenji", "Haru", "Sota", "Ren", "Daichi", "Kaito", "Yuto"], ["Hana", "Yui", "Aoi", "Mei", "Sakura", "Rin", "Emi", "Nao"],
	["Miyu", "Kaede", "Chiyo", "Suzu", "Akane", "Kiku", "Tsubaki", "Momo"], ["Genzo", "Tetsuo", "Isamu"], ["Haruko", "Fumiko", "Setsuko"]]
const SKILL_NAMES := ["lumbering", "mining", "strength", "farming", "cooking", "building", "stamina", "fishing"]

static var heart := 1.0          ## how much faster the villagers work now (Village Heart, with Miko in the village)

var world: World
var d: Dictionary                  ## villagers.json, with the eat sound and the beds' data
var s: Dictionary                  ## Villagers' settings: most, newcomersUpTo, checkEvery
var people: Array = []             ## everyone, housed or not, in the order they came
var living := {}                   ## bed key -> [person, Villager]
var waiting := {}                  ## person name -> Villager (no bed yet, about the banner)
var _next_check := 0.0
var tags: Control


func setup(w: World, data: Dictionary, beds: Dictionary, eat_sound: Variant) -> void:
	world = w
	d = data
	d["beds"] = beds
	d["eatSound"] = eat_sound
	s = data.get("villagers", {})


## The job board: the jobs in the order the villagers take them (the jobs window's Job Board sets it). Saved.
var board: Array = BOARD.duplicate()
static var closed := false            ## nobody new comes while it's set (the story has its own people at its start)
const BOARD := [Villager.Job.BUILDING, Villager.Job.HAULING, Villager.Job.FARMING, Villager.Job.COOKING, Villager.Job.FISHING,
	Villager.Job.CRAFTING, Villager.Job.LUMBERING, Villager.Job.MINING]


## The saved people (Unity's village.people).
func from_json(json: String) -> void:
	var data: Variant = JSON.parse_string(json)
	people = data.get("people", []) if data is Dictionary else []
	# (the board as saved, as long as it's every job once: else the usual order)
	var saved: Array = (data.get("board", []) as Array).map(func(j): return int(j)) if data is Dictionary and data.get("board") is Array else []
	board = saved if saved.size() == BOARD.size() and BOARD.all(func(j): return saved.has(j)) else BOARD.duplicate()
	for p in people:
		_fix(p)
	Uniques.promote(self)
	# (those from before there were traits: rolled now)
	for p in people:
		if not p.has("traits"):
			Traits.roll(p)
	_next_check = 0.0


func to_json() -> String:
	return JSON.stringify({"people": people, "board": board})


# Fills in what an older save hasn't got.
func _fix(p: Dictionary) -> void:
	if not p.has("skills") or (p.skills.level as Array).max() <= 0:
		var lv := []
		for i in 7:
			match i:
				0: lv.append(int(p.get("lumbering", 1)))
				1: lv.append(int(p.get("mining", 1)))
				3: lv.append(int(p.get("farming", 1)))
				4: lv.append(randi_range(1, 5) if int(p.get("look", 0)) >= 1 else 0)  # only women cook, for now
				_: lv.append(randi_range(1, 5))
		p["skills"] = {"level": lv, "xp": [0, 0, 0, 0, 0, 0, 0]}
	for k in ["talkedDay", "giftDay"]:
		if p.has(k):
			p[k] = int(p[k])
	if p.has("first"):
		p["first"] = int(p.first)
	# (a save's numbers come back as fractions: the jobs ticked are whole)
	if p.has("jobs"):
		p["jobs"] = (p.jobs as Array).map(func(j): return int(j))
	# (skills added since: fishing)
	while (p.skills.level as Array).size() < SKILL_NAMES.size():
		(p.skills.level as Array).append(randi_range(1, 3))
	while (p.skills.xp as Array).size() < SKILL_NAMES.size():
		(p.skills.xp as Array).append(0)
	# (what their look can't do: the elder only cooks, crafts and fishes)
	var looks: Array = d.get("looks", [])
	var lk := clampi(int(p.get("look", 0)), 0, maxi(0, looks.size() - 1))
	if not looks.is_empty() and looks[lk] != null and looks[lk].settings.has("canDo"):
		p["canDo"] = looks[lk].settings.canDo
	if not p.has("thirst"):
		p["thirst"] = 100.0
	for k in ["hunger", "energy", "hp", "maxHp", "atk", "level", "xp", "toolsLeft", "bagSlots", "bagLeft", "job"]:
		if not p.has(k):
			p[k] = {"hunger": 80.0, "energy": 100.0, "hp": 40.0, "maxHp": 40.0, "atk": 6.0, "level": 1}.get(k, 0)


## A person's level at a life skill.
static func skill(p: Dictionary, sk: int) -> int:
	return int(p.skills.level[sk]) if p.has("skills") else 1


## One more go at a skill: every so often it improves, and all of it adds to their level (news in the village's log).
func practise(p: Dictionary, sk: int) -> void:
	var news := ""
	var lv: Array = p.skills.level
	var xp: Array = p.skills.xp
	if int(lv[sk]) > 0 and int(lv[sk]) < LifeSkills.MOST:
		# (traits: a quick learner's go counts double now and then, one set in their ways misses some)
		var learn := Traits.add(p, "learn")
		xp[sk] = int(xp[sk]) + (0 if learn < 0.0 and randf() < -learn else (2 if randf() < learn else 1))
		if int(xp[sk]) >= 8 * maxi(1, int(lv[sk])):
			xp[sk] = 0
			lv[sk] = int(lv[sk]) + 1
			news = "%s's %s improved to %d" % [p.name, SKILL_NAMES[sk], lv[sk]]
	p.xp = int(p.xp) + 1
	if int(p.xp) >= 30 * int(p.level):
		p.xp = 0
		p.level = int(p.level) + 1
		p.maxHp = float(p.maxHp) + 8.0
		p.hp = minf(float(p.maxHp), float(p.hp) + 8.0)
		p.atk = float(p.atk) + 1.0
		news = "%s reached level %d" % [p.name, p.level]
	if news != "":
		VillageLog.event("news:" + p.name, news)


func _beds() -> Array:
	var __t := Time.get_ticks_usec()
	var __r := _beds_untimed()
	Perf.add(&"villagers: beds", __t)
	return __r


func _beds_untimed() -> Array:
	return Needs.all_beds(world, d.beds)


# A bed someone can live in: in the village, in a house.
func _home(bed: Dictionary) -> bool:
	return world.village.contains(bed.pos) and world.roofs != null and world.roofs.room_on(bed.pos) != null


func _bed_at(p: Dictionary) -> Vector2:
	return Vector2(float(p.bedX), -float(p.bedY)) * world.px


func _look_for(p: Dictionary) -> Dictionary:
	var looks: Array = d.get("looks", [])
	var i := clampi(int(p.look), 0, looks.size() - 1)
	return looks[i] if looks[i] != null else looks[0]


func _process(delta: float) -> void:
	var __t := Time.get_ticks_usec()
	_process_timed(delta)
	Perf.add(&"villagers.process", __t)


func _process_timed(_delta: float) -> void:
	if d.get("looks", []).is_empty() or world.player == null:
		return
	_quarry()
	var t := Villager.now()
	if t < _next_check:
		return
	_next_check = t + float(s.get("checkEvery", 2.0))
	# Village Heart: the villagers work faster while Miko's in the village.
	var mk := world.player
	heart = CharacterStats.percent(mk.stats.stat("villageWork")) if mk != null and mk.stats != null and world.village.contains(mk.position) else 1.0
	var beds := _beds()
	var by_key := {}
	for b in beds:
		by_key[Needs.bed_key(b.pos)] = b
	# Leave: beds taken away, or no longer in a house in the village. The person keeps their claim to it.
	for k in living.keys():
		var v: Variant = living[k][1]   # (untyped: it may have died and been freed)
		if not by_key.has(k) or not is_instance_valid(v) or not _home(by_key[k]):
			if is_instance_valid(v):
				(v as Villager).move_out()
			living.erase(k)
	# The dead are gone for good: their bed frees up for a newcomer.
	people = people.filter(func(p): return float(p.hp) > 0.0 or _living(p))
	if not world.village.founded():
		_clear_waiting()
		return
	# There's always someone hoping to move in: a newcomer turns up when no one's waiting.
	if not closed and _homeless() == null and people.size() < int(s.get("most", 16)) and not _full():
		_arrive()
	_notice(beds)
	for b in beds:
		if living.size() >= int(s.get("most", 16)):
			break
		var k := Needs.bed_key(b.pos)
		if living.has(k) or not _home(b):
			continue
		var who: Variant = _claimant(b)
		if who == null: who = _homeless()
		if who == null and not _full() and not closed: who = _newcomer()
		if who != null:
			_settle(who, b)
	_wanderers()


func _full() -> bool:
	var most := int(s.get("newcomersUpTo", 2))
	return most > 0 and people.size() >= most


func _living(p: Dictionary) -> bool:
	for v in living.values():
		if v[0] == p:
			return true
	return false


# Whoever already calls this bed home.
func _claimant(bed: Dictionary) -> Variant:
	for p in people:
		if bool(p.hasBed) and _bed_at(p).distance_to(bed.pos) < 0.05 * world.px and not _living(p):
			return p
	return null


# Someone with nowhere to live: no bed, or a bed that's no longer a home.
func _homeless() -> Variant:
	for p in people:
		if _living(p):
			continue
		if not bool(p.hasBed):
			return p
		var still := false
		for b in _beds():
			if _bed_at(p).distance_to(b.pos) < 0.05 * world.px and _home(b):
				still = true
				break
		if not still:
			return p
	return null


# A newcomer: by turns, a woman first, so the village gets a mix; a name not yet taken.
func _newcomer() -> Dictionary:
	# (the looks in turn; not one that's someone's own, as Miyu's is)
	var turn := [1, 0, 2].filter(func(l): return l < d.looks.size() and str(d.looks[l].settings.get("uniqueTo", "")) == "")
	var look: int = turn[(turn.find(int(people[-1].look)) + 1) % turn.size()] if not people.is_empty() else 1
	# (a look nobody here has yet comes first)
	for l in turn:
		if l < d.looks.size() and not people.any(func(q): return int(q.look) == l):
			look = l
			break
	look = mini(look, d.looks.size() - 1)
	var pool: Array = NAMES[mini(look, NAMES.size() - 1)]
	var nm := ""
	for n in pool:
		if not Uniques.name_taken(n) and not people.any(func(q): return q.name == n):
			nm = n
			break
	if nm == "":
		nm = "%s %d" % [pool[people.size() % pool.size()], people.size() + 1]
	var level := randi_range(1, 3)
	var p := {"name": nm, "look": look, "hasBed": false, "bedX": 0.0, "bedY": 0.0, "level": level, "xp": 0,
		"maxHp": 30.0 + 10.0 * level, "hp": 30.0 + 10.0 * level, "atk": 4.0 + 2.0 * level,
		"hunger": randf_range(60.0, 100.0), "energy": 100.0, "job": 0, "toolsLeft": 0, "bag": "", "bagSlots": 0, "bagLeft": 0}
	_fix(p)
	Traits.roll(p)
	people.append(p)
	return p


## Someone in particular comes to the village (the story's people): named [param nm], of look [param look].
func add_person(nm: String, look: int) -> Dictionary:
	var level := randi_range(1, 3)
	var p := {"name": nm, "look": look, "hasBed": false, "bedX": 0.0, "bedY": 0.0, "level": level, "xp": 0,
		"maxHp": 30.0 + 10.0 * level, "hp": 30.0 + 10.0 * level, "atk": 4.0 + 2.0 * level,
		"hunger": randf_range(70.0, 100.0), "energy": 100.0, "job": 0, "toolsLeft": 0, "bag": "", "bagSlots": 0, "bagLeft": 0}
	_fix(p)
	Traits.roll(p)
	people.append(p)
	_next_check = 0.0
	return p


func _arrive() -> void:
	var p := _newcomer()
	VillageLog.event("arrived:" + p.name, "%s has come to the village and needs a bed in a house" % p.name)


# Puts who in bed: their claim on it, and their body there.
func _settle(who: Dictionary, bed: Dictionary) -> void:
	VillageLog.clear("homeless:" + who.name)
	who.hasBed = true
	who.bedX = bed.pos.x / world.px
	who.bedY = -bed.pos.y / world.px
	var v := Villager.new()
	v.setup(world, self, _look_for(who), who, bed)
	living[Needs.bed_key(bed.pos)] = [who, v]


# Everyone without a bed is about the village (by the banner), until they get one.
func _wanderers() -> void:
	for p in people:
		if float(p.hp) <= 0.0 or _living(p):
			continue
		if waiting.has(p.name) and is_instance_valid(waiting[p.name]):
			continue
		var v := Villager.new()
		var r := Vector2.from_angle(randf() * TAU) * sqrt(randf()) * 1.5 * world.px
		v.position = world.village.centre() + r + Vector2(0, 0.8 * world.px)
		v.setup(world, self, _look_for(p), p, {})
		waiting[p.name] = v
	for nm in waiting.keys():
		var v: Variant = waiting[nm]   # (untyped: it may have died and been freed)
		var p: Variant = null
		for q in people:
			if q.name == nm:
				p = q
		if p == null or not is_instance_valid(v) or _living(p) or float(p.hp) <= 0.0:
			if is_instance_valid(v):
				v.move_out()
			waiting.erase(nm)


func _clear_waiting() -> void:
	for v in waiting.values():
		if is_instance_valid(v):
			v.move_out()
	waiting.clear()


# What's wrong with the village's homes, for its message list.
func _notice(beds: Array) -> void:
	var __t := Time.get_ticks_usec()
	_notice_untimed(beds)
	Perf.add(&"villagers: notice", __t)


func _notice_untimed(beds: Array) -> void:
	var v := world.village
	for r in Bag.RESOURCES:
		var cap := v.stash_cap(r)
		if cap > 0 and v.stored(r) >= cap:
			VillageLog.problem("storage-full", "Storage is full of %s: build more chests (what doesn't fit is left on the ground)" % UiKit.resource_name(r).to_lower(), VillageLog.Kind.DANGER)
	var homes := 0
	for b in beds:
		if not v.contains(b.pos):
			if v.contains(b.pos, 6.0):
				VillageLog.problem("bed-outside", "A bed is outside the village: no one will live in it")
			continue
		if _home(b): homes += 1
		else: VillageLog.problem("bed-not-house", "A bed isn't in a house (4×4 or bigger, walled and floored): no one can live in it")
	if homes == 0:
		VillageLog.problem("no-homes", "No villagers yet: build a house with a bed in the village")
	var raiders := 0
	for c in Creature.all:
		if c.hit.alive() and v.contains(c.position) and c.get("angry_until") != null and Villager.now() < float(c.angry_until):
			raiders += 1
	if raiders > 0:
		VillageLog.problem("attack", "The village is under attack: a monster got in" if raiders == 1 else "The village is under attack: %d monsters got in" % raiders, VillageLog.Kind.DANGER)
	for p in people:
		if not _living(p):
			VillageLog.problem("homeless:" + p.name, "%s has no bed: build another, in a house" % p.name)


# ---- The quarry (from Unity's Quarry): its rocks don't grow back one by one but all at once, each morning ----

var _quarry_day := -2


func _quarry() -> void:
	var __t := Time.get_ticks_usec()
	_quarry_untimed()
	Perf.add(&"villagers: quarry", __t)


func _quarry_untimed() -> void:
	var q: Dictionary = d.get("quarry", {})
	if q.is_empty() or world.clock == null:
		return
	var hour := float(q.regrowHour)
	# The latest morning that has passed; a new one brings the rock back.
	var day: int = world.clock.day() if world.clock.hour() >= hour else world.clock.day() - 1
	if _quarry_day == -2:
		_quarry_day = day
		return
	if day <= _quarry_day:
		return
	_quarry_day = day
	var a: Array = q.area
	var area := Rect2(float(a[0]), float(a[1]), float(a[2]), float(a[3]))
	for g in Gatherable.all:
		if g.axe or not area.has_point(world.floors.fractional_cell(g.foot)):
			continue
		if g.depleted() or g.stage > 0 or g.left < g.stone:
			g.regrow()


# ---- Alt: who's who ----

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and (event.keycode == KEY_ALT):
		if tags != null:
			tags.visible = event.pressed


## The name tags shown while Alt is held: over each villager, their name and level, and a bar of their HP.
class Tags extends Control:
	var people: Villagers

	func _process(delta: float) -> void:
		var __t := Time.get_ticks_usec()
		_process_timed(delta)
		Perf.add(&"villagers.Tags.process", __t)


	func _process_timed(_delta: float) -> void:
		if visible:
			queue_redraw()

	func _draw() -> void:
		var f: Font = UiKit.body_font if UiKit.body_font else get_theme_default_font()
		var xf := get_viewport().get_canvas_transform()
		for v in Villager.all:
			if not v.visible:
				continue
			var at := xf * (v.position + Vector2(0, -v._top() - 0.15 * people.world.px))
			var text := "%s  Lv %d" % [v.person.name, int(v.person.level)]
			var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
			draw_string_outline(f, at + Vector2(-w / 2.0, -10), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 5, Color(0, 0, 0, 0.85))
			draw_string(f, at + Vector2(-w / 2.0, -10), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
			var frac := clampf(v.hit.hp / v.hit.max_hp, 0.0, 1.0)
			var c := Color(0.55, 0.85, 0.4) if frac > 0.6 else (Color(0.95, 0.72, 0.27) if frac > 0.3 else Color(0.9, 0.33, 0.24))
			draw_rect(Rect2(at + Vector2(-30, -4), Vector2(60, 5)), Color(0, 0, 0, 0.6))
			draw_rect(Rect2(at + Vector2(-30, -4), Vector2(60 * frac, 5)), c)
