class_name Party
extends Node
## Sera's party: up to [constant MOST] companions besides her (four in all), unique characters who've joined her.
## They follow her wherever she goes, keep up (or catch up, a long way behind), fight what comes at her or them, and do
## what she asks: talking to one, "Chop or mine here" (the nearest tree or rock to her, its wood or stone into her bag),
## "Wait here", "Follow me", "Go home" (leave the party). One joins when the story says so (the chronicle's
## "party_join:<id>", once they're up and about: Miyu after she's slept off her rescue). Saved (world.party).

const MOST := 3
const BEHIND := 1.4               ## units behind her a companion keeps
const CATCH_UP := 28.0            ## units away a companion's brought up to her (a long way behind: teleported, the road)
const GUARD := 7.0                ## units from her they go for a monster

static var active: Party

var world: World
var miko: Miko
var people: Villagers
var members: Array = []           ## unique ids, in the order they joined
var waiting := {}                 ## id -> where they were told to wait (px)
var hud: VBoxContainer


func setup(w: World, who: Miko, vs: Villagers, hud_root: Node) -> void:
	world = w
	miko = who
	people = vs
	active = self
	hud = VBoxContainer.new()
	hud.add_theme_constant_override("separation", int(4 * HudStyle.SCALE))
	hud.position = Vector2(18, 140) * HudStyle.SCALE
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.add_child(hud)


func to_json() -> String:
	var w := {}
	for id in waiting:
		w[id] = [waiting[id].x, waiting[id].y]
	return JSON.stringify({"members": members, "waiting": w})


func from_json(json: String) -> void:
	var d: Variant = JSON.parse_string(json)
	if d is Dictionary:
		members = (d.get("members", []) as Array).map(func(m): return str(m))
		for id in d.get("waiting", {}):
			var p: Array = d.waiting[id]
			waiting[str(id)] = Vector2(float(p[0]), float(p[1]))


## Whether person [param p] is one of Sera's party.
func has_member(p: Dictionary) -> bool:
	return members.has(str(p.get("unique", "")))


## Their place in the party (0 the first), for where they walk.
func place_of(p: Dictionary) -> int:
	return members.find(str(p.get("unique", "")))


func full() -> bool:
	return members.size() >= MOST


## [param id] joins (if there's room, they're here, and they can).
func join(id: String) -> bool:
	if members.has(id) or full():
		return false
	var p := Uniques.person(people, id)
	if p.is_empty() or not Traits.has(p, "unique"):
		return false
	members.append(id)
	waiting.erase(id)
	if Chronicle.active != null and not Chronicle.active.happened("party:" + id):
		Chronicle.active.record("party:" + id)
	VillageLog.event("party:" + id, "%s has joined you" % str(p.name))
	_hud()
	return true


func leave(id: String) -> void:
	members.erase(id)
	waiting.erase(id)
	_hud()


func wait_here(p: Dictionary, at: Vector2) -> void:
	waiting[str(p.unique)] = at


func follow(p: Dictionary) -> void:
	waiting.erase(str(p.get("unique", "")))


## Where [param p] is to be (px): behind Sera, fanned out by their place; or where they were told to wait.
func spot_for(p: Dictionary) -> Vector2:
	var id := str(p.get("unique", ""))
	if waiting.has(id):
		return waiting[id]
	var i := maxi(0, place_of(p))
	var back := Vector2(-1.0 if miko.facing_right else 1.0, -0.5 if not miko.facing_up else 0.5).normalized()
	var side := Vector2(-back.y, back.x)
	return miko.position + (back * BEHIND + side * (float(i) - float(members.size() - 1) / 2.0) * 0.9) * world.px


var _next := 0.0


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now < _next:
		return
	_next = now + 1.0
	# The story's joins, once they're up and about.
	if Chronicle.active != null and not full():
		for e in Chronicle.active.events:
			var what := str(e.what)
			if not what.begins_with("party_join:"):
				continue
			var id := what.trim_prefix("party_join:")
			if members.has(id) or Chronicle.active.happened("party:" + id) or Uniques.lost(id):
				continue
			var p := Uniques.person(people, id)
			if p.is_empty() or world.clock.hours < float(p.get("restUntil", -1.0)):
				continue
			join(id)
	_hud()


# Their faces and health, under Sera's card.
func _hud() -> void:
	if hud == null:
		return
	var want := members.size()
	while hud.get_child_count() > want:
		var c := hud.get_child(hud.get_child_count() - 1)
		hud.remove_child(c)
		c.queue_free()
	for i in want:
		var p := Uniques.person(people, str(members[i]))
		if p.is_empty():
			continue
		var row: Label
		if i < hud.get_child_count():
			row = hud.get_child(i)
		else:
			row = HudStyle.label("", 11, "bold", HudStyle.color("text"))
			row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			hud.add_child(row)
		var hp := float(p.get("hp", 0.0))
		var most := maxf(1.0, float(p.get("maxHp", 1.0)))
		var bar := "■".repeat(roundi(8.0 * clampf(hp / most, 0.0, 1.0)))
		row.text = "%s  %s%s" % [p.name, bar, "  (waiting)" if waiting.has(str(members[i])) else ""]
