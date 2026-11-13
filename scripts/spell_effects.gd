class_name SpellEffects
## What a spell does once cast (redone in Godot from Unity's SpellProjectile, GroundEffect and ImpactRing prefabs, in
## each spell's colour): a projectile flying from the staff along the aim, slanting down to land where it was aimed
## (or bursting sooner on the first enemy in its way, or on whatever it hits); a projectile falling from the sky onto
## the target; or spikes bursting up out of the ground across the area. Each hits everything in its area for the
## spell's damage, raised by the caster's magic and spell damage, and leaves what its element leaves on those it hit
## (StatusEffects: frostbite from ice, a burn from fire); an ice spell with "frozenGround" leaves the ground frozen
## there a few seconds too, and Cold Snap now and then freezes what ice hits solid. Miyu's ice and water: Ice Shard
## (a fast shard, two with Twin Shard), Healing Blanket (one ally wrapped in water and frost a few seconds, mended
## all the while), Frost Armor (a shell of ice on everyone on her side near her, each bursting when it breaks), Ice
## Blast (ice bursting up out of the ground where she aims: the user's animation) and Blizzard (shards falling from
## the sky over an area a few seconds, each shattering where it lands). Anyone can cast them: Sera, or a companion
## with their own stats.


## A spell's damage: its own, raised by the caster's magic (1% a point) and spell damage.
static func damage(spell: Dictionary, stats: CharacterStats) -> float:
	var d := float(spell.damage)
	if stats == null:
		return d
	return d * CharacterStats.percent(stats.stat("magic")) * CharacterStats.percent(stats.stat("spellDamage"))


## [param v] raised by the caster's magic (1% a point): how much a heal mends, how strong a barrier is.
static func by_magic(v: float, stats: CharacterStats) -> float:
	return v if stats == null else v * CharacterStats.percent(stats.stat("magic"))


const SHOWER_GAP := 0.55          ## seconds between the meteors of a Meteor Shower
const TWIN_GAP := 0.12            ## seconds between an Ice Shard and its twin


## [param spell] as the caster's talents shape it ([param stats]): a meteor's damage and area (Skyfall's ranks, Wide
## Crater), how long and how hard a fire spell's burn goes on (Scorch), how hard ice's frostbite bites and how often it
## freezes solid (Frost Bite, Cold Snap); and whatever the spell's "tune" names: the stat that raises its damage,
## area, time, healing, shield strength, frostbite, shards, extra shots, a blanket shared and its frost, frozen ground
## (Miyu's talents).
static func tuned(spell: Dictionary, stats: CharacterStats) -> Dictionary:
	if stats == null:
		return spell
	var t := stats.total()
	var out := spell.duplicate()
	if str(spell.get("delivery", "")) == "SkyFall":
		out.damage = float(spell.damage) * CharacterStats.percent(float(t.get("meteorDamage", 0.0)))
		out.aoeRadius = float(spell.aoeRadius) * CharacterStats.percent(float(t.get("meteorArea", 0.0)))
	if str(spell.get("element", "")) == "Fire":
		out["statusTime"] = CharacterStats.percent(float(t.get("burnTime", 0.0)))
		out["statusBite"] = CharacterStats.percent(float(t.get("burnDamage", 0.0)))
	if str(spell.get("element", "")) == "Ice":
		out["statusBite"] = CharacterStats.percent(float(t.get("frostbiteDamage", 0.0)))
		out["coldSnap"] = float(t.get("coldSnap", 0.0))
	var tune: Dictionary = spell.get("tune", {})
	if tune.is_empty():
		return out
	out.damage = float(spell.damage) * _pct(t, tune, "damage")
	out.aoeRadius = float(spell.aoeRadius) * _pct(t, tune, "area")
	for f in ["healTime", "shieldTime", "stormTime"]:
		if spell.has(f):
			out[f] = float(spell[f]) * _pct(t, tune, "time")
	if spell.has("heal"):
		out.heal = float(spell.heal) * _pct(t, tune, "heal")
	if spell.has("shield"):
		out.shield = float(spell.shield) * _pct(t, tune, "strength")
	out["statusBite"] = float(out.get("statusBite", 1.0)) * _pct(t, tune, "status")
	out["shards"] = int(spell.get("shards", 0)) + int(_flat(t, tune, "count") + 0.001)
	out["extra"] = int(_flat(t, tune, "extra") + 0.001)
	out["share"] = _flat(t, tune, "share")
	out["frost"] = _flat(t, tune, "frost")
	out["frozenGround"] = float(spell.get("frozenGround", 0.0)) + _flat(t, tune, "frozen")
	if _flat(t, tune, "rime") > 0.0:
		out["noStatus"] = false
	return out


# The stat a spell's tune names for [param key], as a multiplier (and as it is).
static func _pct(t: Dictionary, tune: Dictionary, key: String) -> float:
	return CharacterStats.percent(_flat(t, tune, key))


static func _flat(t: Dictionary, tune: Dictionary, key: String) -> float:
	return float(t.get(str(tune.get(key, "")), 0.0)) if tune.has(key) else 0.0


## [param spell]'s cooldown for a caster with [param stats]: shortened by cooldown reduction (at most 60%), a meteor's
## by Short Fuse, and any spell's by the stat its tune names for it (Quick Freeze: Ice Blast).
static func cooldown(spell: Dictionary, stats: CharacterStats) -> float:
	var cd := float(spell.get("cooldown", 0.0))
	if stats == null:
		return cd
	cd *= 1.0 - clampf(stats.stat("cooldownReduction"), 0.0, 60.0) / 100.0
	if str(spell.get("delivery", "")) == "SkyFall":
		cd *= 1.0 - clampf(stats.stat("meteorCooldown"), 0.0, 60.0) / 100.0
	var by := str((spell.get("tune", {}) as Dictionary).get("cooldown", ""))
	if by != "":
		cd *= 1.0 - clampf(stats.stat(by), 0.0, 60.0) / 100.0
	return cd


## Everyone on Sera's side within [param reach] of [param at] on the ground: whoever's played, and each companion
## with her (their body and their stats), as [[body, stats]].
static func party_near(w: World, at: Vector2, reach: float) -> Array:
	var out := []
	var lead := w.player as Miko
	if lead != null and lead.stats != null and _ground_gap(lead.position, at) <= reach:
		out.append([lead, lead.stats])
	if Party.active == null:
		return out
	for v in Villager.all:
		if not is_instance_valid(v) or v.hit == null or not v.hit.alive() or not Party.active.has_member(v.person):
			continue
		if _ground_gap(v.position, at) <= reach:
			var st := Companions.stats_for(v.person)
			if st != null:
				out.append([v, st])
	return out


# How far apart two spots are on the ground (its depth counts double: the ground is drawn at half height).
static func _ground_gap(a: Vector2, b: Vector2) -> float:
	var d := a - b
	return Vector2(d.x, d.y * 2.0).length()


## Casts [param raw] for [param caster] (null: Sera), whose stats are [param stats]: from [param origin] (the staff,
## or the sky) with [param ground_origin] its feet, at [param target]. With Meteor Shower, more meteors follow the
## first, a moment apart, close by.
static func begin(w: World, raw: Dictionary, stats: CharacterStats, origin: Vector2, ground_origin: Vector2, target: Vector2, caster: Node2D = null) -> void:
	var spell := tuned(raw, stats)
	var who: Node2D = caster if caster != null else w.player as Node2D
	var by_player := caster == null or caster == w.player
	match spell.delivery:
		"Directional", "SkyFall":
			var amount := damage(spell, stats)
			_launch(w, spell, amount, by_player, origin, ground_origin, target)
			# Twin Shard: another, a moment after, a hair to the side.
			for i in int(spell.get("extra", 0)):
				var aim := ground_origin + (target - ground_origin).rotated(deg_to_rad(4.0 * (1.0 if i % 2 == 0 else -1.0)))
				w.get_tree().create_timer(TWIN_GAP * (i + 1)).timeout.connect(func():
					if is_instance_valid(w):
						_launch(w, spell, amount, by_player, origin, ground_origin, aim))
			var more := int(stats.stat("meteorShower") + 0.001) if stats != null and spell.delivery == "SkyFall" else 0
			for i in more:
				var off := Vector2.from_angle(randf() * TAU) * float(spell.aoeRadius) * randf_range(0.5, 0.9)
				off.y *= 0.5
				w.get_tree().create_timer(SHOWER_GAP * (i + 1)).timeout.connect(func():
					if is_instance_valid(w):
						_launch(w, spell, amount, by_player, origin + off, ground_origin + off, target + off))
		"Ground":
			match str(spell.effect):
				"IceBlast":
					IceBlastArea.make(w, spell, target, damage(spell, stats), by_player)
				"Blizzard":
					Blizzard.make(w, spell, target, damage(spell, stats), by_player)
				"Unmade":
					pass   # (Glacial Spikes, Ice Pillar: not made yet)
				_:
					var g := Spikes.new()
					g.world = w
					g.spell = spell
					g.by_player = by_player
					w.things.add_child(g)
					g.start(target, damage(spell, stats))
		"Ally":
			WaterBlanket.cast(w, spell, stats, who, target, by_player)
		"Self":
			match str(spell.effect):
				"HealingBlanket":
					WaterBlanket.cast(w, spell, stats, who, who.global_position, by_player)
				"FrostArmor":
					FrostArmor.cast(w, spell, stats, who, by_player)


static func _launch(w: World, spell: Dictionary, amount: float, by_player: bool, origin: Vector2, ground_origin: Vector2, target: Vector2) -> void:
	var p := Projectile.new()
	p.world = w
	p.spell = spell
	p.amount = amount
	p.by_player = by_player
	w.add_child(p)
	p.start(origin, ground_origin, target)


## Hits everyone on the other side within [param area] of [param at] for [param amount], leaving the spell's element's
## effect (frostbite, a burn) on whoever's still standing (not a Blizzard's shards, but with Rime), now and then
## freezing them solid (Cold Snap), and frozen ground if the spell leaves it.
static func strike(w: World, spell: Dictionary, at: Vector2, area: float, amount: float, by_player: bool) -> int:
	var snap := float(spell.get("coldSnap", 0.0))
	var quiet := bool(spell.get("noStatus", false))
	var n := Damageable.hit_around(at, area, amount, Damageable.Team.ENEMY, by_player, func(d: Damageable) -> void:
		if not quiet:
			StatusEffects.from_spell(d, spell, amount, by_player)
		if snap > 0.0 and randf() < snap / 100.0:
			StatusEffects.freeze(d, by_player))
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


## [param spell]'s impact sound at [param at]; one that comes thick and fast (soundCap: Ice Shard's, a Blizzard's
## shards) is kept to that many playing at once, a moment apart, shared by everything playing the same sound.
static func impact_sound(w: World, spell: Dictionary, at: Vector2) -> void:
	var path := str(spell.get("impactSound", ""))
	if path == "" or not ResourceLoader.exists(path):
		return
	var cap := int(spell.get("soundCap", 0))
	if cap > 0:
		Sfx.play_capped(w, Sfx.stream(path), at, float(spell.soundVolume), 0.06, path, cap, 0.08)
	else:
		Sfx.play(w, Sfx.stream(path), at, float(spell.soundVolume))


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
		SpellEffects.impact_sound(world, spell, at)
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


## Ground frozen where an ice spell landed: a sheet of ice lying flat on the ground a few seconds, its edge uneven
## (lobed, wobbling), see-through enough that the ground shows faintly, a frosty rim, glossy streaks shimmering slowly
## across it, a few thin cracks; it spreads out quickly and melts back from its edge at the end. A monster standing on it is frostbitten harder (slowed more, bitten harder) for as long as it stays, and a
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
	var _edge := []       # how far out the edge lies all round, as a share of the radius
	var _streaks := []    # [middle, half length, phase] of the glossy streaks
	const EDGE_POINTS := 48

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
		for i in 5:
			g._glints.append([Vector2.from_angle(randf() * TAU) * sqrt(randf()) * g.radius * 0.75, randf() * TAU])
		# Its edge: a few broad lobes and smaller wobbles, a little jitter, smoothed.
		var lobes := randi_range(3, 5)
		var p1 := randf() * TAU
		var p2 := randf() * TAU
		var raw := []
		for i in EDGE_POINTS:
			var t := TAU * i / EDGE_POINTS
			raw.append(0.86 + 0.09 * sin(lobes * t + p1) + 0.05 * sin((lobes + 4) * t + p2) + randf_range(-0.04, 0.04))
		for i in EDGE_POINTS:
			g._edge.append((float(raw[(i - 1 + EDGE_POINTS) % EDGE_POINTS]) + 2.0 * float(raw[i]) + float(raw[(i + 1) % EDGE_POINTS])) / 4.0)
		for i in 3:
			g._streaks.append([Vector2(randf_range(-0.4, 0.3), randf_range(-0.5, 0.3)) * g.radius, g.radius * randf_range(0.18, 0.32), randf() * TAU])
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

	# The sheet's outline at [param k] of its size, and pulled in by [param inset] (px), flat (before squashing).
	func _outline(k: float, inset := 0.0) -> PackedVector2Array:
		var out := PackedVector2Array()
		for i in EDGE_POINTS:
			out.append(Vector2.from_angle(TAU * i / EDGE_POINTS) * maxf(0.0, radius * float(_edge[i]) * k - inset))
		return out

	func _draw() -> void:
		var shown := minf(clampf(age / FADE_IN, 0.0, 1.0), clampf((life - age) / FADE_OUT, 0.0, 1.0))
		# Spreading out as it forms, melting back from its edge as it goes.
		var k := lerpf(0.65, 1.0, clampf(age / FADE_IN, 0.0, 1.0)) * lerpf(0.82, 1.0, clampf((life - age) / FADE_OUT, 0.0, 1.0))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))
		var sheet := _outline(k)
		draw_colored_polygon(sheet, Color(0.76, 0.89, 1.0, 0.3 * shown))
		draw_colored_polygon(_outline(k * 0.72), Color(0.9, 0.96, 1.0, 0.1 * shown))
		var rim := sheet.duplicate()
		rim.append(sheet[0])
		draw_polyline(rim, Color(0.93, 0.98, 1.0, 0.6 * shown), 3.0, true)
		var inner := _outline(k, 7.0)
		inner.append(inner[0])
		draw_polyline(inner, Color(0.85, 0.94, 1.0, 0.25 * shown), 1.5, true)
		for c in _cracks:
			draw_line(c[0] * k, c[1] * k, Color(1.0, 1.0, 1.0, 0.35 * shown), 1.5, true)
		# Glossy streaks, catching the light now and then.
		for st in _streaks:
			var gl := 0.5 + 0.5 * sin(age * 1.3 + float(st[2]))
			var m: Vector2 = st[0] * k
			var dir := Vector2(1.0, -0.55).normalized() * float(st[1]) * k
			draw_line(m - dir, m + dir, Color(1.0, 1.0, 1.0, (0.12 + 0.28 * gl) * shown), 5.0, true)
			draw_line(m - dir * 0.6 + Vector2(0, 9), m + dir * 0.6 + Vector2(0, 9), Color(1.0, 1.0, 1.0, (0.06 + 0.16 * gl) * shown), 3.0, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		for g in _glints:
			var p: Vector2 = g[0] * k * Vector2(1.0, 0.5)
			var tw := maxf(0.0, sin(age * 2.0 + g[1]))
			if tw > 0.5:
				var sz := 5.0 * tw
				var c := Color(1.0, 1.0, 1.0, 0.7 * shown * tw)
				draw_line(p + Vector2(-sz, 0), p + Vector2(sz, 0), c, 1.5, true)
				draw_line(p + Vector2(0, -sz), p + Vector2(0, sz), c, 1.5, true)


## Healing Blanket: one of the caster's side (whoever's nearest where it's aimed, else the caster) wrapped a few seconds
## in a cool blanket of water and frost: their body shines a soft icy blue, pulsing slowly, frost motes drifting up
## round them, and they're mended a little every moment (the numbers rising blue now and then, the shine brightening
## as they do). Nothing else is touched: no ground, no monsters. Cast on them again, it starts afresh; another can be
## wrapped meanwhile. Cold Comfort: monsters the wrapped one strikes are frostbitten. Shared Warmth: the most hurt
## ally near them is wrapped too, more weakly.
class WaterBlanket extends Node2D:
	const EVERY := 0.5
	const SHOW_EVERY := 3             ## mends between the numbers shown
	const FADE := 0.6
	static var _on := {}              # wearer -> their blanket
	static var mended := 0.0          ## all blankets have mended so far (the scenarios read it)

	var world: World
	var spell: Dictionary
	var wearer: Node2D
	var wear_stats: CharacterStats
	var hit: Damageable
	var by_player := true
	var per_tick := 0.0
	var time := 8.0
	var frost := 0.0                  ## Cold Comfort's bite a second on monsters they strike (0: none)
	var age := 0.0
	var healed := 0.0                 ## all this one's mended
	var _next := 0.0
	var _ticks := 0
	var _shown := 0.0
	var _pulse := 0.0
	var _motes: CPUParticles2D

	## Wraps whoever of the caster's side is nearest [param spot] (within the spell's pickReach), else the caster; with
	## Shared Warmth, the most hurt ally near them too. The one wrapped first.
	static func cast(w: World, sp: Dictionary, st: CharacterStats, caster: Node2D, spot: Vector2, mine: bool) -> WaterBlanket:
		var pick: Array = []
		var best := INF
		for pair in SpellEffects.party_near(w, spot, float(sp.get("pickReach", 160.0))):
			var gap := SpellEffects._ground_gap((pair[0] as Node2D).global_position, spot)
			if gap < best:
				best = gap
				pick = pair
		if pick.is_empty():
			if caster == null:
				return null
			pick = [caster, st]
		var b := put_on(w, sp, st, pick[0], pick[1], 1.0, mine)
		var share := float(sp.get("share", 0.0))
		if share > 0.0:
			var other: Array = []
			var low := 1.0
			for pair in SpellEffects.party_near(w, (pick[0] as Node2D).global_position, float(sp.get("shareReach", 320.0))):
				if pair[0] == pick[0]:
					continue
				var f := share_of_hp(pair[0], pair[1])
				if f < low:
					low = f
					other = pair
			if not other.is_empty():
				put_on(w, sp, st, other[0], other[1], share / 100.0, mine)
		return b

	## A blanket on [param who] (whose stats are [param wst]) at [param k] of its strength, cast by one with [param st];
	## on them already, it starts afresh.
	static func put_on(w: World, sp: Dictionary, st: CharacterStats, who: Node2D, wst: CharacterStats, k: float, mine: bool) -> WaterBlanket:
		if who == null:
			return null
		var per := SpellEffects.by_magic(float(sp.get("heal", 6.0)), st) * EVERY * k
		var b := of(who)
		if b != null:
			b.age = minf(b.age, FADE)
			b.time = float(sp.get("healTime", 8.0))
			b.per_tick = maxf(b.per_tick, per)
			b.frost = maxf(b.frost, float(sp.get("frost", 0.0)) * SpellEffects.by_magic(float(sp.get("frostBite", 2.0)), st))
			return b
		b = WaterBlanket.new()
		b.world = w
		b.spell = sp
		b.wearer = who
		b.wear_stats = wst
		b.hit = who.get("hit") as Damageable if "hit" in who else null
		b.by_player = mine
		b.per_tick = per
		b.time = float(sp.get("healTime", 8.0))
		b.frost = float(sp.get("frost", 0.0)) * SpellEffects.by_magic(float(sp.get("frostBite", 2.0)), st)
		b.z_index = 1
		b.material = CanvasItemMaterial.new()
		(b.material as CanvasItemMaterial).blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		who.add_child(b)   # (lit as their body is: a shine on it, not a lamp at night)
		var m := CPUParticles2D.new()
		m.amount = 26
		m.lifetime = 1.3
		m.local_coords = false
		m.texture = Waterfall._dot(16, 1.0)
		m.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		m.emission_rect_extents = Vector2(0.22 * w.px, 0.35 * w.px)
		m.position = Vector2(0, -0.55 * w.px)
		m.direction = Vector2(0, -1)
		m.spread = 30.0
		m.gravity = Vector2.ZERO
		m.initial_velocity_min = 14.0
		m.initial_velocity_max = 40.0
		m.scale_amount_min = 0.45
		m.scale_amount_max = 1.0
		var g := Gradient.new()
		g.set_color(0, Color(1.0, 1.0, 1.0, 0.0))
		g.set_color(1, Color(0.6, 0.85, 1.0, 0.0))
		g.add_point(0.25, Color(0.92, 0.98, 1.0, 0.95))
		g.add_point(0.7, Color(0.65, 0.88, 1.0, 0.6))
		m.color_ramp = g
		World.keep_lit(m)
		b.add_child(m)
		m.emitting = true
		b._motes = m
		_on[who] = b
		SpellEffects.sound(w, str(sp.get("impactSound", "")), who.global_position, float(sp.get("soundVolume", 0.6)))
		return b

	## [param who]'s blanket while it's on, else null.
	static func of(who: Node2D) -> WaterBlanket:
		var b: Variant = _on.get(who)
		return b as WaterBlanket if b != null and is_instance_valid(b) and (b as WaterBlanket).age < (b as WaterBlanket).time else null

	## Whether [param who] is wrapped now.
	static func on(who: Node2D) -> bool:
		return of(who) != null

	## How much of their HP [param who] (with [param st]) has now, as a share.
	static func share_of_hp(who: Node2D, st: CharacterStats) -> float:
		var h: Damageable = who.get("hit") as Damageable if "hit" in who else null
		if h != null and is_instance_valid(h):
			return h.hp / maxf(1.0, h.max_hp)
		return st.hp / maxf(1.0, st.stat("maxHp"))

	## Cold Comfort: [param attacker] just struck [param foe]; wrapped, the cold bites it.
	static func struck(attacker: Node2D, foe: Damageable) -> void:
		var b := of(attacker)
		if b == null or b.frost <= 0.0 or foe == null or not is_instance_valid(foe) or not foe.alive():
			return
		var k: Dictionary = StatusEffects.kinds().get("Frostbite", {})
		StatusEffects.apply(foe, "Frostbite", float(k.get("seconds", 4.0)), b.frost, float(k.get("slow", 35.0)), &"Frostbite", b.by_player)

	func _process(delta: float) -> void:
		var __t := Time.get_ticks_usec()
		_process_timed(delta)
		Perf.add(&"spell_effects.WaterBlanket.process", __t)

	func _process_timed(delta: float) -> void:
		age += delta
		_pulse = maxf(0.0, _pulse - delta * 2.5)
		queue_redraw()
		if age < time and age >= _next:
			_next = age + EVERY
			_mend()
		if age >= time and _motes != null:
			_motes.emitting = false
		if age >= time + FADE:
			if _on.get(wearer) == self:
				_on.erase(wearer)
			queue_free()

	func _mend() -> void:
		var got := 0.0
		if hit != null and is_instance_valid(hit):
			if not hit.alive():
				return
			var b := hit.hp
			hit.heal(per_tick)
			got = hit.hp - b
		elif wear_stats != null and is_instance_valid(wear_stats):
			var b2 := wear_stats.hp
			wear_stats.heal(per_tick)
			got = wear_stats.hp - b2
		healed += got
		mended += got
		_shown += got
		_ticks += 1
		if _ticks % SHOW_EVERY == 0 and _shown >= 0.5:
			FloatingText.spawn(world, "+%d" % maxi(1, roundi(_shown)), wearer.global_position + Vector2(0, -1.0 * world.px), Color(0.6, 0.88, 1.0))
			_shown = 0.0
			_pulse = 1.0

	# The shine over their body: a soft pale blue glow hugging it, pulsing slowly (brighter as it mends), and a few
	# glints of frost twinkling on it.
	func _draw() -> void:
		var shown := clampf(age / FADE, 0.0, 1.0) * clampf((time + FADE - age) / FADE, 0.0, 1.0)
		var beat := 0.5 + 0.5 * sin(age * 2.4)
		var a := (0.3 + 0.12 * beat + 0.25 * _pulse) * shown
		var px := world.px
		draw_set_transform(Vector2(0, -0.55 * px), 0.0, Vector2(0.42, 1.0))
		for i in 4:
			var f := 1.0 - i * 0.2
			draw_circle(Vector2.ZERO, 0.5 * px * f, Color(0.5, 0.78, 1.0, a * 0.4))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		for i in 5:
			var ph := age * 1.7 + i * 1.9
			var tw := maxf(0.0, sin(ph))
			if tw < 0.4:
				continue
			var at := Vector2(sin(i * 2.3) * 0.18 * px, -(0.2 + 0.13 * i) * px)
			var sz := 6.0 * tw
			var c := Color(0.85, 0.95, 1.0, 0.8 * tw * shown)
			draw_line(at + Vector2(-sz, 0), at + Vector2(sz, 0), c, 1.5, true)
			draw_line(at + Vector2(0, -sz), at + Vector2(0, sz), c, 1.5, true)


## Frost Armor: a shell of ice round everyone on the caster's side near them (whoever's played, the companions, the
## caster) that soaks damage (a shield on their stats, and on what can be hit of them if they have it), glittering
## shards turning round them and cracks showing as it wears. Broken, it bursts: shards flying out, hurting and
## frostbiting the monsters round them. Its time up first, it just melts away. Cast again, the old ones melt and new
## ones take their place.
class FrostArmor extends Node2D:
	static var _on := {}   # wearer -> their armour
	static var bursts := 0 ## shells burst so far (the scenarios read it)

	var world: World
	var spell: Dictionary
	var stats: CharacterStats       ## the caster's (how hard the burst hits)
	var wear_stats: CharacterStats  ## the wearer's (the shield's on them)
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

	## Armour on everyone on [param caster]'s side within the spell's reach of them (the caster too). The ones put on.
	static func cast(w: World, sp: Dictionary, st: CharacterStats, caster: Node2D, mine: bool) -> Array:
		var out := []
		if caster == null:
			return out
		var nearby := SpellEffects.party_near(w, caster.global_position, float(sp.get("reach", 0.0)))
		if not nearby.any(func(pair): return pair[0] == caster):
			nearby.append([caster, st])
		for pair in nearby:
			out.append(make(w, sp, st, pair[0], pair[1], mine))
		return out

	## Whether [param wearer] has armour on now.
	static func on(wearer: Node2D) -> bool:
		var a: Variant = _on.get(wearer)
		return a != null and is_instance_valid(a) and (a as FrostArmor)._melting < 0.0

	## A shell on [param wearer] (whose stats are [param wst]), cast by one with [param st].
	static func make(w: World, sp: Dictionary, st: CharacterStats, wearer: Node2D, wst: CharacterStats, mine: bool) -> FrostArmor:
		if wearer == null:
			return null
		var old: Variant = _on.get(wearer)
		if old != null and is_instance_valid(old):
			(old as FrostArmor)._melt()
		var b := FrostArmor.new()
		b.world = w
		b.spell = sp
		b.stats = st
		b.wear_stats = wst
		b.who = wearer
		b.by_player = mine
		b.hit = wearer.get("hit") as Damageable if "hit" in wearer else null
		b.full = SpellEffects.by_magic(float(sp.get("shield", 40.0)), st) * (CharacterStats.percent(st.stat("shieldPower")) if st != null else 1.0)
		b.left = b.full
		b.life = float(sp.get("shieldTime", 15.0))
		if wst != null:
			wst.set_shield(b, b.full)
		if b.hit != null:
			b.hit.set_shield(b, b.full)
		b.z_as_relative = false
		b.z_index = 3985
		b.position = wearer.global_position
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
		_on[wearer] = b
		SpellEffects.sound(w, str(sp.launchSound), b.position, float(sp.soundVolume))
		return b

	func _process(delta: float) -> void:
		var __t := Time.get_ticks_usec()
		_process_timed(delta)
		Perf.add(&"spell_effects.FrostArmor.process", __t)

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
		if wear_stats != null and is_instance_valid(wear_stats):
			now_left = minf(now_left, wear_stats.shield_from(self))
		if hit != null and is_instance_valid(hit):
			now_left = minf(now_left, hit.shield_from(self))
		if now_left <= 0.01:
			_burst()
			return
		if now_left < left:
			left = now_left
			if wear_stats != null and is_instance_valid(wear_stats):
				wear_stats.set_shield(self, left)
			if hit != null and is_instance_valid(hit):
				hit.set_shield(self, left)
		if age >= life:
			_melt()

	# Broken: it bursts, hurting and frostbiting the monsters round the wearer.
	func _burst() -> void:
		left = 0.0
		bursts += 1
		var r := float(spell.aoeRadius)
		var c := SpellEffects.color(spell)
		SpellEffects.strike(world, spell, position, r, SpellEffects.damage(spell, stats), by_player)
		SpellEffects.Burst.make(world, position, r, c)
		SpellEffects.sound(world, str(spell.impactSound), position, float(spell.soundVolume))
		FloatingText.spawn(world, "Frost Armor shattered", position + Vector2(0, -1.6 * world.px), Color(0.7, 0.9, 1.0), 18)
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
		if wear_stats != null and is_instance_valid(wear_stats):
			wear_stats.set_shield(self, 0.0)
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
		var rx := 0.5 * world.px
		for i in 6:
			var a := age * 1.4 + i * TAU / 6.0
			var at := Vector2(cos(a) * rx, -0.35 * world.px + sin(a) * rx * 0.3)
			var h := 0.22 * world.px
			var front := sin(a) > 0.0
			var col := Color(0.9, 0.97, 1.0, (0.8 if front else 0.3) * fading)
			draw_colored_polygon(PackedVector2Array([at + Vector2(0, -h), at + Vector2(h * 0.28, 0), at + Vector2(0, h * 0.35), at + Vector2(-h * 0.28, 0)]), col)
			draw_colored_polygon(PackedVector2Array([at + Vector2(0, -h), at + Vector2(h * 0.28, 0), at + Vector2(0, h * 0.35)]), Color(c, 0.8 * fading))


## Ice Blast: the user's animation (vfx/ice_blast: a glint, a ring on the ground, a burst of ice spikes up out of it
## that shatter, frosted cracks fading) at the spot aimed at, sized so its ring is the spell's area; its sound
## (the user's too) comes in on the eruption (soundAfter), and the blast lands as the spikes break out of the ground
## (landsAfter), hurting and frostbiting everything in the area, and with Frozen Ground leaving it frozen there.
class IceBlastArea extends Node2D:
	const SCENE := "res://vfx/ice_blast/ice_blast.tscn"
	const RING := 0.69                ## the animation's frosted ring at its widest, as a share of its frame's width
	static var blasts := 0            ## blasts landed so far (the scenarios read it)
	static var hits := 0              ## monsters they've hit

	var world: World
	var spell: Dictionary
	var amount := 0.0
	var by_player := true
	var age := 0.0
	var lands := 0.57
	var sound_at := 0.43
	var _sounded := false
	var last := 3.6                   ## seconds the animation runs
	var _landed := false

	static func make(w: World, sp: Dictionary, at: Vector2, dmg: float, mine: bool) -> IceBlastArea:
		var b := IceBlastArea.new()
		b.world = w
		b.spell = sp
		b.amount = dmg
		b.by_player = mine
		b.lands = float(sp.get("landsAfter", 0.57))
		b.sound_at = float(sp.get("soundAfter", 0.0))
		b.position = at
		var r := float(sp.aoeRadius)
		if ResourceLoader.exists(SCENE):
			var anim := (load(SCENE) as PackedScene).instantiate() as Node2D
			var frames := (anim as AnimatedSprite2D).sprite_frames if anim is AnimatedSprite2D else null
			var wide := 256.0
			if frames != null and frames.has_animation(&"default") and frames.get_frame_count(&"default") > 0:
				wide = float(frames.get_frame_texture(&"default", 0).get_width())
				b.last = frames.get_frame_count(&"default") / maxf(1.0, frames.get_animation_speed(&"default")) + 0.1
			anim.scale = Vector2.ONE * (2.0 * r / (wide * RING))
			World.keep_lit(anim)
			b.add_child(anim)
		World.keep_lit(b)
		w.things.add_child(b)
		return b

	func _process(delta: float) -> void:
		var __t := Time.get_ticks_usec()
		_process_timed(delta)
		Perf.add(&"spell_effects.IceBlastArea.process", __t)

	func _process_timed(delta: float) -> void:
		age += delta
		if not _sounded and age >= sound_at:
			_sounded = true
			SpellEffects.sound(world, str(spell.impactSound), position, float(spell.soundVolume))
		if not _landed and age >= lands:
			_landed = true
			blasts += 1
			hits += SpellEffects.strike(world, spell, position, float(spell.aoeRadius), amount, by_player)
			if get_child_count() == 0:
				SpellEffects.Burst.make(world, position, float(spell.aoeRadius), SpellEffects.color(spell))
		if age >= last:
			queue_free()


## Blizzard: over the area, for a few seconds, shards of ice fall slanting out of the sky one after another (snow
## drifting down with them), each with its shadow growing under it; landing, each shatters in a small burst, hurting
## what's round it (frostbiting too, with Rime).
class Blizzard extends Node2D:
	const FALL := 0.45                ## seconds a shard takes to fall
	const HIGH := 560.0               ## how far up it falls from
	const SLANT := Vector2(-0.32, -1.0)
	static var landed := 0            ## shards landed so far (the scenarios read it)
	static var hits := 0              ## monsters they've hit

	var world: World
	var spell: Dictionary
	var amount := 0.0
	var by_player := true
	var radius := 256.0
	var time := 4.0
	var shard_r := 72.0
	var age := 0.0
	var _falls := []                  # [where it lands (from the middle), when it starts falling, landed]
	var _snow: CPUParticles2D

	static func make(w: World, sp: Dictionary, at: Vector2, dmg: float, mine: bool) -> Blizzard:
		var b := Blizzard.new()
		b.world = w
		b.spell = sp
		b.amount = dmg
		b.by_player = mine
		b.radius = float(sp.aoeRadius)
		b.time = float(sp.get("stormTime", 4.0))
		b.shard_r = float(sp.get("shardRadius", 72.0))
		var n := maxi(1, int(sp.get("shards", 12)))
		for i in n:
			var o := Vector2.from_angle(randf() * TAU) * sqrt(randf()) * b.radius
			o.y *= 0.5
			b._falls.append([o, (float(i) + randf() * 0.8) * maxf(0.1, b.time - FALL) / float(n), false])
		b.position = at
		b.z_as_relative = false
		b.z_index = 4000
		var m := CPUParticles2D.new()
		m.amount = 70
		m.lifetime = 1.1
		m.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		m.emission_rect_extents = Vector2(b.radius, b.radius * 0.3)
		m.position = Vector2(0.2 * HIGH, -0.55 * HIGH)
		m.direction = Vector2(-0.3, 1.0)
		m.spread = 8.0
		m.gravity = Vector2.ZERO
		m.initial_velocity_min = 380.0
		m.initial_velocity_max = 520.0
		m.texture = Waterfall._dot(16, 1.0)
		m.scale_amount_min = 0.4
		m.scale_amount_max = 0.9
		m.color = Color(0.9, 0.97, 1.0, 0.8)
		b.add_child(m)
		m.emitting = true
		b._snow = m
		World.keep_lit(b)
		w.add_child(b)
		SpellEffects.sound(w, str(sp.launchSound), at, float(sp.soundVolume))
		return b

	func _process(delta: float) -> void:
		var __t := Time.get_ticks_usec()
		_process_timed(delta)
		Perf.add(&"spell_effects.Blizzard.process", __t)

	func _process_timed(delta: float) -> void:
		age += delta
		queue_redraw()
		for f in _falls:
			if not f[2] and age >= float(f[1]) + FALL:
				f[2] = true
				_land(position + (f[0] as Vector2))
		if age >= time - 0.3 and _snow.emitting:
			_snow.emitting = false
		if age >= time + FALL + 1.2:
			queue_free()

	func _land(at: Vector2) -> void:
		landed += 1
		hits += SpellEffects.strike(world, spell, at, shard_r, amount, by_player)
		SpellEffects.Burst.make(world, at, shard_r, SpellEffects.color(spell))
		SpellEffects.impact_sound(world, spell, at)

	func _draw() -> void:
		var c := SpellEffects.color(spell)
		var shown := clampf(age / 0.4, 0.0, 1.0) * clampf((time + FALL - age) / 0.6, 0.0, 1.0)
		# The storm's ground, faintly.
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))
		draw_circle(Vector2.ZERO, radius, Color(c, 0.08 * shown))
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64, Color(0.9, 0.97, 1.0, 0.35 * shown), 2.0, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var down := -SLANT.normalized()
		var side := down.orthogonal()
		for f in _falls:
			var k := (age - float(f[1])) / FALL
			if k < 0.0 or k >= 1.0:
				continue
			var o: Vector2 = f[0]
			# Its shadow, growing as it nears.
			draw_set_transform(o, 0.0, Vector2(1.0, 0.5))
			draw_circle(Vector2.ZERO, 6.0 + 14.0 * k, Color(0.2, 0.35, 0.5, 0.25 * k))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			var p := o + SLANT * HIGH * (1.0 - k * k)
			var tip := p + down * 26.0
			var tail := p - down * 30.0
			draw_line(tail - down * 40.0, tail, Color(0.9, 0.97, 1.0, 0.35), 3.0, true)
			draw_colored_polygon(PackedVector2Array([tip, p + side * 8.0, tail, p - side * 8.0]), Color(c, 0.95))
			draw_colored_polygon(PackedVector2Array([tip, p + side * 3.0, p - down * 6.0]), SpellEffects.core(c))

