class_name Raids
extends Node
## Raids on the village (monsters.json's raids): now and then, at night, a horde comes out of the mist at it, from
## any side. Mutated villagers mostly, a few slimes; more of them the longer the village has stood. They make straight
## for the village, breaking down any barricade across their way, and go for whoever they find there, Miko or the
## villagers; with nobody about they roam it. The village log warns of it. At dawn what's left of them falls back
## into the mist (they become ordinary monsters again). It's random: most nights nothing comes.

static var active: Raids

var world: World
var d: Dictionary                ## monsters.json
var raiders: Array = []          ## the horde about now
var _hour_seen := -1
var _last_night := -1            ## the night (its day) the last raid came: one a night at most
const WALL_TOUGH := 45.0         ## what a house wall takes before it gives way
const MOST_BROKEN := 4           ## walls broken in any one house in a raid, at most
var wear := {}                   ## house walls being hit: wall key -> damage taken
var broken := {}                 ## house key -> walls broken in it this raid
var _walls := []                 ## the house walls that can be broken: [{e: [x, y, alongY, type], mid, house}]
var _walls_at := -10.0


func setup(w: World, data: Dictionary) -> void:
	world = w
	d = data
	active = self


## Whether a raid's on: the horde's about. Then every villager who can fight does.
static func on() -> bool:
	return active != null and not active.raiders.is_empty()


## Whether [param body] is one of the raid's.
static func raider(body: Node) -> bool:
	return active != null and active.raiders.has(body)


func _settings() -> Dictionary:
	return d.get("raids", {"firstDay": 3, "chancePerHour": 0.04, "size": [3, 10], "slimeShare": 0.3, "from": 12.0})


func _night() -> bool:
	var h: float = world.clock.hour()
	return h >= 20.0 or h < 5.5


func _process(_delta: float) -> void:
	var __t := Time.get_ticks_usec()
	_process_timed()
	Perf.add(&"raids.process", __t)


func _process_timed() -> void:
	if world.clock == null or not world.village.founded():
		return
	if not raiders.is_empty():
		raiders = raiders.filter(func(r): return is_instance_valid(r))
		if raiders.is_empty():
			VillageLog.event("raid", Loc.t("raid.beaten"))
		elif not _night():
			_fall_back()
		return
	# Each game hour of the night, a chance of one.
	var slot := floori(world.clock.hours)
	if slot == _hour_seen:
		return
	_hour_seen = slot
	var st := _settings()
	var night_of: int = world.clock.day() - (1 if world.clock.hour() < 12.0 else 0)
	if _night() and world.clock.day() >= int(st.firstDay) and night_of != _last_night and randf() < float(st.chancePerHour):
		start()


## Sends a horde at the village now (from a random side); how many came (0 if there was nowhere for them to come from).
## A raid sets out (of [param count] monsters, or as the night has it), from [param toward] (an angle round the
## village; anywhere when INF). [param quiet]: no word of it floating over Sera (another band of the same raid).
func start(count := -1, toward := INF, quiet := false) -> int:
	var st := _settings()
	if raiders.filter(func(r): return is_instance_valid(r)).is_empty():
		wear.clear()
		broken.clear()
		_walls_at = -10.0
	var centre := world.village.centre()
	var box := world.village.bounds()
	var out := maxf(box.size.x, box.size.y) / 2.0 + float(st.from) * world.px
	var spot: Variant = null
	var heading := randf() * TAU if toward == INF else toward
	for tries in 60:
		var a := heading + randf_range(-0.7, 0.7)
		var p := centre + Vector2(cos(a), sin(a) * 0.5) * out * randf_range(1.0, 1.25)
		if world.mist.tier_at(p) != Mist.Tier.CLEAR and Wilds.open(world, p, 2.0) and Wilds.dry_way(world, p, centre):
			spot = p
			heading = a
			break
	if spot == null:
		return 0
	var size: Array = st.size
	var n := count if count > 0 else clampi(int(size[0]) + floori(world.clock.day() / 2.0), int(size[0]), int(size[1]))
	var md := d
	for i in n:
		var at: Vector2 = spot + Vector2.from_angle(randf() * TAU) * randf_range(0.3, 2.0) * world.px
		if not Wilds.dry(world, at, 0.3):
			at = spot
		var m: Creature
		if randf() < float(st.slimeShare) and md.has("slime"):
			var sl := Slime.spawn(world, md.slime, randf() < 0.25, at, world.mist.power(at))
			sl.angry_until = INF
			sl.home = centre
			m = sl
		else:
			m = MutatedVillager.spawn(world, md.mutatedVillager, at)
		m.raid_to = spot_in_village(world)
		raiders.append(m)
	_last_night = world.clock.day() - (1 if world.clock.hour() < 12.0 else 0)
	var dirs := ["east", "south-east", "south", "south-west", "west", "north-west", "north", "north-east"]
	var side := Loc.t("dir." + dirs[posmod(roundi(heading / (TAU / 8.0)), 8)])
	VillageLog.problem("raid", Loc.t("raid.warning", {"side": side, "count": n}), VillageLog.Kind.DANGER)
	var miko := world.player
	if miko != null and not quiet:
		FloatingText.spawn(world, Loc.t("raid.float", {"side": side}), miko.position + Vector2(0, -2.0 * world.px), Color(1.0, 0.45, 0.4))
	# The villagers in the village shout it.
	for v in Villager.all:
		if is_instance_valid(v) and world.village.contains(v.position) and not v.in_bed:
			v.bark("bark.raid", {"side": side}, true)
			v.show_mood("alarm", 8.0)
	return n


# Dawn: what's left of the horde falls back into the mist, ordinary monsters again.
func _fall_back() -> void:
	for r in raiders:
		if not is_instance_valid(r):
			continue
		r.raid_to = Vector2.INF
		if r is Slime:
			(r as Slime).angry_until = Creature.now()
			(r as Slime).home = r.position
	raiders.clear()
	VillageLog.event("raid", Loc.t("raid.dawn"))


# ---- The houses' walls: smashed at by raiders with nobody near to go for ----

## The house walls that can be broken now (not doors or windows, gates, fences or barricades; not in a house that's
## had its fill broken).
func house_walls() -> Array:
	var t := Creature.now()
	if t - _walls_at < 2.0:
		return _walls
	_walls_at = t
	var seen := {}
	_walls = []
	if Upkeep.active == null:
		return _walls
	for h in Upkeep.active.houses():
		if int(broken.get(h.key, 0)) >= MOST_BROKEN:
			continue
		for c in h.cells:
			for e in [WallMap.Edge.new(c, true), WallMap.Edge.new(c + Vector2i(1, 0), true), WallMap.Edge.new(c, false), WallMap.Edge.new(c + Vector2i(0, 1), false)]:
				var ty := world.walls.get_wall(e)
				if ty == "" or seen.has(e.key()) or world.walls.hp.has(e.key()):
					continue
				var info: Dictionary = world.walls.types[ty]
				if float(info.opening) != 0.0 or str(info.toggle) != "" or bool(info.get("fence", false)):
					continue
				seen[e.key()] = true
				_walls.append({"e": [e.vertex.x, e.vertex.y, e.along_y, ty], "mid": world.walls.edge_middle(e), "house": h.key})
	return _walls


## The nearest house wall to [param p] within [param within] (px), or {} when there's none.
func house_wall_near(p: Vector2, within: float) -> Dictionary:
	var best := {}
	var best_d := within
	for w in house_walls():
		var dd := p.distance_to(w.mid)
		if dd < best_d:
			best_d = dd
			best = w
	return best


## Whether the house wall [param w] (from [method house_wall_near]) still stands.
func standing(w: Dictionary) -> bool:
	return not w.is_empty() and world.walls.get_wall(WallMap.Edge.new(Vector2i(int(w.e[0]), int(w.e[1])), bool(w.e[2]))) != ""


## A raider hits the house wall [param w] for [param amount]: the house the worse for it, and once the wall's taken
## enough it gives way (planned to be built again).
func strike_house_wall(w: Dictionary, amount: float) -> void:
	if not standing(w):
		return
	var e := WallMap.Edge.new(Vector2i(int(w.e[0]), int(w.e[1])), bool(w.e[2]))
	var k := e.key()
	wear[k] = float(wear.get(k, 0.0)) + amount
	HitFx.sound(world, w.mid)
	Puffs.burst(world, w.mid, 0.5, 3)
	if Upkeep.active != null:
		Upkeep.active.condition[w.house] = maxf(10.0, float(Upkeep.active.condition.get(w.house, 100.0)) - amount * 0.4)
	if float(wear[k]) >= WALL_TOUGH:
		wear.erase(k)
		broken[w.house] = int(broken.get(w.house, 0)) + 1
		_walls_at = -10.0
		smash(world, w.e)


## A wall smashed in ([param b]: [x, y, alongY, type]): gone, with dust and the crack of it, and planned to be built
## again.
static func smash(w: World, b: Array) -> void:
	var e := WallMap.Edge.new(Vector2i(int(b[0]), int(b[1])), bool(b[2]))
	if w.walls.get_wall(e) == "":
		return
	var at := w.walls.edge_middle(e)
	w.walls.remove(e)
	Puffs.burst(w, at, 1.2, 10)
	HitFx.sound(w, at)
	if Construction.active != null:
		Construction.active.plan_wall(e, str(b[3]))
		Construction.active.start_building()


## Somewhere in the village for a raider to make for: a random spot within its square.
static func spot_in_village(w: World) -> Vector2:
	var c := w.village.centre()
	var h := w.village.half_size() * 0.8
	var off := Vector2(randf_range(-h, h), randf_range(-h, h))
	return w.floors.corner(w.floors.fractional_cell(c) + off)
