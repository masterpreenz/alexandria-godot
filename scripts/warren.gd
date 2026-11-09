class_name Warren
extends Node
## Keeps rabbits in the rabbit holes (from Unity's RabbitWarren). It looks over the placed props now and then for
## holes: a new hole gets its rabbits (they come out of it after a while), a hole that's gone leaves its rabbits
## homeless, and each new day every hole is topped back up to its number. Rabbits dig their own holes too: on open
## grass at the edge of a healthy wood, never deep in it. At the start the world gets its share of them; after that,
## one more a day while there are fewer. The holes are ordinary props, so they're saved with the world; the rabbits
## aren't, they're simply there again.

## A rabbit hole in the world, and whether it's still there.
class Hole:
	var position := Vector2.ZERO
	var alive := true
	var rabbits: Array = []

var world: World
var d: Dictionary                   ## monsters.json
var holes := {}                     ## Vector2i key -> Hole
var _looked_at := -1
var _next_look := 0.0
var _dig_from := 0.0
var _dug_at_start := false
var _to_dig := 0
var _last_day := -1


func setup(w: World, data: Dictionary) -> void:
	world = w
	d = data
	_dig_from = _now() + 4.0


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _process(delta: float) -> void:
	var __t := Time.get_ticks_usec()
	_process_timed(delta)
	Perf.add(&"warren.process", __t)


func _process_timed(_delta: float) -> void:
	if world.player == null or not d.has("rabbit"):
		return
	var t := _now()
	if t >= _next_look:
		_next_look = t + float(d.rabbitSpawner.lookEvery)
		look()
	# The world's share of holes, once the saved one is in; and one more each new day while short.
	if not _dug_at_start and t >= _dig_from:
		_dug_at_start = true
		_to_dig = int(d.rabbitSpawner.wildHoles) * 3
	# One try a frame, so digging the world's share never stalls a frame.
	if _to_dig > 0:
		_to_dig -= 1
		if not _dig():
			_to_dig = 0
	var day: int = world.clock.day() if world.clock != null else 1
	if day != _last_day:
		var first := _last_day < 0
		_last_day = day
		if not first and _dug_at_start:
			_to_dig = maxi(_to_dig, 3)
		for h in holes.values():
			_fill(h, 1.0, 20.0)


static func _key(at: Vector2) -> Vector2i:
	return Vector2i(roundi(at.x / 6.4), roundi(at.y / 6.4))


## Finds the holes among the placed props: new ones get rabbits, missing ones are let go.
func look() -> void:
	var prop: String = d.rabbitSpawner.holeProp
	if world.props.version == _looked_at:
		return
	_looked_at = world.props.version
	var seen := {}
	for at in world.props_named(prop):
		var key := _key(at)
		seen[key] = true
		if holes.has(key):
			continue
		var h := Hole.new()
		h.position = at
		holes[key] = h
		_fill(h, 3.0, 12.0)
	for key in holes.keys():
		if not seen.has(key):
			holes[key].alive = false
			holes.erase(key)


# Tops a hole up to its number, each new rabbit coming out after a while.
func _fill(h: Hole, soonest: float, latest: float) -> void:
	h.rabbits = h.rabbits.filter(func(r): return is_instance_valid(r))
	# A hole the mist has covered stays empty until it's cleared again.
	if world.mist != null and world.mist.tier_at(h.position) != Mist.Tier.CLEAR:
		return
	for i in range(h.rabbits.size(), int(d.rabbitSpawner.perHole)):
		h.rabbits.append(Rabbit.spawn(world, d.rabbit, h, randf_range(soonest, latest)))


# One try at digging a new hole while the world has fewer than its share; false once it has enough.
func _dig() -> bool:
	look()
	if holes.size() >= int(d.rabbitSpawner.wildHoles):
		return false
	var at: Variant = _forest_edge()
	if at != null:
		world.props.place_free(at, d.rabbitSpawner.holeProp)  # the next look finds it and gives it its rabbits
	return true


# Open grass at the edge of a wood: a few steps out from a tree that has others round it, with no tree right on top
# of it (or in front, where its top would hide it), away from the other holes, the village and Miko.
func _forest_edge() -> Variant:
	var trees := []
	for g in Gatherable.all:
		if g.axe and not g.depleted():
			trees.append(g.foot)
	if trees.is_empty():
		return null
	var px := world.px
	for tries in 60:
		var tree: Vector2 = trees[randi() % trees.size()]
		if Wilds.trees_near(tree, 3.2 * px).size() - 1 < 2:
			continue
		var a := randf() * TAU
		var r := randf_range(1.6, 2.8) * px
		var spot := tree + Vector2(cos(a) * r, sin(a) * r * 0.5)
		# Not in the mist: rabbits only live where it's been cleared (a crystal's living forest).
		if world.mist != null and world.mist.tier_at(spot) != Mist.Tier.CLEAR:
			continue
		if not Wilds.vegetation(world, spot) or not Wilds.open(world, spot, 2.0, 0.7):
			continue
		if not Wilds.healthy_forest(world, spot, 3, 4.0):
			continue
		if world.player.position.distance_to(spot) < float(d.rabbitSpawner.digAwayFromPlayer) * px:
			continue
		var near_tree := false
		for t in Wilds.trees_near(spot, 3.0 * px):
			var dd: Vector2 = t - spot
			# Right on top of it, or standing in front (below it on screen) where the treetop would hide it.
			if dd.length() < 1.3 * px or (dd.y > 0.0 and dd.y < 2.6 * px and absf(dd.x) < 1.6 * px):
				near_tree = true
				break
		if near_tree or _open_sides(spot) < 3:
			continue
		var near_hole := false
		for h in holes.values():
			if h.position.distance_to(spot) < 7.0 * px:
				near_hole = true
				break
		if near_hole:
			continue
		return spot
	return null


# Of eight ways out from the spot, how many reach open ground (no tree near a point 3 steps out).
func _open_sides(spot: Vector2) -> int:
	var n := 0
	for i in 8:
		var a := i * PI / 4.0
		if Wilds.trees_near(spot + Vector2(cos(a) * 3.0, sin(a) * 1.5) * world.px, 1.6 * world.px).is_empty():
			n += 1
	return n
