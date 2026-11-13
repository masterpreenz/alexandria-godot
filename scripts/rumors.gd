class_name Rumors
extends Node
## Rumors: what the villagers tell Miko, in place of quests. A villager with one to tell shows it over their head;
## asked ("Heard anything?"), they tell it, and it goes in the journal (RumorsWindow, K). A rumor says nothing of what
## comes of it. It has steps, each known only once the one before is done: where it might be is marked on the maps,
## roughly (a ring it's somewhere inside), while it's tracked. Miko can keep her own notes on each. What's happened
## with every rumor, and when, is written in the Chronicle: rumors appear by it (after another came to something, or
## was left too long), so one leads to others.
##
## All of it is rumors.json. A rumor there:
##   id, title
##   teller    who tells it: {"any": true}, {"name": "Yui"} or {"look": 1}
##   appears   when it can be told: {"afterDay": n, "after": [{"event": "done:other", "days": n}], "unless": ["heard:x"]}
##   told      what the teller says ({dir}: which way its first place lies, {teller}, {miko})
##   expires   {"days": n}: left that long unfinished, it's over ("ignored:id" is recorded)
##   steps     [{id, note (the journal's line), place, done, safe (once here, it can't run out)}]
##     place   {"kind": "forest" (the nearest wood; "misted": in the mist; or the wood in map "section": "F6", at its
##              "corner": "upper-left" | "upper-right" | "lower-left" | "lower-right" as seen, its edge on that side) | "same" (the step before's) |
##              "of" ("rumor", "step": another rumor's) | "village" | "section" ("section": "A8", its middle) | "cell" ("x", "y"), "vague": the ring's radius, units}
##     done    {"kind": "reach" ("within" units) | "cleared" ("radius" units round it, "share" of it out of the mist) |
##              "days" ("days" since the step began) | "event" ("event": in the chronicle)}
##   reward    never shown: {"gifts": [[resource, n]], "effects": [...], "log": the village log's line}
##   failed    the same, for when it's left too long: {"effects": [...], "log"}
##     effects "rabbit_hole" | "unique_arrives:<id>" (a unique character comes to the village) |
##             "unique_lost:<id>" (they're lost for good) | "record:<event>" (written in the chronicle)
##   appears   may also ask "unless": ["unique:miyu", "lost:miyu"]: whatever's in the chronicle
##   leads     {"done": [ids], "ignored": [ids]}: for whoever's reading the file (what appears is by "appears")

signal changed

const FILE := "res://data/rumors.json"
const CHECK_EVERY := 1.0

static var active: Rumors

var world: World
var miko: Miko
var defs: Array = []              ## the rumors, as written
var by_id := {}
var heard := {}                   ## id -> {state: "open"|"done"|"ignored", step, from (hours the step began), heard (hours), by (who told it), places {step id: [x, y]}, notes, tracked, ended}
var offers := {}                  ## id -> the name of the villager who has it to tell
var _clock := 0.0


func setup(w: World, who: Miko) -> void:
	world = w
	miko = who
	active = self
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(FILE))
	if d is Dictionary:
		defs = d.get("rumors", [])
	for r in defs:
		by_id[str(r.id)] = r


func to_json() -> String:
	return JSON.stringify({"heard": heard, "offers": offers})


func from_json(json: String) -> void:
	var d: Variant = JSON.parse_string(json)
	if d is Dictionary:
		heard = d.get("heard", {})
		offers = d.get("offers", {})
		for id in heard.keys():
			if not by_id.has(id):
				heard.erase(id)   # (a rumor since taken out of the file)
			else:
				heard[id].step = int(heard[id].step)
	changed.emit()


func _process(delta: float) -> void:
	_clock += delta
	if _clock < CHECK_EVERY or Chronicle.active == null or world.clock == null:
		return
	_clock = 0.0
	if not _placed_again:
		_placed_again = true
		_place_again()
	_offer()
	for id in heard:
		var st: Dictionary = heard[id]
		if st.state != "open":
			continue
		var def: Dictionary = by_id[id]
		var days := float(def.get("expires", {}).get("days", 0))
		# (a step that's "safe": what was at stake is in hand, and the time no longer runs)
		var safe := bool(step_of(def, st).get("safe", false))
		if days > 0.0 and not safe and Chronicle.active.now() - float(st.heard) >= days * 24.0:
			_end(def, st, "ignored")
		elif _step_done(def, st):
			_advance(def, st)


# ---- Who has what to tell ----

# Whether a rumor can be told now: not heard already, and everything its "appears" asks has come about.
func _can_appear(def: Dictionary) -> bool:
	if heard.has(str(def.id)) or not world.village.founded():
		return false
	var ch := Chronicle.active
	var a: Dictionary = def.get("appears", {})
	if world.clock.day() < int(a.get("afterDay", 0)):
		return false
	for c in a.get("after", []):
		var since := ch.days_since(str(c.event))
		if since < 0.0 or since < float(c.get("days", 0)):
			return false
	for e in a.get("unless", []):
		if ch.happened(str(e)):
			return false
	return true


# Each rumor that can be told has someone to tell it (and keeps them, while they're about).
func _offer() -> void:
	var was := offers.duplicate()
	for def in defs:
		var id := str(def.id)
		if not _can_appear(def):
			offers.erase(id)
			continue
		var tellers := Villager.all.filter(func(v): return is_instance_valid(v) and _tells(def, v))
		if tellers.any(func(v): return v.person.name == offers.get(id, "")):
			continue
		if tellers.is_empty():
			offers.erase(id)
			continue
		# (someone with nothing else to tell, if there is one)
		var free := tellers.filter(func(v): return not offers.values().has(v.person.name))
		# (and of those, by their traits: a gossip hears it first, the tight-lipped last)
		var from: Array = free if not free.is_empty() else tellers
		var keenest := -INF
		for v in from:
			keenest = maxf(keenest, Traits.add(v.person, "gossip"))
		offers[id] = from.filter(func(v): return Traits.add(v.person, "gossip") >= keenest).pick_random().person.name
		if not Chronicle.active.happened("known:" + id):
			Chronicle.active.record("known:" + id, {"by": offers[id]})
	if was != offers:
		changed.emit()


func _tells(def: Dictionary, v: Villager) -> bool:
	var t: Dictionary = def.get("teller", {})
	if t.has("name"):
		return str(v.person.name) == str(t.name)
	if t.has("look"):
		return int(v.person.get("look", -1)) == int(t.look)
	return true


## The rumor [param v] has to tell, or {}.
func offer_from(v: Villager) -> Dictionary:
	for id in offers:
		if offers[id] == v.person.name and by_id.has(id) and not heard.has(id):
			return by_id[id]
	return {}


## Whether [param v] has something to tell (shown over their head).
func has_offer(v: Villager) -> bool:
	return not offer_from(v).is_empty()


## [param v] tells the rumor: it's in the journal from now, tracked. What they say.
func hear(id: String, v: Villager) -> String:
	var def: Dictionary = by_id[id]
	var now := Chronicle.active.now()
	var st := {"state": "open", "step": 0, "from": now, "heard": now, "by": str(v.person.name), "places": {}, "notes": "", "tracked": true, "ended": -1.0}
	heard[id] = st
	offers.erase(id)
	_find_place(def, st, 0)
	Chronicle.active.record("heard:" + id, {"by": st.by})
	changed.emit()
	return _fill(str(def.get("told", "")), def, st)


# ---- Steps ----

func step_of(def: Dictionary, st: Dictionary) -> Dictionary:
	var steps: Array = def.get("steps", [])
	return steps[clampi(int(st.step), 0, steps.size() - 1)] if not steps.is_empty() else {}


## Where step [param i] of a heard rumor is (px), or INF if it has no place.
func place_of(st: Dictionary, def: Dictionary, i: int) -> Vector2:
	var steps: Array = def.get("steps", [])
	if i < 0 or i >= steps.size():
		return Vector2.INF
	var p: Variant = st.places.get(str(steps[i].id))
	return Vector2(float(p[0]), float(p[1])) if p is Array else Vector2.INF


# Works out where a step is, once, as it becomes known.
func _find_place(def: Dictionary, st: Dictionary, i: int) -> void:
	var steps: Array = def.get("steps", [])
	if i >= steps.size():
		return
	var pl: Dictionary = steps[i].get("place", {})
	var at := Vector2.INF
	match str(pl.get("kind", "")):
		"forest": at = _wood_in(pl) if pl.has("section") else _a_wood(bool(pl.get("misted", false)))
		"same": at = place_of(st, def, i - 1)
		"of":
			var other: Dictionary = heard.get(str(pl.get("rumor", "")), {})
			var p: Variant = other.get("places", {}).get(str(pl.get("step", "")))
			if p is Array:
				at = Vector2(float(p[0]), float(p[1]))
		"section": at = _section_middle(str(pl.get("section", "")))
		"village": at = world.village.centre()
		"cell": at = world.floors.cell_centre(Vector2i(int(pl.get("x", 0)), int(pl.get("y", 0))))
	if at != Vector2.INF:
		st.places[str(steps[i].id)] = [at.x, at.y]


var _placed_again := false


# The section a step's place is asked to be in (as "F6"), in cells; empty for none.
func _section_rect(step: Dictionary) -> Rect2i:
	var pl: Dictionary = step.get("place", {})
	if str(pl.get("kind", "")) != "forest" or not pl.has("section"):
		return Rect2i()
	var cr := MapMarks.section_of(str(pl.section).to_upper())
	return Rect2i() if cr.is_empty() else MapMarks.section_bounds(int(cr[0]), int(cr[1]))


# A heard rumor whose place was found outside the map section it names (an older game: the woods' edge was looked
# for just past it): found again, there, and the steps that go "same" with it.
func _place_again() -> void:
	for id in heard:
		var st: Dictionary = heard[id]
		var def: Dictionary = by_id[id]
		var steps: Array = def.get("steps", [])
		var moved := false
		for i in steps.size():
			var sect := _section_rect(steps[i])
			var at := place_of(st, def, i)
			if sect.has_area() and at != Vector2.INF and not sect.has_point(world.floors.cell_at(at)):
				_find_place(def, st, i)
				moved = true
			elif moved and str(steps[i].get("place", {}).get("kind", "")) == "same" and st.places.has(str(steps[i].id)):
				_find_place(def, st, i)
		if moved:
			changed.emit()


# The wood in a map section (as "F6"): at the corner of it asked for (as seen on screen), the edge of the trees on
# that side, a way in; else the trees nearest the section's middle. In the mist that can be cleared, if that's asked
# for. With no trees there, a wood near the village.
func _wood_in(pl: Dictionary) -> Vector2:
	var wanted := str(pl.get("section", "")).to_upper()
	var misted := bool(pl.get("misted", false))
	var cells := Rect2i()
	var cr := MapMarks.section_of(wanted)
	if not cr.is_empty():
		cells = MapMarks.section_bounds(int(cr[0]), int(cr[1]))
	var way: Vector2 = {"upper-left": Vector2(-1, -1), "upper-right": Vector2(1, -1), "lower-left": Vector2(-1, 1), "lower-right": Vector2(1, 1)}.get(str(pl.get("corner", "")), Vector2.ZERO)
	# (with no corner asked for: the trees nearest the section's middle, so it's plainly in it)
	var c := world.floors.cell_centre(cells.get_center()) if cells.has_area() else world.village.centre()
	var best := Vector2.INF
	var best_score := -INF
	for g in Gatherable.all:
		if not g.axe or g.depleted() or not cells.has_point(world.floors.cell_at(g.foot)):
			continue
		if misted and world.mist != null and world.mist.tier_at(g.foot) != Mist.Tier.NORMAL:
			continue
		if Wilds.trees_near(g.foot, 3.2 * world.px).size() < 3:
			continue   # (a tree on its own isn't the wood)
		# (the furthest that way; with no corner asked for, the nearest the middle)
		var score: float = g.foot.dot(way) if way != Vector2.ZERO else -g.foot.distance_to(c)
		if score > best_score:
			best_score = score
			best = g.foot
	if best == Vector2.INF:
		return _a_wood(misted)
	# (a corner asked for: just outside the trees, on that side, where she'd walk in; still in the section)
	if way == Vector2.ZERO:
		return best
	var out := best + way.normalized() * Vector2(1.6, 0.8) * world.px
	return out if Wilds.open(world, out, 0.5, 0.3) and cells.has_point(world.floors.cell_at(out)) else best


# The middle of a map section (as "A8"), or the nearest dry ground to it.
func _section_middle(wanted: String) -> Vector2:
	var cr := MapMarks.section_of(wanted)
	if not cr.is_empty():
		if true:
				var b := MapMarks.section_bounds(int(cr[0]), int(cr[1]))
				var mid := b.position + Vector2i(b.size.x >> 1, b.size.y >> 1)
				for r in 12:
					for dx in range(-r, r + 1):
						for dy in range(-r, r + 1):
							var at := world.floors.cell_centre(mid + Vector2i(dx, dy))
							if maxi(absi(dx), absi(dy)) == r and world.water_depth(at) <= 0.0:
								return at
				return world.floors.cell_centre(mid)
	return Vector2.INF


# A wood near the village: the nearest in the mist that can be cleared (not the strong mist), if that's asked for
# and there is one; else the nearest.
func _a_wood(misted: bool) -> Vector2:
	var c := world.village.centre()
	var best := Vector2.INF
	var best_d := INF
	var any := Vector2.INF
	var any_d := INF
	for ring in [10.0, 16.0, 22.0, 30.0]:
		for i in 12:
			var a := i * TAU / 12.0
			var w: Variant = Wilds.forest(world, c + Vector2(cos(a), sin(a) * 0.5) * float(ring) * world.px, 2, 8.0)
			if w == null:
				continue
			var d: float = (w as Vector2).distance_to(c)
			if d < any_d:
				any_d = d
				any = w
			if world.mist != null and world.mist.tier_at(w) == Mist.Tier.NORMAL and d < best_d:
				best_d = d
				best = w
	return best if misted and best != Vector2.INF else any


func _step_done(def: Dictionary, st: Dictionary) -> bool:
	var step := step_of(def, st)
	var done: Dictionary = step.get("done", {})
	var at := place_of(st, def, int(st.step))
	match str(done.get("kind", "")):
		"reach":
			return at != Vector2.INF and _apart(miko.position, at) <= float(done.get("within", 3))
		"cleared":
			return at != Vector2.INF and cleared_share(at, float(done.get("radius", 4))) >= float(done.get("share", 0.6))
		"days":
			return Chronicle.active.now() - float(st.from) >= float(done.get("days", 1)) * 24.0
		"event":
			return Chronicle.active.happened(str(done.get("event", "")))
	return false


# How far apart two places are, in units (as on the ground: the picture's squashed up and down).
func _apart(a: Vector2, b: Vector2) -> float:
	var d := (a - b) / world.px
	return Vector2(d.x, d.y * 2.0).length()


## The share of the ground within [param radius] units of [param at] that's out of the mist (0 to 1).
func cleared_share(at: Vector2, radius: float) -> float:
	if world.mist == null:
		return 1.0
	var clear := 0
	var all := 0
	for ring in 4:
		for i in 10:
			var a := i * TAU / 10.0
			var r := radius * (ring + 1) / 4.0
			all += 1
			if world.mist.tier_at(at + Vector2(cos(a), sin(a) * 0.5) * r * world.px) == Mist.Tier.CLEAR:
				clear += 1
	return float(clear) / float(all)


func _advance(def: Dictionary, st: Dictionary) -> void:
	var id := str(def.id)
	Chronicle.active.record("step:%s/%s" % [id, str(step_of(def, st).get("id", st.step))])
	if int(st.step) + 1 >= (def.get("steps", []) as Array).size():
		_end(def, st, "done")
		return
	st.step = int(st.step) + 1
	st.from = Chronicle.active.now()
	_find_place(def, st, int(st.step))
	FloatingText.spawn(world, "Rumor: something new", miko.position + Vector2(0, -2.2 * world.px), Color(1, 0.86, 0.45), 20, 2.0)
	VillageLog.event("rumor." + id, "%s: there's more to it (J)" % str(def.title))
	changed.emit()


# A rumor's over: it came to something (what, only now), or it was left too long.
func _end(def: Dictionary, st: Dictionary, how: String) -> void:
	var id := str(def.id)
	st.state = how
	st.ended = Chronicle.active.now()
	st.tracked = false
	Chronicle.active.record("%s:%s" % [how, id])
	if how == "done":
		var rw: Dictionary = def.get("reward", {})
		var at := place_of(st, def, int(st.step))
		for g in rw.get("gifts", []):
			world.village.give(miko.bag, miko, str(g[0]), int(g[1]), miko.position)
		for e in rw.get("effects", []):
			_effect(str(e), at)
		var line := _fill(str(rw.get("log", "")), def, st)
		VillageLog.event("rumor." + id, line if line != "" else "%s: it came to something" % str(def.title))
		FloatingText.spawn(world, "Rumor resolved", miko.position + Vector2(0, -2.2 * world.px), Color(0.7, 1.0, 0.7), 20, 2.0)
	else:
		# Left too long: what comes of that.
		var fl: Dictionary = def.get("failed", {})
		for e in fl.get("effects", []):
			_effect(str(e), place_of(st, def, int(st.step)))
		var lost_line := _fill(str(fl.get("log", "")), def, st)
		VillageLog.event("rumor." + id, lost_line if lost_line != "" else "%s: nothing was done about it" % str(def.title), VillageLog.Kind.DANGER if lost_line != "" else VillageLog.Kind.WARNING)
	changed.emit()


# What a rumor's reward does in the world, by name.
func _effect(e: String, at: Vector2) -> void:
	var people: Villagers = get_parent().get_node_or_null("Villagers")
	if e.begins_with("unique_arrives:") and people != null:
		Uniques.arrive(people, e.get_slice(":", 1))
		return
	if e.begins_with("unique_lost:"):
		Uniques.lose(e.get_slice(":", 1))
		return
	if e.begins_with("record:"):
		Chronicle.active.record(e.trim_prefix("record:"))
		return
	match e:
		"rabbit_hole":
			# Rabbits move in: a hole at the wood, on open ground out of the mist.
			if at == Vector2.INF:
				return
			for i in 40:
				var a := randf() * TAU
				var p := at + Vector2(cos(a), sin(a) * 0.5) * randf_range(1.0, 3.5) * world.px
				if world.mist.tier_at(p) == Mist.Tier.CLEAR and Wilds.open(world, p, 1.0, 0.5):
					world.props.place_free(p, "RabbitHole")
					return


# ---- For the journal and the maps ----

## The heard rumors, for the journal: those still open first (newest first), then the rest.
func listed() -> Array:
	var ids := heard.keys()
	ids.sort_custom(func(a, b):
		var oa: bool = heard[a].state == "open"
		var ob: bool = heard[b].state == "open"
		return float(heard[a].heard) > float(heard[b].heard) if oa == ob else oa)
	return ids


## The journal's lines for a rumor: one for each step known so far, [text, done].
func lines(id: String) -> Array:
	var def: Dictionary = by_id[id]
	var st: Dictionary = heard[id]
	var out := []
	var steps: Array = def.get("steps", [])
	for i in mini(int(st.step) + 1, steps.size()):
		out.append([_fill(str(steps[i].get("note", "")), def, st), i < int(st.step) or st.state == "done"])
	return out


func set_notes(id: String, text: String) -> void:
	if heard.has(id):
		heard[id].notes = text


func set_tracked(id: String, on: bool) -> void:
	if heard.has(id):
		heard[id].tracked = on
		changed.emit()


## What the maps show: for each tracked rumor still open with somewhere to be, {id, title, at (px: the ring's
## middle, off from the place itself), radius (px)}. It's somewhere in the ring, not at its middle.
func marks() -> Array:
	var out := []
	for id in heard:
		var st: Dictionary = heard[id]
		if st.state != "open" or not bool(st.tracked):
			continue
		var def: Dictionary = by_id[id]
		var at := place_of(st, def, int(st.step))
		if at == Vector2.INF:
			continue
		var vague := float(step_of(def, st).get("place", {}).get("vague", 4))
		# (the same way off each time it's asked: by the rumor and the step)
		var h := hash("%s/%d" % [id, int(st.step)])
		var a := float(h % 628) / 100.0
		var off := Vector2(cos(a), sin(a) * 0.5) * vague * 0.55 * world.px
		# (a place in a named section: its ring kept wholly in that section)
		var sect := _section_rect(step_of(def, st))
		if sect.has_area():
			var v := mini(int(ceilf(vague)), floori(mini(sect.size.x, sect.size.y) / 2.0) - 1)
			var c := world.floors.cell_at(at + off)
			var inside := Vector2i(clampi(c.x, sect.position.x + v, sect.end.x - 1 - v), clampi(c.y, sect.position.y + v, sect.end.y - 1 - v))
			if inside != c:
				off = world.floors.cell_centre(inside) - at
		out.append({"id": id, "title": str(def.title), "at": at + off, "radius": vague * world.px})
	return out


## Draws the tracked rumors' rings on a map: [param to_point] turns a place (px) into a point on [param canvas],
## [param scale] is the map's px to one of the world's.
func draw_marks(canvas: CanvasItem, to_point: Callable, scale: float, frame: Rect2, names: bool) -> void:
	var k := HudStyle.SCALE
	for m in marks():
		var p: Vector2 = to_point.call(m.at)
		var r: float = float(m.radius) * scale
		if not frame.grow(r).has_point(p):
			continue
		canvas.draw_set_transform(p, 0.0, Vector2(1.0, 0.5))
		canvas.draw_circle(Vector2.ZERO, r, Color(1.0, 0.82, 0.3, 0.16))
		canvas.draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(1.0, 0.82, 0.3, 0.9), maxf(1.5, 1.5 * k), true)
		canvas.draw_set_transform(Vector2.ZERO)
		var f := HudStyle.font("bold")
		var sz := roundi(13 * k)
		canvas.draw_string_outline(f, p + Vector2(-20 * k, 5 * k), "?", HORIZONTAL_ALIGNMENT_CENTER, 40 * k, sz, 4, Color(0, 0, 0, 0.8))
		canvas.draw_string(f, p + Vector2(-20 * k, 5 * k), "?", HORIZONTAL_ALIGNMENT_CENTER, 40 * k, sz, Color(1.0, 0.86, 0.45))
		if names:
			var ts := roundi(11 * k)
			var at := p + Vector2(-120 * k, r * 0.5 + 14 * k)
			canvas.draw_string_outline(f, at, str(m.title), HORIZONTAL_ALIGNMENT_CENTER, 240 * k, ts, 4, Color(0, 0, 0, 0.8))
			canvas.draw_string(f, at, str(m.title), HORIZONTAL_ALIGNMENT_CENTER, 240 * k, ts, Color(1.0, 0.9, 0.6))


# A line with its names filled in: {dir} (which way the rumor's first place lies from the village), {teller}, {miko}.
func _fill(text: String, def: Dictionary, st: Dictionary) -> String:
	var at := place_of(st, def, 0)
	return text.format({"dir": direction(at) if at != Vector2.INF else "north", "teller": str(st.by), "miko": Playable.name_now()})


## Which way [param at] lies from the village's middle, as "north-west" (up the screen is north).
func direction(at: Vector2) -> String:
	var d := at - world.village.centre()
	d.y *= 2.0
	var names := ["east", "south-east", "south", "south-west", "west", "north-west", "north", "north-east"]
	return names[posmod(roundi(d.angle() / (PI / 4.0)), 8)]
