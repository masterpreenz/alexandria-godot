class_name SpellEffects
## What a spell does once cast (redone in Godot from Unity's SpellProjectile, GroundEffect and ImpactRing prefabs, in
## each spell's colour): a projectile flying from the staff along the aim, slanting down to land where it was aimed
## (or bursting sooner on the first enemy in its way, or on whatever it hits); a projectile falling from the sky onto
## the target; or spikes bursting up out of the ground across the area. Each hits everything in its area for the
## spell's damage, raised by the caster's magic and spell damage, and leaves what its element leaves on those it hit
## (StatusEffects: frostbite from ice, a burn from fire); an ice spell with "frozenGround" leaves the ground frozen
## there a few seconds too. Spells cast on oneself: Water Heal (mending the caster and allies round them over a
## moment) and Ice Barrier (a shield of ice on the caster that bursts when it breaks, frostbiting what's near).
## Anyone can cast them: Sera, or a companion with their own stats.


## A spell's damage: its own, raised by the caster's magic (1% a point) and spell damage.
static func damage(spell: Dictionary, stats: CharacterStats) -> float:
	var d := float(spell.damage)
	if stats == null:
		return d
	return d * CharacterStats.percent(stats.stat("magic")) * CharacterStats.percent(stats.stat("spellDamage"))


## [param v] raised by the caster's magic (1% a point): how much a heal mends, how strong a barrier is.
static func by_magic(v: float, stats: CharacterStats) -> float:
	return v if stats == null else v * CharacterStats.percent(stats.stat("magic"))


## Casts [param spell] for [param caster] (null: Sera), whose stats are [param stats]: from [param origin] (the staff,
## or the sky) with [param ground_origin] its feet, at [param target].
static func begin(w: World, spell: Dictionary, stats: CharacterStats, origin: Vector2, ground_origin: Vector2, target: Vector2, caster: Node2D = null) -> void:
	var who: Node2D = caster if caster != null else w.player as Node2D
	var by_player := caster == null or caster == w.player
	match spell.delivery:
		"Directional", "SkyFall":
			var p := Projectile.new()
			p.world = w
			p.spell = spell
			p.amount = damage(spell, stats)
			p.by_player = by_player
			w.add_child(p)
			p.start(origin, ground_origin, target)
		"Ground":
			var g := Spikes.new()
			g.world = w
			g.spell = spell
			g.by_player = by_player
			w.things.add_child(g)
			g.start(target, damage(spell, stats))
		"Self":
			match str(spell.effect):
				"WaterHeal":
					WaterHeal.make(w, spell, stats, who)
				"IceBarrier":
					IceBarrier.make(w, spell, stats, who, by_player)


## Hits everyone on the other side within [param area] of [param at] for [param amount], leaving the spell's element's
## effect (frostbite, a burn) on whoever's still standing, and frozen ground if the spell leaves it.
static func strike(w: World, spell: Dictionary, at: Vector2, area: float, amount: float, by_player: bool) -> int:
	var n := Damageable.hit_around(at, area, amount, Damageable.Team.ENEMY, by_player, func(d: Damageable) -> void:
		StatusEffects.from_spell(d, spell, amount, by_player))
	if float(spell.get("frozenGround", 0.0)) > 0.0:
		FrozenGround.make(w, spell, at, area, amount, by_player)
	return n


static func color(spell: Dictionary) -> Color:
	var c: Array = spell.color
	return Color(c[0], c[1], c[2], 1.0)


## The white at the heart of a spell of colour [param c]: warm for fire, cold for ice and water.
static func core(c: Color) -> Color:
	return Color(0.9, 0.97, 1.0) if c.b > c.r else Color(1.0, 0.95, 0.8)


static func sound(w: World, path: String, at: Vector2, volume: float) -> void:
	if path != "" and ResourceLoader.exists(path):
		Sfx.play(w, Sfx.stream(path), at, volume)


## A glowing ball with a trail, flying or falling; bursting with sparks and a ring where it lands.
class Projectile extends Node2D:
	var world: World
	var spell: Dictionary
	var amount := 0.0
	var by_player := true
	var falling := false
	var origin := Vector2.ZERO
	var target := Vector2.ZERO
	var ground := Vector2.ZERO
	var lift := Vector2.ZERO
	var velocity := Vector2.ZERO
	var travelled := 0.0
	var max_travel := 0.0
	var fall_time := 0.1
	var fall_progress := 0.0
	var trail: CPUParticles2D

	func start(o: Vector2, ground_origin: Vector2, t: Vector2) -> void:
		origin = o
		target = t
		position = o
		z_as_relative = false
		z_index = 4000
		var c := SpellEffects.color(spell)
		var k := float(spell.projectileScale)
		trail = CPUParticles2D.new()
		trail.amount = 60
		trail.lifetime = 0.45
		trail.local_coords = false
		trail.texture = Waterfall._dot(32, 1.0)
		trail.scale_amount_min = 0.5 * k
		trail.scale_amount_max = 0.9 * k
		trail.gravity = Vector2(0, -60)
		trail.initial_velocity_min = 5.0
		trail.initial_velocity_max = 30.0
		trail.spread = 180.0
		var g := Gradient.new()
		g.set_color(0, Color(SpellEffects.core(c), 0.95))
		g.set_color(1, Color(c, 0.0))
		g.add_point(0.3, Color(c, 0.8))
		trail.color_ramp = g
		add_child(trail)
		SpellEffects.sound(world, spell.launchSound, t, spell.soundVolume)
		falling = spell.delivery == "SkyFall"
		if falling:
			fall_time = maxf(o.distance_to(t) / float(spell.projectileSpeed), 0.1)
			return
		ground = ground_origin
		lift = o - ground_origin
		var direction := t - ground_origin
		velocity = (direction.normalized() if direction.length() > 1.0 else Vector2.LEFT) * float(spell.projectileSpeed)
		max_travel = clampf(direction.length(), 0.3 * world.px, float(spell.range))

	func _process(delta: float) -> void:
		var __t := Time.get_ticks_usec()
		_process_timed(delta)
		Perf.add(&"spell_effects.Projectile.process", __t)


	func _process_timed(delta: float) -> void:
		queue_redraw()
		if falling:
			fall_progress = minf(fall_progress + delta / fall_time, 1.0)
			position = origin.lerp(target, fall_progress * fall_progress)  # speeding up as it falls
			if fall_progress >= 1.0:
				_explode(target)
			return
		var step := velocity * delta
		if step.length() > max_travel - travelled:
			step = step.normalized() * (max_travel - travelled)
		# Bursts on whoever is in its way this frame, however fast it's going.
		for d in Damageable.all:
			if d.team != Damageable.Team.ENEMY or not d.alive():
				continue
			var q := Geometry2D.get_closest_point_to_segment(d.global_position, ground, ground + step)
			if d.ground_distance(q) <= 0.15 * world.px:
				_explode(q)
				return
		# Or on what blocks it (a tree, a wall).
		var q2 := PhysicsRayQueryParameters2D.create(ground, ground + step)
		if world.player is CollisionObject2D:
			q2.exclude = [(world.player as CollisionObject2D).get_rid()]
		var hit := world.get_world_2d().direct_space_state.intersect_ray(q2)
		if not hit.is_empty():
			_explode(hit.position)
			return
		ground += step
		travelled += step.length()
		var progress := clampf(travelled / max_travel, 0.0, 1.0) if max_travel > 0.0 else 1.0
		position = ground + lift * (1.0 - progress)
		if travelled >= max_travel - 0.01:
			_explode(ground)

	func _draw() -> void:
		var c := SpellEffects.color(spell)
		var r := 14.0 * float(spell.projectileScale)
		draw_circle(Vector2.ZERO, r * 1.8, Color(c, 0.25))
		if str(spell.element) == "Ice" and not falling:
			# A shard of ice, point first.
			var f := velocity.normalized() if velocity.length() > 1.0 else Vector2.LEFT
			var side := f.orthogonal()
			var tip := f * r * 2.2
			var tail := -f * r * 1.4
			draw_colored_polygon(PackedVector2Array([tip, side * r * 0.75, tail, -side * r * 0.75]), Color(c, 0.95))
			draw_colored_polygon(PackedVector2Array([tip, side * r * 0.3, tail * 0.5]), SpellEffects.core(c))
			return
		draw_circle(Vector2.ZERO, r, Color(c, 0.9))
		draw_circle(Vector2.ZERO, r * 0.5, SpellEffects.core(c))

	func _explode(at: Vector2) -> void:
		SpellEffects.strike(world, spell, at, float(spell.aoeRadius), amount, by_player)
		SpellEffects.sound(world, spell.impactSound, at, spell.soundVolume)
		Burst.make(world, at, float(spell.aoeRadius), SpellEffects.color(spell))
		# The trail finishes on its own.
		trail.emitting = false
		var t := trail
		remove_child(t)
		world.add_child(t)
		t.global_position = position
		t.z_as_relative = false
		t.z_index = 4000
		world.get_tree().create_timer(0.6).timeout.connect(t.queue_free)
		queue_free()


## Sparks flying out over the area, and a ring spreading flat on the ground, fading.
class Burst extends Node2D:
	var radius := 96.0
	var col := Color.WHITE
	var age := 0.0

	static func make(w: World, at: Vector2, r: float, c: Color) -> void:
		var b := Burst.new()
		b.radius = r
		b.col = c
		b.position = at
		b.z_as_relative = false
		b.z_index = 3990
		w.add_child(b)
		var p := CPUParticles2D.new()
		p.one_shot = true
		p.explosiveness = 1.0
		p.amount = clampi(int(40.0 * r / 96.0), 20, 160)
		p.lifetime = 0.7
		p.texture = Waterfall._dot(32, 1.0)
		p.spread = 180.0
		p.initial_velocity_min = r * 1.2
		p.initial_velocity_max = r * 3.0
		p.damping_min = r * 2.5
		p.damping_max = r * 3.5
		p.gravity = Vector2(0, 80)
		p.scale_amount_min = 0.4
		p.scale_amount_max = 0.9
		var g := Gradient.new()
		g.set_color(0, Color(SpellEffects.core(c), 1.0))
		g.set_color(1, Color(c, 0.0))
		g.add_point(0.35, Color(c, 0.9))
		p.color_ramp = g
		p.emitting = true
		b.add_child(p)

	func _process(delta: float) -> void:
		var __t := Time.get_ticks_usec()
		_process_timed(delta)
		Perf.add(&"spell_effects.Burst.process", __t)


	func _process_timed(delta: float) -> void:
		age += delta
		queue_redraw()
		if age > 0.9:
			queue_free()

	func _draw() -> void:
		var t := clampf(age / 0.6, 0.0, 1.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))
		draw_circle(Vector2.ZERO, radius * lerpf(0.3, 1.0, t), Color(col, 0.4 * (1.0 - t)))
		# The flash at its heart, gone quickly.
		var f := clampf(age / 0.22, 0.0, 1.0)
		draw_circle(Vector2.ZERO, radius * lerpf(0.25, 0.75, f), Color(SpellEffects.core(col), 0.6 * (1.0 - f)))
		draw_arc(Vector2.ZERO, radius * lerpf(0.3, 1.05, t), 0.0, TAU, 48, Color(col.lightened(0.3), 0.9 * (1.0 - t)), 4.0, true)


## Spikes bursting up out of the ground across the area (nearer the middle first), holding, and sinking back, with a
## tinted patch spreading under them and lingering a little longer.
class Spikes extends Node2D:
	var world: World
	var spell: Dictionary
	var by_player := true
	var spikes := []   # [offset, delay, size, flip]
	var age := 0.0
	const RISE := 0.12
	const HOLD := 0.9
	const SINK := 0.3

	func start(at: Vector2, amount: float) -> void:
		position = at
		var r := float(spell.aoeRadius)
		var units := r / world.px
		var count := clampi(roundi(PI * units * units * 2.5), 3, 60)
		for i in count:
			var o := Vector2.from_angle(randf() * TAU) * sqrt(randf()) * r
			o.y *= 0.5
			spikes.append([o, o.length() / r * 0.15 + randf() * 0.05, randf_range(0.7, 1.2), randf() < 0.5])
		spikes.sort_custom(func(a, b): return a[0].y < b[0].y)
		SpellEffects.strike(world, spell, at, r, amount, by_player)
		SpellEffects.sound(world, spell.launchSound, at, spell.soundVolume)
		SpellEffects.sound(world, spell.impactSound, at, spell.soundVolume)

	func _process(delta: float) -> void:
		var __t := Time.get_ticks_usec()
		_process_timed(delta)
		Perf.add(&"spell_effects.Spikes.process", __t)


	func _process_timed(delta: float) -> void:
		age += delta
		queue_redraw()
		if age > 2.6:
			queue_free()

	func _draw() -> void:
		var c := SpellEffects.color(spell)
		var r := float(spell.aoeRadius)
		var patch := clampf(age / 0.2, 0.0, 1.0) * (1.0 - clampf((age - 1.4) / 1.2, 0.0, 1.0))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))
		draw_circle(Vector2.ZERO, r, Color(c, 0.35 * patch))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		for s in spikes:
			var t: float = age - s[1]
			var h := 0.0
			if t < 0.0: h = 0.0
			elif t < RISE: h = _ease_out_back(t / RISE)
			elif t < RISE + HOLD: h = 1.0
			else: h = 1.0 - clampf((t - RISE - HOLD) / SINK, 0.0, 1.0)
			if h <= 0.0:
				continue
			var base: Vector2 = s[0]
			var tall: float = 0.55 * world.px * s[2] * h
			var wide: float = 0.12 * world.px * s[2]
			var lean := wide * 0.35 * (-1.0 if s[3] else 1.0)
			var pts := PackedVector2Array([base + Vector2(-wide, 0), base + Vector2(lean, -tall), base + Vector2(wide, 0)])
			draw_colored_polygon(pts, c.darkened(0.15))
			draw_colored_polygon(PackedVector2Array([base + Vector2(-wide * 0.2, 0), base + Vector2(lean, -tall), base + Vector2(wide, 0)]), c.lightened(0.35))

	static func _ease_out_back(x: float) -> float:
		var c1 := 1.70158
		return 1.0 + (c1 + 1.0) * pow(x - 1.0, 3.0) + c1 * pow(x - 1.0, 2.0)


## Ground frozen where an ice spell landed: a pale patch of ice, cracked and glinting, lying flat on the ground a few
## seconds. A monster standing on it is frostbitten harder (slowed more, bitten harder) for as long as it stays, and a
## moment after it steps off.
class FrozenGround extends Node2D:
	const EVERY := 0.25
	const FADE_IN := 0.3
	const FADE_OUT := 0.8

	var world: World
	var radius := 0.0
	var life := 5.0
	var dps := 0.0
	var slow := 60.0
	var linger := 0.75
	var by_player := true
	var age := 0.0
	var _next := 0.0
	var _cracks := []     # [from, to] across the ice (px, before squashing flat)
	var _glints := []     # [where, phase]

	static func make(w: World, spell: Dictionary, at: Vector2, area: float, amount: float, mine: bool) -> FrozenGround:
		var k: Dictionary = StatusEffects.kinds().get("FrozenGround", {})
		var g := FrozenGround.new()
		g.world = w
		g.radius = area * float(k.get("areaShare", 0.85))
		g.life = float(spell.frozenGround)
		g.dps = amount * float(k.get("perSecond", 0.3))
		g.slow = float(k.get("slow", 60.0))
		g.linger = float(k.get("linger", 0.75))
		g.by_player = mine
		g.position = at
		for i in 7:
			var a := randf() * TAU
			var from := Vector2.from_angle(a) * g.radius * randf_range(0.05, 0.3)
			var mid := from + Vector2.from_angle(a + randf_range(-0.5, 0.5)) * g.radius * randf_range(0.25, 0.4)
			var to := mid + Vector2.from_angle(a + randf_range(-0.6, 0.6)) * g.radius * randf_range(0.2, 0.35)
			g._cracks.append([from, mid])
			g._cracks.append([mid, to])
		for i in 9:
			g._glints.append([Vector2.from_angle(randf() * TAU) * sqrt(randf()) * g.radius * 0.85, randf() * TAU])
		g.visibility_layer |= LightMap.UNLIT_LAYER   # (glinting at night too)
		w.add_ground_layer(g, -9978)   # on the ground, under everyone
		return g

	func _process(delta: float) -> void:
		var __t := Time.get_ticks_usec()
		_process_timed(delta)
		Perf.add(&"spell_effects.FrozenGround.process", __t)

	func _process_timed(delta: float) -> void:
		age += delta
		queue_redraw()
		if age >= life:
			queue_free()
			return
		if age >= _next:
			_next = age + EVERY
			for d in Damageable.all:
				if d.team == Damageable.Team.ENEMY and d.alive() and d.ground_distance(position) <= radius:
					StatusEffects.apply(d, "Frostbite", linger, dps, slow, &"Frostbite:ground", by_player)

	func _draw() -> void:
		var shown := minf(clampf(age / FADE_IN, 0.0, 1.0), clampf((life - age) / FADE_OUT, 0.0, 1.0))
		var r := radius * lerpf(0.6, 1.0, clampf(age / FADE_IN, 0.0, 1.0))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))
		draw_circle(Vector2.ZERO, r, Color(0.72, 0.88, 1.0, 0.5 * shown))
		draw_circle(Vector2(-r * 0.2, -r * 0.15), r * 0.55, Color(0.9, 0.97, 1.0, 0.22 * shown))
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 48, Color(0.92, 0.98, 1.0, 0.75 * shown), 3.0, true)
		var k := r / radius
		for c in _cracks:
			draw_line(c[0] * k, c[1] * k, Color(1.0, 1.0, 1.0, 0.6 * shown), 2.0, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		for g in _glints:
			var p: Vector2 = g[0] * k * Vector2(1.0, 0.5)
			var tw := maxf(0.0, sin(age * 4.0 + g[1]))
			if tw > 0.3:
				var s := 7.0 * tw
				var c := Color(1.0, 1.0, 1.0, 0.9 * shown * tw)
				draw_line(p + Vector2(-s, 0), p + Vector2(s, 0), c, 1.5, true)
				draw_line(p + Vector2(0, -s), p + Vector2(0, s), c, 1.5, true)


## Water Heal: a ring of water spreading on the ground round the caster and droplets springing up about them; over a
## moment it mends the caster and everyone on their side near them (Sera, her companions, villagers), a little each
## tick, the numbers rising blue.
class WaterHeal extends Node2D:
	const EVERY := 0.4

	var world: World
	var spell: Dictionary
	var stats: CharacterStats
	var who: Node2D
	var radius := 0.0
	var time := 2.0
	var per_tick := 0.0
	var ticks := 1
	var done := 0
	var age := 0.0
	var _next := 0.0
	var drops: CPUParticles2D

	static func make(w: World, sp: Dictionary, st: CharacterStats, caster: Node2D) -> WaterHeal:
		var h := WaterHeal.new()
		h.world = w
		h.spell = sp
		h.stats = st
		h.who = caster
		h.radius = float(sp.aoeRadius)
		h.time = float(sp.get("healTime", 2.0))
		h.ticks = maxi(1, roundi(h.time / EVERY))
		h.per_tick = SpellEffects.by_magic(float(sp.get("heal", 20.0)), st) / h.ticks
		h.position = caster.global_position if caster != null else Vector2.ZERO
		h.visibility_layer |= LightMap.UNLIT_LAYER   # (bright at night too)
		w.add_ground_layer(h, -9978)
		# Droplets springing up all round and falling back.
		var m := CPUParticles2D.new()
		m.amount = 70
		m.lifetime = 0.9
		m.local_coords = false
		m.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		m.emission_rect_extents = Vector2(h.radius * 0.7, h.radius * 0.35)
		m.direction = Vector2(0, -1)
		m.spread = 18.0
		m.gravity = Vector2(0, 520)
		m.initial_velocity_min = 160.0
		m.initial_velocity_max = 300.0
		m.texture = Waterfall._dot(16, 1.0)
		m.scale_amount_min = 0.8
		m.scale_amount_max = 1.4
		var g := Gradient.new()
		g.set_color(0, Color(0.85, 0.95, 1.0, 0.95))
		g.set_color(1, Color(0.3, 0.6, 1.0, 0.0))
		g.add_point(0.5, Color(0.45, 0.72, 1.0, 0.8))
		m.color_ramp = g
		m.z_as_relative = false
		m.z_index = 3990
		m.position = h.position
		World.keep_lit(m)
		w.add_child(m)
		m.emitting = true
		h.drops = m
		SpellEffects.sound(w, str(sp.impactSound), h.position, float(sp.soundVolume))
		return h

	func _process(delta: float) -> void:
		var __t := Time.get_ticks_usec()
		_process_timed(delta)
		Perf.add(&"spell_effects.WaterHeal.process", __t)

	func _process_timed(delta: float) -> void:
		age += delta
		if who != null and is_instance_valid(who):
			position = who.global_position
		if drops != null:
			drops.position = position
			if age >= time:
				drops.emitting = false
		queue_redraw()
		if done < ticks and age >= _next:
			_next = age + EVERY
			done += 1
			_mend()
		if age >= time + 0.6:
			if drops != null:
				var m := drops
				drops = null
				m.get_tree().create_timer(1.0).timeout.connect(m.queue_free)
			queue_free()

	# One tick: the caster, Sera if she's near, and everyone on her side within reach.
	func _mend() -> void:
		var sera := world.player as Miko
		var mended := {}
		if stats != null:
			_show(stats, who if who != null and is_instance_valid(who) else sera)
			mended[stats] = true
		if sera != null and sera.stats != null and not mended.has(sera.stats) and _near(sera.position):
			_show(sera.stats, sera)
		for a in Damageable.all.duplicate():
			if is_instance_valid(a) and a.team == Damageable.Team.ALLY and a.alive() and a.ground_distance(position) <= radius:
				var b: float = a.hp
				a.heal(per_tick)
				_number(a.hp - b, a.global_position + Vector2(0, -a.height * 0.6))

	func _show(st: CharacterStats, at: Node2D) -> void:
		var before := st.hp
		st.heal(per_tick)
		if at != null:
			_number(st.hp - before, at.global_position + Vector2(0, -0.9 * world.px))

	func _near(p: Vector2) -> bool:
		var d := p - position
		return Vector2(d.x, d.y * 2.0).length() <= radius

	func _number(healed: float, at: Vector2) -> void:
		if healed >= 0.5:
			FloatingText.spawn(world, "+%d" % maxi(1, roundi(healed)), at, Color(0.5, 0.85, 1.0))

	func _draw() -> void:
		var shown := clampf(age / 0.2, 0.0, 1.0) * clampf((time + 0.6 - age) / 0.6, 0.0, 1.0)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))
		draw_circle(Vector2.ZERO, radius, Color(0.35, 0.62, 1.0, 0.18 * shown))
		# Ripples spreading out from the caster, one after another.
		for i in 3:
			var f := fmod(age * 0.9 + i / 3.0, 1.0)
			draw_arc(Vector2.ZERO, radius * f, 0.0, TAU, 48, Color(0.75, 0.9, 1.0, 0.7 * shown * (1.0 - f)), 3.0, true)
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(0.55, 0.8, 1.0, 0.6 * shown), 2.5, true)


## Ice Barrier: a shell of ice round the caster that soaks damage (a shield on their stats, and on what can be hit of
## them if they have it), glittering shards turning round them and cracks showing as it wears. Broken, it bursts:
## shards flying out, hurting and frostbiting the monsters round them. Its time up first, it just melts away. Cast
## again, the old one melts and a new one takes its place.
class IceBarrier extends Node2D:
	static var _on := {}   # caster -> their barrier

	var world: World
	var spell: Dictionary
	var stats: CharacterStats
	var who: Node2D
	var hit: Damageable
	var by_player := true
	var full := 0.0
	var left := 0.0
	var life := 15.0
	var age := 0.0
	var _melting := -1.0
	var _shell: Sprite2D
	var _cracks := []

	static func make(w: World, sp: Dictionary, st: CharacterStats, caster: Node2D, mine: bool) -> IceBarrier:
		if caster == null:
			return null
		var old: Variant = _on.get(caster)
		if old != null and is_instance_valid(old):
			(old as IceBarrier)._melt()
		var b := IceBarrier.new()
		b.world = w
		b.spell = sp
		b.stats = st
		b.who = caster
		b.by_player = mine
		b.hit = caster.get("hit") as Damageable if "hit" in caster else null
		b.full = SpellEffects.by_magic(float(sp.get("shield", 40.0)), st) * (CharacterStats.percent(st.stat("shieldPower")) if st != null else 1.0)
		b.left = b.full
		b.life = float(sp.get("shieldTime", 15.0))
		if st != null:
			st.set_shield(b, b.full)
		if b.hit != null:
			b.hit.set_shield(b, b.full)
		b.z_as_relative = false
		b.z_index = 3985
		b.position = caster.global_position
		b._shell = Sprite2D.new()
		b._shell.texture = ShieldBubble.dome()
		var d := float(b._shell.texture.get_width())
		b._shell.position = Vector2(0, -0.62 * w.px)
		b._shell.scale = Vector2(1.25 * w.px / d, 1.55 * w.px / d)
		b.add_child(b._shell)
		for i in 6:
			var a := randf() * TAU
			b._cracks.append([Vector2.from_angle(a) * 0.15 * w.px, Vector2.from_angle(a + randf_range(-0.4, 0.4)) * 0.55 * w.px])
		World.keep_lit(b)
		w.add_child(b)
		_on[caster] = b
		SpellEffects.sound(w, str(sp.launchSound), b.position, float(sp.soundVolume))
		return b

	func _process(delta: float) -> void:
		var __t := Time.get_ticks_usec()
		_process_timed(delta)
		Perf.add(&"spell_effects.IceBarrier.process", __t)

	func _process_timed(delta: float) -> void:
		age += delta
		queue_redraw()
		if _melting >= 0.0:
			_melting += delta
			modulate.a = 1.0 - clampf(_melting / 0.4, 0.0, 1.0)
			if _melting >= 0.4:
				queue_free()
			return
		if who == null or not is_instance_valid(who):
			_melt()
			return
		position = who.global_position
		# What's left of it: the least of what its shields hold (kept the same on both).
		var now_left := left
		if stats != null:
			now_left = minf(now_left, stats.shield_from(self))
		if hit != null and is_instance_valid(hit):
			now_left = minf(now_left, hit.shield_from(self))
		if now_left <= 0.01:
			_burst()
			return
		if now_left < left:
			left = now_left
			if stats != null:
				stats.set_shield(self, left)
			if hit != null and is_instance_valid(hit):
				hit.set_shield(self, left)
		if age >= life:
			_melt()

	# Broken: it bursts, hurting and frostbiting the monsters round the caster.
	func _burst() -> void:
		left = 0.0
		var r := float(spell.aoeRadius)
		var c := SpellEffects.color(spell)
		SpellEffects.strike(world, spell, position, r, SpellEffects.damage(spell, stats), by_player)
		SpellEffects.Burst.make(world, position, r, c)
		SpellEffects.sound(world, str(spell.impactSound), position, float(spell.soundVolume))
		FloatingText.spawn(world, "Barrier shattered", position + Vector2(0, -1.6 * world.px), Color(0.7, 0.9, 1.0), 18)
		# Shards of it flying out.
		var p := CPUParticles2D.new()
		p.one_shot = true
		p.explosiveness = 1.0
		p.amount = 36
		p.lifetime = 0.6
		p.texture = Waterfall._dot(16, 0.3)
		p.spread = 180.0
		p.initial_velocity_min = r * 1.5
		p.initial_velocity_max = r * 3.0
		p.damping_min = r * 2.0
		p.damping_max = r * 3.0
		p.scale_amount_min = 0.5
		p.scale_amount_max = 1.1
		p.color = Color(0.85, 0.95, 1.0)
		p.position = position + Vector2(0, -0.6 * world.px)
		p.z_as_relative = false
		p.z_index = 3990
		p.emitting = true
		world.add_child(p)
		world.get_tree().create_timer(1.0).timeout.connect(p.queue_free)
		_melt()

	# Gone (broken, its time up, or a new one cast): its shields taken away, fading.
	func _melt() -> void:
		if _melting >= 0.0:
			return
		_melting = 0.0
		if stats != null and is_instance_valid(stats):
			stats.set_shield(self, 0.0)
		if hit != null and is_instance_valid(hit):
			hit.set_shield(self, 0.0)
		if _on.get(who) == self:
			_on.erase(who)

	func _exit_tree() -> void:
		_melt()

	func _draw() -> void:
		var c := SpellEffects.color(spell)
		var worn := 1.0 - clampf(left / maxf(full, 0.01), 0.0, 1.0)
		var fading := clampf((life - age) / 1.5, 0.3, 1.0)
		_shell.modulate = Color(c.lightened(0.2), 0.9 * fading * (0.85 + 0.15 * sin(age * 3.0)))
		var mid := Vector2(0, -0.62 * world.px)
		# Cracks across it, more as it wears.
		var shown := roundi(worn * _cracks.size())
		for i in shown:
			var cr: Array = _cracks[i]
			draw_line(mid + cr[0], mid + cr[1], Color(1, 1, 1, 0.7 * fading), 2.0, true)
		# Shards turning round them, on the ground's ellipse.
		var rx := 0.62 * world.px
		for i in 6:
			var a := age * 1.4 + i * TAU / 6.0
			var at := Vector2(cos(a) * rx, -0.35 * world.px + sin(a) * rx * 0.3)
			var h := 0.22 * world.px
			var front := sin(a) > 0.0
			var col := Color(0.9, 0.97, 1.0, (0.95 if front else 0.45) * fading)
			draw_colored_polygon(PackedVector2Array([at + Vector2(0, -h), at + Vector2(h * 0.28, 0), at + Vector2(0, h * 0.35), at + Vector2(-h * 0.28, 0)]), col)
			draw_colored_polygon(PackedVector2Array([at + Vector2(0, -h), at + Vector2(h * 0.28, 0), at + Vector2(0, h * 0.35)]), Color(c, 0.8 * fading))
