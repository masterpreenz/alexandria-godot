class_name Spawners
extends Node
## Puts the monsters about (from Unity's SlimeSpawner and BoarSpawner).
## - Slimes come out of the mist: small ones on their own (every other one within reach of Miko, so they're met), and a
##   few large ones each with a little group of small ones round it; only where there's mist, never in or near the
##   village, in a house, on anything solid or right beside her. Each is stronger by the mist it came out of. Every
##   so often the numbers are topped back up; ones left on ground the mist no longer covers, away from her, go. A few
##   small ones also live in the healthy forest, spread out.
## - Boars live in the healthy forest: among trees, not by roads or out in the open, outside the village, never beside
##   her, one to a stretch of forest. Each new day the number is topped back up.

var world: World
var d: Dictionary                 ## monsters.json
var small: Array[Slime] = []
var large: Array[Slime] = []
var forest: Array[Slime] = []
var boars: Array[Boar] = []
var _next_restock := 0.0
var _last_day := -1


func setup(w: World, data: Dictionary) -> void:
	world = w
	d = data


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _process(delta: float) -> void:
	var __t := Time.get_ticks_usec()
	_process_timed(delta)
	Perf.add(&"spawners.process", __t)


func _process_timed(_delta: float) -> void:
	# Not before the forest is laid out (which woods are rotten decides where the wildlife goes).
	if world.player == null or not Corruption.ready():
		return
	if d.has("slime") and _now() >= _next_restock:
		_next_restock = _now() + float(d.slimeSpawner.restockEvery)
		restock_slimes()
	var day: int = world.clock.day() if world.clock != null else 1
	if d.has("boar") and day != _last_day:
		_last_day = day
		restock_boars()


static func _alive(list: Array) -> Array:
	return list.filter(func(x): return is_instance_valid(x))


func _ppos() -> Vector2:
	return world.player.position


# Left on ground the mist no longer covers, and Miko isn't about: it goes (one in the village stays: it's attacking).
func _stranded(sl: Slime) -> bool:
	return not world.village.contains(sl.position, 0.5) and world.mist.tier_at(sl.position) == Mist.Tier.CLEAR \
		and _ppos().distance_to(sl.position) > 12.0 * world.px


## Brings the slimes back up to their numbers.
func restock_slimes() -> void:
	var __t := Time.get_ticks_usec()
	_restock_slimes_untimed()
	Perf.add(&"spawning: slimes", __t)


func _restock_slimes_untimed() -> void:
	var sp: Dictionary = d.slimeSpawner
	small.assign(_alive(small))
	large.assign(_alive(large))
	for sl in small.duplicate():
		if _stranded(sl):
			small.erase(sl)
			sl.queue_free()
	for sl in large.duplicate():
		if _stranded(sl):
			large.erase(sl)
			sl.queue_free()
	for i in range(large.size(), int(sp.largeCount)):
		if not _budget():
			_next_restock = _now()
			return
		# The first large group not far from Miko, the rest anywhere.
		var at: Variant = _spot_near(9.0, 16.0) if i == 0 else null
		if at == null:
			at = Wilds.find_spot(world, _free, 60)
		if at == null:
			break
		large.append(_slime(true, at))
		var gs: Array = sp.groupSize
		for g in randi_range(int(gs[0]), int(gs[1])):
			for tries in 8:
				var r := Vector2.from_angle(randf() * TAU) * randf_range(0.8, 1.6) * world.px
				var near: Vector2 = at + Vector2(r.x, r.y * 0.5)
				if _free(near):
					small.append(_slime(false, near))
					break
	# A few living in the healthy forest, one to a stretch of it.
	forest.assign(_alive(forest))
	for i in range(forest.size(), int(sp.forestCount)):
		if not _budget():
			_next_restock = _now()
			return
		var at: Variant = Wilds.find_spot(world, _forest_spot, 120)
		if at == null:
			break
		var sl := Slime.spawn(world, d.slime, false, at)
		sl.name = "Forest Slime"
		forest.append(sl)
	# The ones with a large slime don't count against the loners.
	var loners := small.size() - _grouped()
	for i in range(loners, int(sp.smallCount)):
		if not _budget():
			_next_restock = _now()
			return
		# Every other one within reach of Miko (but not on top of her), so they're met.
		var at: Variant = _spot_near(7.0, 15.0) if i % 2 == 0 else null
		if at == null:
			at = Wilds.find_spot(world, _free, 60)
		if at == null:
			break
		small.append(_slime(false, at))


## How many creatures may be made in one frame: making them is the costly part, so a restock fills in over a few
## frames instead of stalling one.
const PER_FRAME := 3
var _made := 0
var _made_frame := -1


func _budget() -> bool:
	if Engine.get_process_frames() != _made_frame:
		_made_frame = Engine.get_process_frames()
		_made = 0
	_made += 1
	return _made <= PER_FRAME


func _slime(is_large: bool, at: Vector2) -> Slime:
	return Slime.spawn(world, d.slime, is_large, at, world.mist.power(at))


func _grouped() -> int:
	var n := 0
	for sl in small:
		for l in large:
			if is_instance_valid(l) and sl.position.distance_to(l.position) < 2.5 * world.px:
				n += 1
				break
	return n


func _spot_near(lo: float, hi: float) -> Variant:
	for tries in 40:
		var a := randf() * TAU
		var r := randf_range(lo, hi) * world.px
		var spot := _ppos() + Vector2(cos(a) * r, sin(a) * r * 0.5)
		if _free(spot):
			return spot
	return null


# Out of the mist: open ground, not right beside Miko.
func _free(at: Vector2) -> bool:
	if _ppos().distance_to(at) < float(d.slimeSpawner.awayFromPlayer) * world.px:
		return false
	if world.mist.tier_at(at) == Mist.Tier.CLEAR:
		return false
	return Wilds.open(world, at, float(d.slimeSpawner.villageMargin))


func _forest_spot(at: Vector2) -> bool:
	var sp: Dictionary = d.slimeSpawner
	if _ppos().distance_to(at) < float(sp.awayFromPlayer) * world.px:
		return false
	for sl in forest:
		if is_instance_valid(sl) and sl.position.distance_to(at) < float(sp.forestApart) * world.px:
			return false
	return Wilds.healthy_forest(world, at) and Wilds.open(world, at, float(sp.villageMargin) + 2.0)


## Brings the boars back up to their number (any that ended up in the village go).
func restock_boars() -> void:
	var __t := Time.get_ticks_usec()
	_restock_boars_untimed()
	Perf.add(&"spawning: boars", __t)


func _restock_boars_untimed() -> void:
	boars.assign(_alive(boars))
	for b in boars.duplicate():
		if world.village.contains(b.position, 0.5):
			boars.erase(b)
			b.queue_free()
	for i in range(boars.size(), int(d.boarSpawner.count)):
		if not _budget():
			_last_day = -1   # the rest next frame
			return
		var at: Variant = Wilds.find_spot(world, _boar_fits, 160)
		if at == null:
			break
		boars.append(Boar.spawn(world, d.boar, at))


func _boar_fits(at: Vector2) -> bool:
	var sp: Dictionary = d.boarSpawner
	if _ppos().distance_to(at) < float(sp.awayFromPlayer) * world.px:
		return false
	for b in boars:
		if is_instance_valid(b) and b.position.distance_to(at) < float(sp.apart) * world.px:
			return false
	# Not in the mist: boars only live where it's been cleared (a crystal's living forest).
	if world.mist != null and world.mist.tier_at(at) != Mist.Tier.CLEAR:
		return false
	return Wilds.healthy_forest(world, at) and Wilds.open(world, at, float(sp.villageMargin), 0.45)
