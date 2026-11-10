class_name Raids
extends Node
## Raids on the village (monsters.json's raids): now and then, at night, a horde comes out of the mist at it, from
## any side. Mutated villagers mostly, a few slimes; more of them the longer the village has stood. They make straight
## for the village, breaking down any barricade across their way, and go for whoever they find there, Miko or the
## villagers; with nobody about they roam it. The village log warns of it. At dawn what's left of them falls back
## into the mist (they become ordinary monsters again). It's random: most nights nothing comes.

var world: World
var d: Dictionary                ## monsters.json
var raiders: Array = []          ## the horde about now
var _hour_seen := -1
var _last_night := -1            ## the night (its day) the last raid came: one a night at most


func setup(w: World, data: Dictionary) -> void:
	world = w
	d = data


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
func start(count := -1) -> int:
	var st := _settings()
	var centre := world.village.centre()
	var box := world.village.bounds()
	var out := maxf(box.size.x, box.size.y) / 2.0 + float(st.from) * world.px
	var spot: Variant = null
	var heading := randf() * TAU
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
	if miko != null:
		FloatingText.spawn(world, Loc.t("raid.float", {"side": side}), miko.position + Vector2(0, -2.0 * world.px), Color(1.0, 0.45, 0.4))
	# The villagers in the village shout it.
	for v in Villager.all:
		if is_instance_valid(v) and world.village.contains(v.position) and not v.in_bed:
			v.bark("bark.raid", {"side": side}, true)
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


## Somewhere in the village for a raider to make for: a random spot within its square.
static func spot_in_village(w: World) -> Vector2:
	var c := w.village.centre()
	var h := w.village.half_size() * 0.8
	var off := Vector2(randf_range(-h, h), randf_range(-h, h))
	return w.floors.corner(w.floors.fractional_cell(c) + off)
