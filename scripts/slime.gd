class_name Slime
extends Creature
## A slime (from Unity's Slime): hops about near where it spawned, minding its own business. Hit it and it turns on
## Miko: it hops after her, biting on contact and bouncing back off her, until she gets well away and it calms down.
## Wandering it keeps out of the village; chasing, it follows her in. A large one is twice the size, three times as
## tough and hits harder. Out of the mist it's stronger (more HP, harder hits, a deeper purple). Falling, it gives
## experience, coins, maybe a mist crystal and slime jelly, and bursts.
##
## Its sheets (front: facing south-west, back: north-west; mirrored for the east) are 8 frames: 0-2 a resting wobble,
## 3-7 a hop (crouch, rise, air, land, settle).

var large := false
var power := 1.0
var home := Vector2.ZERO
var target := Vector2.ZERO
var chasing := false
var hopping := false
var bouncing := false
var angry_until := -1.0
var hop_from := Vector2.ZERO
var clock := 0.0
var rest_until := 0.0
var last_hit := -99.0
var tint := Color.WHITE


static func spawn(w: World, d: Dictionary, is_large: bool, at: Vector2, mist_power := 1.0) -> Slime:
	var sl := Slime.new()
	sl.large = is_large
	var st: Dictionary = d.settings
	var k := 2.0 if is_large else 1.0
	sl.build(w, d, (float(st.hp) * 3.0 if is_large else float(st.hp)) * maxf(1.0, mist_power), 0.22 * k, 0.45 * k, 0.35)
	sl.name = "Large Slime" if is_large else "Slime"
	sl.grow(k)
	sl.position = at
	sl.home = at
	sl.target = at
	sl.power = maxf(1.0, mist_power)
	if sl.power > 1.01:
		sl.tint = Color.WHITE.lerp(Color(0.8, 0.62, 1.0), inverse_lerp(1.0, 1.5, sl.power))
	sl.art.modulate = sl.tint
	sl.rest_until = now() + randf_range(0.0, 2.0)
	sl.clock = randf() * 3.0
	w.things.add_child(sl)
	sl._show(0)
	return sl


func _scale() -> float:
	return 2.0 if large else 1.0


func _physics_process(delta: float) -> void:
	var __t := Time.get_ticks_usec()
	_physics_process_timed(delta)
	Perf.add(&"slime.physics", __t)


func _physics_process_timed(delta: float) -> void:
	if resting():
		return
	var t := now()
	var p := player()
	var at := position
	# Only once it's been hit: then it goes for whoever's nearest, Miko or a villager (into the village too: it's no
	# safe place now), giving up past its leash.
	var angry := t < angry_until
	var reach := float(s.sight) * (1.25 if large else 1.0) * world.px
	var leash := float(s.leash) * world.px
	var seen := false
	var prey: Node2D = null
	var prey_body: Damageable = null
	if angry:
		var best := reach
		if p != null and p.stats.hp > 0.0 and p.position.distance_to(at) < best and p.position.distance_to(home) < leash:
			best = p.position.distance_to(at)
			prey = p
		for v in Villager.all:
			if not v.visible or not v.hit.alive():
				continue
			var dd := v.position.distance_to(at)
			if dd < best and v.position.distance_to(home) < leash:
				best = dd
				prey = v
				prey_body = v.hit
		seen = prey != null
	# Drawn off by a shield shikigami: that instead.
	var drawn := taunter()
	if drawn != null:
		prey = drawn
		prey_body = drawn
		seen = true
	if seen:
		angry_until = maxf(angry_until, t + float(s.calmAfter))
	if seen != chasing:
		chasing = seen
		if not seen:
			_pick_wander()
	# A barricade in the way: that first.
	var bar := barricade_ahead(prey.position) if chasing else []
	# Raiding with nobody about to go for: at the nearest house's walls.
	var house := {}
	if not chasing and raid_to != Vector2.INF and Raids.active != null:
		house = Raids.active.house_wall_near(at, 9.0 * world.px)
	if chasing:
		target = prey.position if bar.is_empty() else bar[1]
	elif not house.is_empty():
		target = house.mid
	elif at.distance_to(home) > float(s.leash) * world.px:
		target = home
	_animate(t, delta)
	if not bar.is_empty():
		_bite_barricade(t, bar)
	elif not house.is_empty():
		_bite_house(t, house)
	elif prey_body != null:
		_bite_villager(t, prey_body, prey.position - at)
	elif p != null:
		_bite(t, p.position - at)
	# Never into the water: a step that would end in the river stops at the bank.
	if velocity != Vector2.ZERO and world.wet(position + velocity * get_physics_process_delta_time() * 4.0):
		velocity = Vector2.ZERO
	move_and_slide()
	paint_flash()


func _animate(t: float, delta: float) -> void:
	if bouncing:
		_bounce(t, delta)
		return
	if not hopping:
		# Resting: a slow wobble (0, 1, 2, 1), until it's time to hop again.
		clock += delta * float(s.restFps)
		var f := floori(clock) % 4
		_show(1 if f == 3 else f)
		velocity = Vector2.ZERO
		var far := position.distance_to(target) > 0.25 * world.px
		if t >= rest_until and far:
			hopping = true
			clock = 0.0
			hop_from = position
			face(target - position)
		elif t >= rest_until and not far:
			_pick_wander()
		return
	# Hopping: frames 3 to 7; it only moves while off the ground (4 to 6).
	clock += delta * float(s.hopFps) * (1.25 if chasing else 1.0)
	var frame := 3 + floori(clock)
	if frame > 7:
		hopping = false
		clock = 0.0
		velocity = Vector2.ZERO
		rest_until = t + (randf_range(0.05, 0.25) if chasing else randf_range(0.2, 0.6))
		if not chasing and position.distance_to(target) < 0.3 * world.px:
			rest_until = t + randf_range(1.0, 3.5)
		return
	_show(frame)
	var dir := target - position
	var airborne := frame >= 4 and frame <= 6
	var v := Vector2.ZERO
	if airborne and dir.length() > 0.1 * world.px:
		v = dir.normalized() * float(s.hopSpeed) * world.px * (1.2 if chasing else 1.0) * (0.85 if large else 1.0)
	# Wandering, it keeps out of the village (unless it's raiding it).
	if not chasing and raid_to == Vector2.INF and v != Vector2.ZERO and world.village.contains(position + v * 0.25, 0.3):
		v = Vector2.ZERO
		_pick_wander()
	if v != Vector2.ZERO:
		# Round trees and rocks, not into them; somewhere else to go if it still can't get there.
		v = steer.around(v, delta)
		if steer.stuck and not chasing:
			_pick_wander()
	velocity = v


func _show(frame: int) -> void:
	var sheet: Array = s.back if facing_back else s.front
	if frame < sheet.size():
		show_art(int(sheet[frame]))


# Touching Miko hurts her, now and then, and it bounces back off her.
func _bite(t: float, to_player: Vector2) -> void:
	var p := player()
	if p.stats == null or t - last_hit < float(s.hitEvery) or t >= angry_until:
		return
	var reach := (0.26 * _scale() + 0.22) * world.px
	var d := to_player.length()
	if d > reach or p.stats.hp <= 0.0:
		return
	last_hit = t
	var away := to_player / d if d > 0.01 else (Vector2.RIGHT if flip else Vector2.LEFT)
	hurt_player(float(s.damage) * (2.5 if large else 1.0) * power, away * (3.2 if large else 2.2) * world.px, 0.16)
	# Bounces off her: the hop backwards, back to where it jumped from (or a little way back if it was sitting).
	if not hopping or hop_from.distance_to(position) < 0.2 * world.px:
		hop_from = position - away * 0.55 * _scale() * world.px
		clock = 4.0
	hopping = false
	bouncing = true
	clock = clampf(clock, 1.0, 4.99)


# Butting at a barricade in its way, now and then.
func _bite_barricade(t: float, bar: Array) -> void:
	if t - last_hit < float(s.hitEvery) or position.distance_to(bar[1]) > (0.3 * _scale() + 0.45) * world.px:
		return
	last_hit = t
	world.walls.damage(bar[0], float(s.damage) * (2.5 if large else 1.0) * power)


# Raiding: at a house's wall (from Raids.house_wall_near), biting at it now and then.
func _bite_house(t: float, w: Dictionary) -> void:
	if t - last_hit < float(s.hitEvery) or position.distance_to(w.mid) > (0.3 * _scale() + 0.45) * world.px:
		return
	last_hit = t
	Raids.active.strike_house_wall(w, float(s.damage) * (2.5 if large else 1.0) * power)


# Touching a villager hurts them, now and then.
func _bite_villager(t: float, villager: Damageable, to_them: Vector2) -> void:
	if t - last_hit < float(s.hitEvery):
		return
	var reach := (0.26 * _scale() + 0.22) * world.px
	var d := to_them.length()
	if d > reach:
		return
	last_hit = t
	villager.hurt(float(s.damage) * (2.5 if large else 1.0) * power)
	var away := to_them / d if d > 0.01 else (Vector2.RIGHT if flip else Vector2.LEFT)
	if not hopping or hop_from.distance_to(position) < 0.2 * world.px:
		hop_from = position - away * 0.55 * _scale() * world.px
		clock = 4.0
	hopping = false
	bouncing = true
	clock = clampf(clock, 1.0, 4.99)


# The hop run backwards (7 back to 3), carrying it back to where the hop started.
func _bounce(t: float, delta: float) -> void:
	var fps := float(s.hopFps) * 1.3
	clock -= delta * fps
	if clock < 0.0:
		bouncing = false
		clock = 0.0
		velocity = Vector2.ZERO
		rest_until = t + randf_range(0.5, 0.9)
		return
	_show(clampi(3 + floori(clock), 3, 7))
	var left := maxf(0.05, clock / fps)
	velocity = ((hop_from - position) / left).limit_length(float(s.hopSpeed) * 3.0 * world.px)


func _pick_wander() -> void:
	for i in 6:
		var r := Vector2.from_angle(randf() * TAU) * sqrt(randf()) * float(s.wander) * world.px
		var spot := home + Vector2(r.x, r.y * 0.5)
		# Never into the river: dry there, back from the bank, and nothing to cross on the way.
		if not world.village.contains(spot, 0.5) and Wilds.dry(world, spot, 0.5) and Wilds.dry_way(world, position, spot):
			target = spot
			return
	target = home


func hostile() -> bool:
	return chasing


func _hurt(_amount: float) -> void:
	flash_until = now() + 0.12
	# Knocked back a little, and angry now.
	var p := player()
	if p != null:
		var away := (position - p.position).normalized()
		position += away * 0.18 * world.px / _scale()
	home = position
	angry_until = now() + float(s.calmAfter)


func _died() -> void:
	var p := player()
	if p != null and p.stats != null:
		p.stats.gain_xp(int(s.xp) * (3 if large else 1))
	var coins: Array = s.coins
	var n := randi_range(int(coins[0]), int(coins[1])) * (4 if large else 1)
	Pickup.drop(world, "Gold", n, position)
	# A mist crystal (for cleansing crystals), and slime jelly (to cook).
	var crystals := 2 if large else (1 if randf() < float(s.crystalChance) else 0)
	if crystals > 0:
		Pickup.launch_icon(world, "Crystal", crystals, position, 2.2)
	var jelly := 3 if large else (1 if randf() < float(s.jellyChance) else 0)
	if jelly > 0:
		Pickup.launch_icon(world, "Jelly", jelly, position, 2.2)
	drop_seed()
	SlimePop.play(world, art, position, 1.0)
	queue_free()


## A slime bursting: its last frame squashing flat and fading, and a few droplets flying.
class SlimePop extends Node2D:
	var sprite: Sprite2D
	var drops: Array[Sprite2D] = []
	var drop_velocity: Array[Vector2] = []
	var age := 0.0
	var k := 1.0
	var base := Vector2.ONE
	var unit := 128.0

	static func play(w: World, from: Sprite2D, at: Vector2, size: float) -> void:
		var pop := SlimePop.new()
		pop.k = size
		pop.unit = w.px
		pop.position = at
		pop.sprite = from.duplicate() as Sprite2D
		pop.sprite.position = from.position * size
		pop.sprite.material = null
		pop.base = from.scale * size
		pop.sprite.scale = pop.base
		pop.add_child(pop.sprite)
		for i in 6:
			var d := from.duplicate() as Sprite2D
			d.material = null
			d.scale = from.scale * 0.18 * size
			d.position = Vector2(0, -0.15 * size * w.px)
			pop.add_child(d)
			pop.drops.append(d)
			var a := (i / 6.0 + randf_range(-0.05, 0.05)) * TAU
			pop.drop_velocity.append(Vector2(cos(a), -(sin(a) * 0.5 + 0.9)) * randf_range(1.2, 2.0) * size * w.px)
		w.things.add_child(pop)

	func _process(delta: float) -> void:
		var __t := Time.get_ticks_usec()
		_process_timed(delta)
		Perf.add(&"slime.SlimePop.process", __t)


	func _process_timed(delta: float) -> void:
		age += delta
		var t := clampf(age / 0.45, 0.0, 1.0)
		sprite.scale = Vector2(base.x * (1.0 + t * 0.5), base.y * (1.0 - t * 0.8))
		modulate.a = 1.0 - t
		for i in drops.size():
			drop_velocity[i] += Vector2(0, 6.0 * unit) * delta
			drops[i].position += drop_velocity[i] * delta
		if t >= 1.0:
			queue_free()
