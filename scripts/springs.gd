class_name Springs
extends Node
## Springs (from Unity's Springs and Pond): now and then a source of clean water wells up in a forest, a small pool on
## open grass among the trees (never by a road, in the village or by other water), and stays a few days before drying
## out. Never two near each other. Round a spring the forest heals and the rot can't take hold (Corruption). Pale
## motes of light rise off the water. Each pool is a fan of water inside a wobbly shore, with a bank wall where the
## shore faces the camera (the same water and bank shaders as the world's ponds).

const POINTS := 72
const WALL_OVERLAP := 0.06       ## units: how far a bank's wall reaches below the water's edge
const DROP := 0.3                ## units: how far the far shore drops to the water
const WOBBLE := 0.22
const WADE := 0.25

static var active: Springs

var world: World
var s: Dictionary                ## farm.json's springs settings
var all: Array = []              ## [{data {x, y, radius, until, seed}, at, shown, drying, nodes, rim, motes, light}]
var _pending: Array = []
var _have_saved := false
var _next_spring := -1.0
var _last_day := -1


func setup(w: World, settings: Dictionary) -> void:
	world = w
	s = settings
	active = self


## The saved springs (Unity's world.forest springs: x, y in cells, radius, until, seed).
func restore(list: Array) -> void:
	_pending = list
	_have_saved = true
	# A saved world with springs keeps to the mornings for more; one with none gets its first soon.
	_next_spring = 0.0 if not list.is_empty() else -1.0


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _hours() -> float:
	return world.clock.hours if world.clock != null else 0.0


## Whether [param at] is close enough to a spring to be healed by it.
static func near(at: Vector2) -> bool:
	if active == null:
		return false
	var r: float = float(active.s.heals) * active.world.px
	for sp in active.all:
		if not sp.drying and sp.at.distance_to(at) <= r:
			return true
	return false


func _process(delta: float) -> void:
	var __t := Time.get_ticks_usec()
	_process_timed(delta)
	Perf.add(&"springs.process", __t)


func _process_timed(delta: float) -> void:
	if world.player == null:
		return
	if not _pending.is_empty():
		for d in _pending:
			_make(d, true)
		_pending = []
	var day: int = world.clock.day() if world.clock != null else 1
	if day != _last_day:
		var first := _last_day < 0
		_last_day = day
		if not first and all.size() < int(s.most) and randf() < float(s.dailyChance):
			_try_well()
	# The very first one soon after starting, so there's one in the world.
	if _next_spring < 0.0:
		_next_spring = _now() + 20.0
	if _next_spring > 0.0 and _now() >= _next_spring and all.is_empty():
		_next_spring = 0.0
		_try_well()
	# Welling up, drying out (out of her sight).
	for i in range(all.size() - 1, -1, -1):
		var sp: Dictionary = all[i]
		if not sp.drying and _hours() >= float(sp.data.until) and world.player.position.distance_to(sp.at) > 16.0 * world.px:
			sp.drying = true
		var want := 0.0 if sp.drying else 1.0
		if not is_equal_approx(sp.shown, want):
			sp.shown = move_toward(sp.shown, want, delta / 6.0)
			_build(sp, maxf(0.2, float(sp.data.radius) * smoothstep(0.15, 1.0, sp.shown)))
			sp.light.energy = 0.5 * sp.shown
			sp.motes.modulate.a = sp.shown
			sp.motes.emitting = sp.shown > 0.05
		if sp.drying and sp.shown <= 0.0:
			_clear(sp)
			all.remove_at(i)


func _clear(sp: Dictionary) -> void:
	for n in sp.nodes:
		if is_instance_valid(n): n.queue_free()
	sp.nodes = []


# Looks for a spot for a spring and makes one there.
func _try_well() -> void:
	for tries in 120:
		var at: Variant = Wilds.find_spot(world, _fits, 40)
		if at == null:
			return
		var cell := world.floors.fractional_cell(at)
		var radius := randf_range(float(s.size[0]), float(s.size[1]))
		if not _room(cell, radius):
			continue
		_make({"x": cell.x, "y": cell.y, "radius": radius, "seed": randi_range(1, 99999),
			"until": _hours() + randf_range(float(s.lasts[0]), float(s.lasts[1])) * 24.0}, false)
		return


# In a clearing in a forest: trees round it, none on it, and no treetop in front (below it on screen) to hide it.
func _fits(at: Vector2) -> bool:
	var px := world.px
	if world.player.position.distance_to(at) < float(s.awayFromPlayer) * px:
		return false
	for sp in all:
		if sp.at.distance_to(at) < float(s.apart) * px:
			return false
	if not Wilds.forest_floor(world, at) or Wilds.trees_near(at, 8.0 * px).size() < 6:
		return false
	for t in Wilds.trees_near(at, 6.0 * px):
		var dd: Vector2 = t - at
		if Vector2(dd.x, dd.y * 2.0).length() < 3.2 * px:
			return false
		if dd.y > 0.0 and dd.y < 4.5 * px and absf(dd.x) < 2.8 * px:
			return false
	return Wilds.open(world, at, 4.0, 0.5)


# Room for the pool: grass all over it and a little round, no water, nothing standing on it.
func _room(centre: Vector2, radius: float) -> bool:
	var reach := ceili(radius + 1.5)
	for x in range(-reach, reach + 1):
		for y in range(-reach, reach + 1):
			if Vector2(x, y).length() > radius + 1.5:
				continue
			var cell := Vector2i(floori(centre.x + x), floori(centre.y + y))
			if not world.floors.in_bounds(cell) or world.floors.get_laid(cell) != "" or world.floors.get_floor(cell) != world.floors.base_floor:
				return false
			var w := world.floors.cell_centre(cell)
			if world.water_depth(w) > 0.01 or not Wilds.open(world, w, 0.0, 0.45):
				return false
	return true


func _make(d: Dictionary, full: bool) -> void:
	var sp := {"data": d, "shown": 1.0 if full else 0.0, "drying": false, "nodes": [], "rim": []}
	sp.at = _world(Vector2(float(d.x), float(d.y)))
	# Pale light off the water, and motes rising.
	var l := PointLight2D.new()
	l.texture = Fires._glow()
	l.color = Color(0.65, 0.95, 1.0)
	l.texture_scale = 2.6 * 2.0 * world.px / float(Fires._glow().get_width())
	l.position = sp.at + Vector2(0, -0.2 * world.px)
	l.energy = 0.5 * sp.shown
	world.add_child(l)
	sp.light = l
	var m := CPUParticles2D.new()
	m.amount = 18
	m.lifetime = 3.0
	m.lifetime_randomness = 0.4
	m.local_coords = false
	m.position = sp.at
	m.texture = Fires._soft_dot()
	m.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = maxf(0.3, float(d.radius) * 0.35) * world.px
	m.scale = Vector2(1.0, 0.5)
	m.direction = Vector2(0, -1)
	m.spread = 6.0
	m.gravity = Vector2.ZERO
	m.initial_velocity_min = 0.25 * world.px
	m.initial_velocity_max = 0.45 * world.px
	m.scale_amount_min = 0.04 * world.px / 64.0 * 2.0
	m.scale_amount_max = 0.09 * world.px / 64.0 * 2.0
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	g.colors = PackedColorArray([Color(0.85, 1, 1, 0), Color(0.9, 1, 0.95, 0.9), Color(1, 1, 0.85, 0)])
	m.color_ramp = g
	m.modulate.a = sp.shown
	m.emitting = sp.shown > 0.05
	m.z_as_relative = false
	m.z_index = 3990
	world.add_child(m)
	sp.motes = m
	sp.nodes = []
	_build(sp, float(d.radius) if full else 0.2)
	all.append(sp)


# Cells (the floor grid, fractional) to world px.
func _world(cells: Vector2) -> Vector2:
	return world.floors.corner(cells)


# The shore, in cells: a circle pushed in and out by smooth noise that wraps round.
func _shape(d: Dictionary, radius: float) -> Array:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.seed = int(d.seed)
	noise.frequency = 1.0
	var centre := Vector2(float(d.x), float(d.y))
	var rim := []
	for i in POINTS:
		var a := i * TAU / POINTS
		var n := noise.get_noise_2d(cos(a) * 1.3, sin(a) * 1.3) * 0.5 + 0.5
		rim.append(centre + Vector2(cos(a), sin(a)) * radius * (1.0 + (n - 0.5) * 2.0 * WOBBLE))
	return rim


# How much of a wall the shore at rim point i is: 1 where it faces the camera, 0 where it's level with the water.
func _wall(rim: Array, centre: Vector2, i: int) -> float:
	var outward: Vector2 = (rim[i] - centre).normalized()
	var dir := _world(rim[i] + outward) - _world(rim[i])
	return smoothstep(0.0, 1.0, inverse_lerp(-0.15, 0.25, (-dir.normalized()).y))  # Unity's y is up


# The water (a fan from the middle: deep there, foamy at the shore), the bank walls, and the shore's edge.
func _build(sp: Dictionary, radius: float) -> void:
	_clear(sp)
	var d: Dictionary = sp.data
	var centre := Vector2(float(d.x), float(d.y))
	var rim := _shape(d, radius)
	var px := world.px
	var sink := func(i: int) -> float: return DROP * _wall(rim, centre, i)
	# Water.
	var v := []
	var uv := []
	var t := []
	var mid := _world(centre) + Vector2(0, DROP * 0.5 * px)
	v.append_array([mid.x, mid.y])
	uv.append_array([0.0, 0.5])
	for i in POINTS:
		var p := _world(rim[i]) + Vector2(0, sink.call(i) * px)
		v.append_array([p.x, p.y])
		uv.append_array([0.0, 1.0])
		t.append_array([0, 1 + i, 1 + (i + 1) % POINTS])
	var water := world._mesh({"name": "Spring", "v": v, "uv": uv, "t": t, "material": "River", "flow": 0.12})
	world.add_ground_layer(water, -9997)
	sp.nodes.append(water)
	# Bank walls where the shore faces the camera.
	var cv := []
	var cuv := []
	var cuv2 := []
	var ct := []
	var along := 0.0
	var prev := -1
	for k in POINTS + 1:
		var i := k % POINTS
		var before := (i + POINTS - 1) % POINTS
		var step: float = (rim[i] as Vector2).distance_to(rim[before]) if k > 0 else 0.0
		@warning_ignore("integer_division")
		var at := cv.size() / 2
		var top := _world(rim[i])
		var sk: float = sink.call(i)
		var bottom := top + Vector2(0, (sk + WALL_OVERLAP if sk > 0.01 else sk) * px)
		cv.append_array([top.x, top.y, bottom.x, bottom.y])
		cuv.append_array([along + step, 0.0, along + step, 1.0])
		cuv2.append_array([0.0, maxf(0.05, sk), 0.0, maxf(0.05, sk)])
		if k > 0 and not (sk < 0.01 and sink.call(before) < 0.01):
			ct.append_array([prev, at, prev + 1, prev + 1, at, at + 1])
		along += step
		prev = at
	if not ct.is_empty():
		var bank := world._mesh({"name": "SpringBank", "v": cv, "uv": cuv, "uv2": cuv2, "t": ct, "material": "Cliff"})
		world.add_ground_layer(bank, -9996)
		sp.nodes.append(bank)
	# The shore: in as far as you can wade.
	var body := StaticBody2D.new()
	var poly := CollisionPolygon2D.new()
	poly.build_mode = CollisionPolygon2D.BUILD_SEGMENTS
	var pts := PackedVector2Array()
	for k in POINTS + 1:
		var p: Vector2 = rim[k % POINTS]
		pts.append(_world(p + (centre - p).normalized() * WADE))
	poly.polygon = pts
	body.add_child(poly)
	world.add_child(body)
	sp.nodes.append(body)
	sp.rim = rim


## The springs, for the save (with the forest, world.forest).
func saved() -> Array:
	return all.filter(func(sp): return not sp.drying).map(func(sp): return sp.data)
