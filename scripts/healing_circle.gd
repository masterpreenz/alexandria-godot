class_name HealingCircle
extends Node2D
## A healing shikigami's circle (from Unity's HealingCircle): laid flat on the ground where its summoner stood, it
## fades in growing, turns slowly and glows, motes rising off it, and every tick heals its summoner and their allies
## standing in it; then it fades away. With Lasting Heal, the summoner leaving it (or it fading round them) keeps
## mending a while (HP Regen). With Searing Circle the monsters standing in it are seared each tick (raised by the
## summoner's magic), and with Purifying Light set burning too.

const FADE_IN := 0.25
const FADE_OUT := 0.45
const SPIN := 40.0
const LASTING := 5.0             ## seconds Lasting Heal's regen lasts after leaving a circle

static var _lasting_until := {}  ## CharacterStats -> when their Lasting Heal ends
static var live: Array[HealingCircle] = []   ## every circle on the ground now

var from: Shikigami
var art: Sprite2D
var motes: CPUParticles2D
var radius := 0.0
var life := 3.0
var tick := 0.5
var tint := Color.WHITE
var age := 0.0
var next_tick := 0.0
var _k := 1.0
var _owner_in := false


static func spawn(sk: Shikigami, at: Vector2) -> HealingCircle:
	var w := sk.world
	var c := HealingCircle.new()
	c.from = sk
	c.radius = float(sk.s.circleRadius) * w.px * CharacterStats.percent(sk.owner_stats.stat("circleSize") if sk.owner_stats != null else 0.0)
	c.life = float(sk.s.circleTime) * CharacterStats.percent(sk.owner_stats.stat("healDuration") if sk.owner_stats != null else 0.0)
	c.tick = maxf(0.1, float(sk.s.circleTick))
	c.tint = Shikigami._color(sk.s.circleTint)
	c.position = at
	c.art = Sprite2D.new()
	var id := int(sk.s.circleSprite)
	c.art.texture = w._texture(w.sprites[id].tex)
	var info: Dictionary = w.sprites[id]
	c.art.region_enabled = true
	c.art.region_rect = Rect2(info.rect[0], info.rect[1], info.rect[2], info.rect[3])
	c.art.modulate = Color(c.tint, 0.0)
	c._k = c.radius / (info.rect[2] * 0.5)
	c.add_child(c.art)
	# Motes rising off it, all across it.
	var m := CPUParticles2D.new()
	m.amount = clampi(int(60.0 * float(sk.s.circleRadius)), 30, 160)
	m.lifetime = 1.0
	m.local_coords = false
	m.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = c.radius * 0.95
	m.scale = Vector2(1.0, 0.5)  # flat on the 2:1 ground
	m.direction = Vector2(0, -1)
	m.spread = 12.0
	m.gravity = Vector2.ZERO
	m.initial_velocity_min = 50.0
	m.initial_velocity_max = 110.0
	m.texture = Waterfall._dot(16, 1.0)
	m.scale_amount_min = 0.8
	m.scale_amount_max = 1.4
	var g := Gradient.new()
	g.set_color(0, Color(lerpf(c.tint.r, 1.0, 0.2), c.tint.g, lerpf(c.tint.b, 1.0, 0.2), 0.9))
	g.set_color(1, Color(c.tint, 0.0))
	m.color_ramp = g
	c.motes = m
	w.add_ground_layer(c, -9979)  # on the ground, under everyone
	# The motes rise in front of whoever stands in it.
	m.position = at
	m.z_as_relative = false
	m.z_index = 3990
	w.add_child(m)
	return c


func _enter_tree() -> void:
	live.append(self)


func _exit_tree() -> void:
	live.erase(self)


## Whether [param p] stands in one of the circles laid for [param st] (whose shikigami laid it).
static func covers(st: CharacterStats, p: Vector2) -> bool:
	for c in live:
		if is_instance_valid(c) and is_instance_valid(c.from) and c.from.owner_stats == st and c.age < c.life:
			var d := p - c.position
			if Vector2(d.x, d.y * 2.0).length() <= c.radius:
				return true
	return false


func _process(delta: float) -> void:
	var __t := Time.get_ticks_usec()
	_process_timed(delta)
	Perf.add(&"healing_circle.process", __t)


func _process_timed(delta: float) -> void:
	age += delta
	_watch_owner()
	if age >= life:
		if _owner_in:
			_lasting_heal()
		_free_motes()
		queue_free()
		return
	if motes != null and age >= life - FADE_OUT and motes.emitting:
		motes.emitting = false
	art.rotation -= deg_to_rad(SPIN) * delta
	var shown := minf(clampf(age / FADE_IN, 0.0, 1.0), clampf((life - age) / FADE_OUT, 0.0, 1.0))
	var grow := lerpf(0.7, 1.0, smoothstep(0.0, 1.0, clampf(age / FADE_IN, 0.0, 1.0)))
	# Turning flat on the ground: spin the art, then squash the whole thing to the 2:1 ground.
	scale = Vector2(_k, _k * 0.5) * grow
	art.modulate = Color(tint, tint.a * shown * (0.8 + 0.2 * sin(age * 6.0)))
	if age >= next_tick and age < life - FADE_OUT * 0.5:
		next_tick += tick
		if is_instance_valid(from):
			from.heal_around(position, radius)
			_sear()


# Searing Circle: the monsters standing in it are hurt (a bite each tick, raised by the summoner's magic); with
# Purifying Light they're set burning too, the burn going on after they step out.
func _sear() -> void:
	var st := from.owner_stats
	var dps := st.stat("circleSear") if st != null else 0.0
	if dps <= 0.0:
		return
	var bite := SpellEffects.by_magic(dps * tick, st)
	var burn := st.stat("circleBurn") > 0.0
	var k: Dictionary = StatusEffects.kinds().get("Burn", {})
	for d in Damageable.all.duplicate():
		if is_instance_valid(d) and d.team == Damageable.Team.ENEMY and d.alive() and d.ground_distance(position) <= radius:
			d.wear(bite, true, Color(1.0, 0.62, 0.3))
			if burn and d.alive() and not k.is_empty():
				StatusEffects.apply(d, "Burn", float(k.seconds) * CharacterStats.percent(st.stat("burnTime")), SpellEffects.by_magic(dps, st) * 0.5 * CharacterStats.percent(st.stat("burnDamage")), 0.0, &"Burn", true)


# The summoner stepping out of it: Lasting Heal starts.
func _watch_owner() -> void:
	if not is_instance_valid(from) or not is_instance_valid(from.owner_node):
		return
	var d: Vector2 = from.owner_node.position - position
	var inside := Vector2(d.x, d.y * 2.0).length() <= radius and age < life
	if _owner_in and not inside:
		_lasting_heal()
	_owner_in = inside


func _lasting_heal() -> void:
	var st := from.owner_stats if is_instance_valid(from) else null
	if st == null:
		return
	var regen := st.stat("lastingHeal")
	if regen <= 0.0:
		return
	var until := Time.get_ticks_msec() / 1000.0 + LASTING
	_lasting_until[st] = until
	st.set_buff("lastingHeal", {"hpRegen": regen})
	FloatingText.spawn(from.world, "Lasting Heal", from.owner_node.position + Vector2(0, -1.5 * from.world.px), Color(0.55, 1.0, 0.6))
	(Engine.get_main_loop() as SceneTree).create_timer(LASTING).timeout.connect(func():
		if is_instance_valid(st) and float(_lasting_until.get(st, 0.0)) <= Time.get_ticks_msec() / 1000.0 + 0.05:
			st.set_buff("lastingHeal", null))


func _free_motes() -> void:
	if motes != null and is_instance_valid(motes):
		motes.emitting = false
		var m := motes
		m.get_tree().create_timer(1.2).timeout.connect(m.queue_free)
		motes = null
