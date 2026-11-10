class_name SpellEffects
## What a spell does once cast (redone in Godot from Unity's SpellProjectile, GroundEffect and ImpactRing prefabs, in
## each spell's colour): a projectile flying from the staff along the aim, slanting down to land where it was aimed
## (or bursting sooner on the first enemy in its way, or on whatever it hits); a projectile falling from the sky onto
## the target; or spikes bursting up out of the ground across the area. Each hits everything in its area for the
## spell's damage, raised by the caster's magic and spell damage.


## A spell's damage: its own, raised by the caster's magic (1% a point) and spell damage.
static func damage(spell: Dictionary, stats: CharacterStats) -> float:
	var d := float(spell.damage)
	if stats == null:
		return d
	return d * CharacterStats.percent(stats.stat("magic")) * CharacterStats.percent(stats.stat("spellDamage"))


static func begin(w: World, spell: Dictionary, stats: CharacterStats, origin: Vector2, ground_origin: Vector2, target: Vector2) -> void:
	match spell.delivery:
		"Directional", "SkyFall":
			var p := Projectile.new()
			p.world = w
			p.spell = spell
			p.amount = damage(spell, stats)
			w.add_child(p)
			p.start(origin, ground_origin, target)
		"Ground":
			var g := Spikes.new()
			g.world = w
			g.spell = spell
			w.things.add_child(g)
			g.start(target, damage(spell, stats))


static func color(spell: Dictionary) -> Color:
	var c: Array = spell.color
	return Color(c[0], c[1], c[2], 1.0)


static func sound(w: World, path: String, at: Vector2, volume: float) -> void:
	if path != "" and ResourceLoader.exists(path):
		Sfx.play(w, Sfx.stream(path), at, volume)


## A glowing ball with a trail, flying or falling; bursting with sparks and a ring where it lands.
class Projectile extends Node2D:
	var world: World
	var spell: Dictionary
	var amount := 0.0
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
		g.set_color(0, Color(1.0, 0.95, 0.8, 0.95))
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
		draw_circle(Vector2.ZERO, r, Color(c, 0.9))
		draw_circle(Vector2.ZERO, r * 0.5, Color(1, 0.97, 0.85, 1.0))

	func _explode(at: Vector2) -> void:
		Damageable.hit_around(at, float(spell.aoeRadius), amount, Damageable.Team.ENEMY, true)
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
		g.set_color(0, Color(1, 0.95, 0.8, 1))
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
		draw_circle(Vector2.ZERO, radius * lerpf(0.25, 0.75, f), Color(1.0, 0.95, 0.8, 0.6 * (1.0 - f)))
		draw_arc(Vector2.ZERO, radius * lerpf(0.3, 1.05, t), 0.0, TAU, 48, Color(col.lightened(0.3), 0.9 * (1.0 - t)), 4.0, true)


## Spikes bursting up out of the ground across the area (nearer the middle first), holding, and sinking back, with a
## tinted patch spreading under them and lingering a little longer.
class Spikes extends Node2D:
	var world: World
	var spell: Dictionary
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
		Damageable.hit_around(at, r, amount, Damageable.Team.ENEMY, true)
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
