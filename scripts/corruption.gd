class_name Corruption
extends Node
## The mist rotting the forest (from Unity's Corruption). In the mist, trees turn corrupted: dark and twisted, tougher
## to chop (some swings glance off) and half the wood. At the start a share of the forest in the mist is already gone,
## in patches (more in strong mist); then every game hour the rot creeps (faster in strong mist, faster beside other
## rotten trees), never on cleared ground, by a spring or near the village; on cleared ground, and faster by a
## spring, rotten trees heal. Corrupted trees near Miko can be fought (they glow faintly and have HP): brought down,
## they fall like a felled tree. Healthy forest (few rotten trees) is where the wildlife lives. Which trees are rotten
## is saved (world.forest), with the springs.

static var active: Corruption

const GLOW_REACH := 9.0           ## units: rotten trees this near her glow

var world: World
var s: Dictionary                 ## farm.json's corruption settings
var rotten := {}                  ## healthy sprite id -> corrupted sprite id
var corrupted: Array = []         ## the rotten trees (Gatherables)
var armed := {}                   ## Gatherable -> [Damageable, PointLight2D]
var seeded := false
var _pending: Variant = null      ## the save's rotten trees, put back once the trees are in
var _seed_at := 0.0
var _last_hour := -1.0
var _next_arm := 0.0


func setup(w: World, settings: Dictionary) -> void:
	world = w
	s = settings
	active = self
	for t in s.get("twins", []):
		rotten[int(t.healthy)] = int(t.corrupted)
	_seed_at = _now() + 3.0


## The saved forest (Unity's world.forest): which trees are rotten (their feet, in units), and the springs.
func from_json(json: String) -> void:
	var d: Variant = JSON.parse_string(json)
	if not d is Dictionary:
		return
	_pending = d.get("corrupted", [])
	if Springs.active != null:
		Springs.active.restore(d.get("springs", []))


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


## Whether the forest is laid out (wildlife can settle).
static func ready() -> bool:
	return active == null or active.seeded


func _trees() -> Array:
	return Gatherable.all.filter(func(g): return g.axe)


## How many rotten trees stand within [param radius] px of [param at].
func corrupted_near(at: Vector2, radius: float) -> int:
	var n := 0
	for t in corrupted:
		if is_instance_valid(t) and t.foot.distance_squared_to(at) <= radius * radius:
			n += 1
	return n


func _process(_delta: float) -> void:
	if world.player == null:
		return
	if _pending != null and _now() >= 0.5:
		_apply(_pending)
		_pending = null
		seeded = true
	if not seeded and _now() >= _seed_at:
		_seed()
		seeded = true
	if not seeded:
		return
	if world.clock != null:
		var hour := floorf(world.clock.hours)
		if _last_hour < 0.0:
			_last_hour = hour
		# An hour (or a few, after sleeping) gone by.
		var i := 0
		while i < 6 and _last_hour < hour:
			_last_hour += 1.0
			_tick()
			i += 1
		_last_hour = maxf(_last_hour, hour)
	if _now() >= _next_arm:
		_next_arm = _now() + 1.0
		_arm()
	_glow()


# The forest as it is at the start: patches gone in the mist, more in strong mist.
func _seed() -> void:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.seed = 371
	noise.frequency = 1.0 / float(s.patchSize)
	for t in _trees():
		var tier := world.mist.tier_at(t.foot)
		if tier == Mist.Tier.CLEAR:
			continue
		var share := float(s.startStrong) if tier == Mist.Tier.STRONG else float(s.startNormal)
		# Patchy: whole stands gone or whole stands spared, a few odd ones either way.
		var u: Vector2 = t.foot / world.px
		var n := (noise.get_noise_2d(u.x, u.y) * 0.5 + 0.5) * 0.85 + _hash(u) * 0.15
		if n < share:
			_turn(t, true, false)


static func _hash(at: Vector2) -> float:
	var h := sin(at.x * 12.9898 + at.y * 78.233) * 43758.5453
	return h - floorf(h)


# An hour of the forest: rot creeping in the mist, healing where it's cleared or by a spring.
func _tick() -> void:
	for t in _trees():
		var at: Vector2 = t.foot
		var tier := world.mist.tier_at(at)
		var spring := Springs.near(at)
		if t.corrupted:
			var heal := float(s.healSpring) if spring else (float(s.healClear) if tier == Mist.Tier.CLEAR else 0.0)
			if heal > 0.0 and randf() < heal:
				_turn(t, false, true)
			continue
		if tier == Mist.Tier.CLEAR or spring or world.village.contains(at, 2.0):
			continue
		var chance := float(s.rotStrong) if tier == Mist.Tier.STRONG else float(s.rotNormal)
		chance += minf(float(s.spreadMost), corrupted_near(at, float(s.spreadReach) * world.px) * float(s.spreadEach))
		if randf() < chance:
			_turn(t, true, true)


# Corrupts or heals a tree; seen happen, with a burst of sparks.
func _turn(t: Gatherable, rot: bool, show: bool) -> void:
	if rot:
		if not rotten.has(t.healthy):
			return
		t.set_corrupted(true, rotten[t.healthy])
		if not corrupted.has(t):
			corrupted.append(t)
	else:
		t.set_corrupted(false, -1)
		corrupted.erase(t)
		_disarm(t)
	if show and t.standing():
		var mid: Vector2 = t.foot + Vector2(0, -t.tree_height() * 0.45)
		if rot:
			_burst(mid, Color(0.85, 0.5, 1.0), Color(0.5, 0.2, 0.8))
		else:
			_burst(mid, Color(0.75, 1.0, 0.6), Color(1.0, 0.95, 0.6))


func _burst(at: Vector2, a: Color, b: Color) -> void:
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 24
	p.lifetime = 0.7
	p.lifetime_randomness = 0.5
	p.position = at
	p.texture = Fires._soft_dot()
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.12 * world.px
	p.spread = 180.0
	p.initial_velocity_min = 1.2 * world.px
	p.initial_velocity_max = 2.6 * world.px
	p.gravity = Vector2(0, 0.6 * 9.8 * world.px)
	p.scale_amount_min = 0.05 * world.px / 32.0
	p.scale_amount_max = 0.12 * world.px / 32.0
	var g := Gradient.new()
	g.set_color(0, a)
	g.set_color(1, Color(b, 0.0))
	p.color_ramp = g
	p.z_as_relative = false
	p.z_index = 3990
	p.emitting = true
	world.add_child(p)
	world.get_tree().create_timer(1.2).timeout.connect(p.queue_free)


# The rotten trees near Miko can be hit, and glow faintly; the rest are left plain (there are hundreds).
func _arm() -> void:
	var at: Vector2 = world.player.position
	var r := float(s.hitReach) * world.px
	for t in corrupted:
		if is_instance_valid(t) and t.standing() and t.foot.distance_to(at) <= r and not armed.has(t):
			armed[t] = _make_armed(t)
	for t in armed.keys():
		var a: Array = armed[t]
		var keep: bool = is_instance_valid(t) and t.corrupted and t.standing() and is_instance_valid(a[0]) and t.foot.distance_to(at) <= r * 1.14
		if not keep:
			_disarm(t)


func _make_armed(t: Gatherable) -> Array:
	var height := t.tree_height()
	var hit := Damageable.new()
	hit.name = "Rot"
	hit.position = t.foot
	world.add_child(hit)
	var strong := world.mist.tier_at(t.foot) == Mist.Tier.STRONG
	hit.setup(world, Damageable.Team.ENEMY, float(s.treeHp) * (1.5 if strong else 1.0), 0.45 * world.px, maxf(world.px, height * 0.5))
	hit.died.connect(func():
		armed.erase(t)
		if is_instance_valid(t):
			t.fell())
	# The glowing veins light the ground a little.
	var l := PointLight2D.new()
	l.texture = Fires._glow()
	l.color = Color(0.78, 0.4, 1.0)
	l.texture_scale = 1.6 * 2.0 * world.px / float(Fires._glow().get_width())
	l.position = t.foot + Vector2(0, -height * 0.3)
	world.add_child(l)
	return [hit, l]


func _disarm(t: Gatherable) -> void:
	if not armed.has(t):
		return
	for n in armed[t]:
		if is_instance_valid(n):
			n.queue_free()
	armed.erase(t)


# Their glow, made stronger as the night darkens (as the fires').
func _glow() -> void:
	var night := 1.0
	var daylight := get_tree().current_scene.get_node_or_null("Daylight") as CanvasModulate
	if daylight != null:
		night = clampf(maxf(daylight.color.r, maxf(daylight.color.g, daylight.color.b)), 0.2, 1.0)
	for a in armed.values():
		if is_instance_valid(a[1]):
			a[1].energy = 0.35 * 0.7 / sqrt(night)
			# Only the nearer ones glow (a light each for a whole wood would wash it out, and cost).
			a[1].visible = a[1].position.distance_to(world.player.position) < GLOW_REACH * world.px


# Puts a saved forest back: just these trees rotten (each matched to the tree standing within 0.2 units).
func _apply(list: Array) -> void:
	for t in corrupted.duplicate():
		if is_instance_valid(t):
			_turn(t, false, false)
	corrupted.clear()
	var grid := {}
	for t in _trees():
		var k := Vector2i(roundi(t.foot.x / world.px * 4.0), roundi(-t.foot.y / world.px * 4.0))
		grid[k] = t
	for sv in list:
		var at := Vector2(float(sv.x), -float(sv.y)) * world.px
		var k := Vector2i(roundi(float(sv.x) * 4.0), roundi(float(sv.y) * 4.0))
		var found: Gatherable = null
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				var t: Gatherable = grid.get(k + Vector2i(dx, dy))
				if found == null and t != null and t.foot.distance_to(at) < 0.2 * world.px:
					found = t
		if found != null:
			_turn(found, true, false)


## Which trees are rotten and the springs, for the save (Unity's world.forest).
func to_json() -> String:
	var list := []
	for t in corrupted:
		if is_instance_valid(t):
			list.append({"x": t.foot.x / world.px, "y": -t.foot.y / world.px})
	return JSON.stringify({"corrupted": list, "springs": Springs.active.saved() if Springs.active != null else []})
