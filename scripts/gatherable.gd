class_name Gatherable
extends Node2D
## Something to gather from (from Unity's MiningSpot): a rock mined with the pickaxe for stone, or a tree chopped with
## the axe for wood. Each strike shakes it and knocks some off as pickups. A big rock breaks down into smaller ones as
## it's mined (its crumbles); once the last runs out a rock crumbles to rubble and a tree falls (toppling, slamming
## down in dust, bouncing, bursting into logs along its length), and either grows back after a while.
## Trees hold [code]tree_wood[/code] times the wood set on them: that many more swings, that many more logs.
##
## The node sits at its sort point (for the y-sort); its art and collider at its foot.

static var all: Array[Gatherable] = []
const GRID := 512.0                ## the squares (px) they're filed under by their foot, to find those near quickly
static var _grid := {}             ## Vector2i -> Array of Gatherables whose foot is in that square
static var version := 0          ## counts every change in how one looks (felled, regrown, new, gone): the maps redraw

## Played when a tree crashes down, and the log's art (from the miner's settings).
static var fall_sound: AudioStream
static var fall_volume := 0.6
static var log_drop := -1

const LAND_AT := 0.6
const BURST_AT := 0.86
const FALL_END := 1.06

var world: World
var data: Dictionary
var axe := false             ## a tree (chopped) rather than a rock (mined)
var resource := "Stone"
var foot := Vector2.ZERO     ## where it stands, px
var stone := 8               ## how much it holds
var left := 8
var stage := 0               ## how many crumbles it has broken down through
var art: Sprite2D
var body: StaticBody2D
var _whole := -1
var healthy := -1            ## its own (healthy) look
var corrupted := false       ## rotted by the mist: tougher, and less wood in it (Corruption)
const CORRUPT_GLANCE := 0.4  ## of a corrupted tree's swings, the share that glance off
const CORRUPT_WOOD := 0.5    ## of the wood it would give, the share it does
var _scale := Vector2.ONE
var _shake := 0.0
var _fall := -1.0
var _grow := -1.0
var _regrow_at := -1.0
var _landed := false
var _burst := false
var _rest := Vector2.ZERO
# A planted tree growing up (from Unity's TreeGrowth): a sapling (too small to chop, nothing in the way), then a young
# tree giving a little wood, then a mature one giving the full amount, steadily with game time. Felled, it's gone.
const YOUNG_AFTER := 8.0          ## game hours
const MATURE_AFTER := 24.0
const SAPLING_SIZE := 0.25
const YOUNG_SIZE := 0.6
const YOUNG_WOOD := 3
const MATURE_WOOD := 8
var planted_at := -1.0            ## game hours it was planted (-1: not planted)
var _tree_wood := 5


func setup(w: World, d: Dictionary, tree_wood: int) -> void:
	world = w
	data = d
	axe = int(d.tool) == 1
	resource = d.resource
	foot = Vector2(d.x, d.y)
	position = Vector2(d.x, d.sort)
	_tree_wood = tree_wood
	stone = int(d.stone) * (tree_wood if axe else 1)
	left = stone
	_whole = int(d.s)
	healthy = _whole
	_scale = Vector2(d.sx, d.sy)
	art = Sprite2D.new()
	world.show_frame(art, _whole, _scale)
	version += 1
	art.position = foot - position
	_rest = art.position
	# Trees sway (their shader; rocks stand still).
	art.material = world.tree_material() if axe else world.snow_material(0)
	if axe:
		art.set_meta("sway", true)
	add_child(art)
	world.add_occluder(art)
	Culler.still(world, self, foot)   # (whoever's behind it gets their outline; Sera's fades it)
	if d.has("collider"):
		body = StaticBody2D.new()
		body.position = -position
		world._collider_into(body, d.collider)
		add_child(body)
	all.append(self)
	_grid.get_or_add(_square(foot), []).append(self)


func _exit_tree() -> void:
	all.erase(self)
	var here: Array = _grid.get(_square(foot), [])
	here.erase(self)
	version += 1


func depleted() -> bool:
	return left <= 0 or sapling()


## A planted tree's age in game hours (faster with the Tree Growth talent).
func age() -> float:
	if planted_at < 0.0 or world.clock == null:
		return INF
	var growth := 1.0
	if world.player != null and world.player.get("stats") != null:
		growth = CharacterStats.percent(world.player.stats.stat("growthSpeed"))
	return (world.clock.hours - planted_at) * growth


## Still a sapling: too small to chop.
func sapling() -> bool:
	return age() < YOUNG_AFTER


## Game hours until it reaches its next stage (0 once mature).
func hours_to_next() -> float:
	var a := age()
	return YOUNG_AFTER - a if a < YOUNG_AFTER else (MATURE_AFTER - a if a < MATURE_AFTER else 0.0)


# Grows steadily: sapling size up to young size, then up to its full size; choppable (and in the way) once young.
func _grow_up() -> void:
	var a := age()
	var factor := lerpf(SAPLING_SIZE, YOUNG_SIZE, a / YOUNG_AFTER) if a < YOUNG_AFTER else lerpf(YOUNG_SIZE, 1.0, clampf((a - YOUNG_AFTER) / (MATURE_AFTER - YOUNG_AFTER), 0.0, 1.0))
	art.scale = (art.get_meta("full_scale", art.scale) as Vector2) * factor
	var young := a >= YOUNG_AFTER
	if body != null:
		body.process_mode = Node.PROCESS_MODE_INHERIT if young else Node.PROCESS_MODE_DISABLED
	var wood := (MATURE_WOOD if a >= MATURE_AFTER else YOUNG_WOOD) * _tree_wood
	if wood > stone:
		left += wood - stone
		stone = wood


## Stone still in it, counting the smaller rocks it will break into.
func remaining() -> int:
	var total := left
	if left > 0:
		for i in range(stage, (data.crumbles as Array).size()):
			total += int(data.crumbles[i][1])
	return total


## How far [param p] is from its edge (its collider), or its foot without one.
func distance_to(p: Vector2) -> float:
	if body != null and body.get_child_count() > 0:
		var shape := body.get_child(0)
		if shape is CollisionShape2D and shape.shape is CircleShape2D:
			return maxf(0.0, (body.global_position + shape.position).distance_to(p) - (shape.shape as CircleShape2D).radius)
		if shape is CollisionPolygon2D:
			var poly: PackedVector2Array = shape.polygon
			if Geometry2D.is_point_in_polygon(p - body.global_position, poly):
				return 0.0
			var best := INF
			for i in poly.size():
				var q := Geometry2D.get_closest_point_to_segment(p - body.global_position, poly[i], poly[(i + 1) % poly.size()])
				best = minf(best, q.distance_to(p - body.global_position))
			return best
	return foot.distance_to(p)


## The nearest one with something left within [param range] of [param p], or null.
static func _square(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / GRID), floori(p.y / GRID))


## The trees and rocks whose foot may be within [param reach] of [param p] (those in the squares it touches).
static func near(p: Vector2, reach: float) -> Array:
	if not p.is_finite() or not is_finite(reach) or reach > 8.0 * GRID:
		return all   # (nowhere in particular, or far and wide: all of them)
	var out := []
	var a := _square(p - Vector2(reach, reach))
	var b := _square(p + Vector2(reach, reach))
	for x in range(a.x, b.x + 1):
		for y in range(a.y, b.y + 1):
			out.append_array(_grid.get(Vector2i(x, y), []))
	return out


static func nearest(p: Vector2, reach: float) -> Gatherable:
	var best: Gatherable = null
	var best_d := reach
	for g: Gatherable in near(p, reach + 200.0):
		# The cheap distance check first: depleted() asks a planted tree's age, which looks up her growth talent.
		if g.foot.distance_squared_to(p) > (reach + 200.0) * (reach + 200.0) or g.depleted():
			continue
		var d := g.distance_to(p)
		if d < best_d:
			best_d = d
			best = g
	return best


## Where pieces fly out from, above its base.
func chunk_point() -> Vector2:
	var ratio := 1.0
	if stage > 0:
		var now: Dictionary = world.sprites[int(data.crumbles[stage - 1][0])]
		var was: Dictionary = world.sprites[_whole]
		ratio = (float(now.rect[3]) / float(now.ppu)) / maxf(0.01, float(was.rect[3]) / float(was.ppu))
	return foot + Vector2(0, -float(data.chunkHeight) * ratio)


## Standing (not felled or crumbled away).
func standing() -> bool:
	return not depleted() and _fall < 0.0


## Corrupts it (showing [param look]) or heals it.
func set_corrupted(on: bool, look: int) -> void:
	if on and look < 0:
		return
	corrupted = on
	_whole = look if on else healthy
	if stage == 0 and _fall < 0.0 and not depleted():
		world.show_frame(art, _whole, _scale)
		version += 1


## Brings it down at once (attacks took it down): it falls and bursts into logs as if chopped through.
func fell() -> void:
	if depleted() or not axe:
		return
	left = 0
	stage = (data.crumbles as Array).size()
	_topple()


## How tall its art stands, px.
func tree_height() -> float:
	return _height()


## Shaken by a blow that takes nothing from it (Miko's staff on a corrupted tree).
func flinch() -> void:
	_shake = 0.18
	set_process(true)


## One strike: what it gives (0 once it's run out).
func strike() -> int:
	if depleted():
		return 0
	if corrupted and randf() < CORRUPT_GLANCE:
		_shake = 0.1
		set_process(true)
		return 0
	var got := mini(left, randi_range(int(data.perStrike[0]), int(data.perStrike[1])))
	left -= got
	_shake = 0.18
	set_process(true)
	var crumbles: Array = data.crumbles
	if depleted() and stage < crumbles.size():
		# Breaks off into a smaller rock, still standing.
		var next: Array = crumbles[stage]
		stage += 1
		left = int(next[1])
		world.show_frame(art, int(next[0]), _scale)
		version += 1
		_shake = 0.3
		set_process(true)
	elif depleted():
		_topple()
	if corrupted and got > 0:
		got = floori(got * CORRUPT_WOOD + randf())
	return got


# Run out: a rock crumbles to rubble, a tree falls.
func _topple() -> void:
	if body != null:
		body.process_mode = Node.PROCESS_MODE_DISABLED
	if float(data.regrow) > 0.0 and planted_at < 0.0:
		_regrow_at = _now() + float(data.regrow)
		set_process(true)
	if int(data.rubble) >= 0:
		world.show_frame(art, int(data.rubble), _scale)
		version += 1
	else:
		_fall = 0.0
		set_process(true)
		_burst = false
		_landed = false
		if axe and fall_sound != null:
			Sfx.play(self, fall_sound, foot, fall_volume)


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _process(delta: float) -> void:
	var __t := Time.get_ticks_usec()
	_process_timed(delta)
	Perf.add(&"gatherable.process", __t)


func _process_timed(delta: float) -> void:
	if planted_at >= 0.0 and _fall < 0.0 and left > 0 and Engine.get_process_frames() % 30 == 0:
		_grow_up()
	if _shake > 0.0:
		_shake -= delta
		art.position = _rest + Vector2(sin(_now() * 90.0) * 0.03 * world.px * (_shake / 0.18), 0)
		if _shake <= 0.0:
			art.position = _rest
	if _fall >= 0.0:
		_falling(delta)
	if _grow >= 0.0:
		_grow += delta
		var t := clampf(_grow / 1.2, 0.0, 1.0)
		art.modulate.a = t
		var full: Vector2 = art.get_meta("full_scale", art.scale)
		art.scale = full * lerpf(0.6, 1.0, t)
		if t >= 1.0:
			_grow = -1.0
	if _regrow_at > 0.0 and _now() >= _regrow_at:
		regrow()
	# Nothing going on (most of the time, for most of them): it stops being called until something starts again.
	if not _busy():
		set_process(false)


# Shaking from a hit, falling, fading back in, waiting to regrow, or planted and still growing.
func _busy() -> bool:
	return _shake > 0.0 or _fall >= 0.0 or _grow >= 0.0 or _regrow_at > 0.0 		or (planted_at >= 0.0 and _fall < 0.0 and left > 0 and age() < MATURE_AFTER)


# A felled tree drops (faster and faster) until it slams into the ground, bounces once, and bursts into logs as it
# comes back down, fading out.
func _falling(delta: float) -> void:
	_fall += delta
	var angle: float
	if _fall < LAND_AT:
		var t := _fall / LAND_AT
		angle = 85.0 * t * t
	else:
		var b := _fall - LAND_AT
		var lift := 9.0 * sin(PI * b / (BURST_AT - LAND_AT)) if _fall < BURST_AT else 0.0
		angle = 85.0 - lift
		if not _landed and axe:
			_landed = true
			_slam()
	# It falls to the right, about its foot.
	art.rotation_degrees = angle
	if not _burst and _fall >= BURST_AT and axe:
		_burst = true
		_burst_into_logs()
		Puffs.burst(world, _trunk_point(0.55), 1.5)
	art.modulate.a = 1.0 - clampf((_fall - BURST_AT) / (FALL_END - BURST_AT), 0.0, 1.0)
	if _fall >= FALL_END:
		_fall = -1.0
		art.visible = false
		art.rotation = 0.0


func _height() -> float:
	var info: Dictionary = world.sprites[_whole]
	return float(info.rect[3]) * world.px / float(info.ppu) * absf(_scale.y)


# A point along the fallen trunk (it falls to the right): 0 its foot, 1 its top.
func _trunk_point(along: float) -> Vector2:
	return foot + Vector2(along * _height(), -0.2 * world.px)


# Hitting the ground: dust thrown up all along the trunk.
func _slam() -> void:
	var h := _height() / world.px
	var puffs := clampi(roundi(h * 1.5), 3, 7)
	for i in puffs:
		Puffs.burst(world, _trunk_point((i + 0.5) / puffs) + Vector2(0, randf_range(-0.08, 0.08) * world.px), randf_range(0.7, 1.1))


# A felled tree's logs: more the taller it was, flung out from all along the fallen trunk.
func _burst_into_logs() -> void:
	var h := _height() / world.px
	var count := clampi(roundi(h * float(data.logsPerUnit)), int(data.logRange[0]), int(data.logRange[1]))
	if corrupted:
		count = maxi(1, roundi(count * CORRUPT_WOOD))
	var sprite := log_drop if log_drop >= 0 else int(data.chunk)
	for i in count:
		var at := foot + Vector2(randf_range(0.15, 0.95) * _height(), (randf_range(-0.12, 0.12) - 0.25) * world.px)
		Pickup.launch(world, resource, 1, sprite, at, 1.0 if log_drop >= 0 else float(data.chunkScale), randf_range(1.3, 2.1))


## Makes it whole again straight away, fading back in.
func regrow() -> void:
	_regrow_at = -1.0
	left = stone
	stage = 0
	world.show_frame(art, _whole, _scale)
	version += 1
	art.set_meta("full_scale", art.scale)
	art.visible = true
	art.rotation = 0.0
	art.position = _rest
	if body != null:
		body.process_mode = Node.PROCESS_MODE_INHERIT
	_grow = 0.0
	set_process(true)


## Plants a sapling of the tree kind [param kind] (a spot from gather.json) at [param at] (px), [param hours] game
## hours ago; it grows into a tree to chop.
static func plant(w: World, kind: Dictionary, at: Vector2, tree_wood: int, hours: float) -> Gatherable:
	var d := kind.duplicate(true)
	var shift := at - Vector2(float(kind.x), float(kind.y))
	d.x = at.x
	d.y = at.y
	d.sort = float(kind.sort) + shift.y
	d.stone = YOUNG_WOOD
	if d.has("collider"):
		var c: Dictionary = d.collider
		if c.has("c"):
			c.c = [float(c.c[0]) + shift.x, float(c.c[1]) + shift.y]
		if c.has("p"):
			var pts := []
			for i in range(0, c.p.size(), 2):
				pts.append_array([float(c.p[i]) + shift.x, float(c.p[i + 1]) + shift.y])
			c.p = pts
	if randf() < 0.5:
		d.sx = -float(d.sx)
	var full := randf_range(0.9, 1.1)
	d.sx = float(d.sx) * full
	d.sy = float(d.sy) * full
	var g := Gatherable.new()
	w.things.add_child(g)
	g.setup(w, d, tree_wood)
	g.planted_at = hours
	g.set_process(true)
	g.art.set_meta("full_scale", g.art.scale)
	g.left = 0
	g.stone = 0
	g._grow_up()
	w.gatherables.append(g)
	return g
