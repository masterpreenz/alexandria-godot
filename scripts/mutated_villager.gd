class_name MutatedVillager
extends Creature
## A villager the mist has taken, early on (one arm swollen purple): it shambles slowly about the mist, standing a
## while, then walking a little way to somewhere dry nearby, and back towards where it started when it strays. While
## Miko is in the mist and it sees her (sight), it comes after her, a little quicker but far slower than she walks, and
## swings its swollen arm down at her when it reaches her (a purple slash; she's hit if she's still in reach on the slam);
## out of the mist, or far enough off
## (giveUpAt), and it gives up. Hit, it flashes pale and is knocked back a little; when it falls it gives Miko some XP and
## drops a few coins.
##
## Its sheets (front: facing south-west, back: north-west; mirrored for the east) are 16 walking frames; standing still
## shows one of them (standFrame).

enum State { STAND, WALK, CHASE, ATTACK }

var state := State.STAND
var home := Vector2.ZERO
var target := Vector2.ZERO
var state_until := 0.0
var clock := 0.0
var _last_pos := Vector2.ZERO
var _stuck := 0.0
var _next_attack := 0.0
var _attack_clock := 0.0
var _hit_done := false
var _slashed := false
var _bar_key: Variant = null      ## the barricade it's swinging at (null: at her)
var _house_wall := {}             ## raiding: the house wall it's smashing at (Raids.house_wall_near), or {}
var prey: Node2D = null            ## who it's after: Miko, or (raiding) a villager too


static func spawn(w: World, d: Dictionary, at: Vector2) -> MutatedVillager:
	var m := MutatedVillager.new()
	m.build(w, d, float(d.settings.hp), 0.25, 1.1, 0.4)
	m.art_scale = World.BODY_SCALE   # a person, the size of everyone else
	m.name = "Mutated Villager"
	m.position = at
	m.home = at
	m.target = at
	m.state_until = now() + randf_range(0.5, 3.0)
	m.clock = randf() * 2.0
	w.things.add_child(m)
	m._show()
	return m


func _physics_process(delta: float) -> void:
	var __t := Time.get_ticks_usec()
	_physics_process_timed(delta)
	Perf.add(&"mutated_villager.physics", __t)


func _physics_process_timed(delta: float) -> void:
	if resting():
		return
	var t := now()
	clock += delta
	# Miko in the mist and in sight: after her. Out of the mist, or got away: back to its wandering. Raiding: after
	# whoever's nearest, Miko or a villager, mist or not; with nobody about, on into the village.
	var p := player()
	prey = _pick_prey(p)
	var hunting := prey != null or raid_to != Vector2.INF
	if hunting and state != State.CHASE and state != State.ATTACK:
		state = State.CHASE
	elif not hunting and state == State.CHASE:
		home = position
		_stand(t)
	match state:
		State.STAND:
			velocity = Vector2.ZERO
			if t >= state_until:
				_pick_walk()
		State.CHASE:
			var goal: Vector2 = prey.position if prey != null else raid_to
			# A barricade in the way: that first.
			var bar := barricade_ahead(goal)
			_bar_key = null if bar.is_empty() else bar[0]
			# Raiding with nobody about to go for: at the nearest house, smashing its walls in.
			if prey == null and bar.is_empty() and raid_to != Vector2.INF and Raids.active != null:
				if not Raids.active.standing(_house_wall):
					_house_wall = Raids.active.house_wall_near(position, 9.0 * world.px)
			else:
				_house_wall = {}
			var to: Vector2 = (goal if bar.is_empty() else bar[1]) - position
			if not _house_wall.is_empty():
				to = _house_wall.mid - position
			var reach := float(s.attackReach) * world.px * (1.0 if bar.is_empty() and _house_wall.is_empty() else 1.3)
			face(to, 0.1)
			if prey == null and bar.is_empty() and _house_wall.is_empty():
				# Marching on the village: round what's in the way; there, on to somewhere else in it.
				if to.length() < 1.2 * world.px:
					raid_to = Raids.spot_in_village(world)
				velocity = steer.around(to.normalized() * float(s.chaseSpeed) * world.px, delta)
			elif to.length() > reach:
				velocity = to.normalized() * float(s.chaseSpeed) * world.px
			else:
				velocity = Vector2.ZERO
				if t >= _next_attack:
					_next_attack = t + float(s.attackEvery)
					state = State.ATTACK
					_attack_clock = 0.0
					_hit_done = false
					_slashed = false
		State.ATTACK:
			velocity = Vector2.ZERO
			_attack_clock += delta
			var f := int(_attack_clock * float(s.attackFps))
			var to_her := prey.position - position if prey != null else Vector2.ZERO
			if _bar_key != null and world.walls.walls.has(_bar_key):
				to_her = world.walls.wall_middle(_bar_key) - position
			elif not _house_wall.is_empty():
				to_her = _house_wall.mid - position
			if f >= int(s.hitFrame) - 1 and not _slashed:
				_slashed = true
				Slash.play(world, position, to_her if to_her != Vector2.ZERO else (Vector2.RIGHT if flip else Vector2.LEFT), Color(0.85, 0.4, 1.0, 0.85), 0.9)
			if f >= int(s.hitFrame) and not _hit_done:
				_hit_done = true
				# The slam lands where she was: she's hit only if she's still in reach.
				if _bar_key != null:
					world.walls.damage(_bar_key, float(s.attackDamage) * 2.0)
				elif not _house_wall.is_empty() and Raids.active != null:
					Raids.active.strike_house_wall(_house_wall, float(s.attackDamage) * 2.0)
				elif prey is Villager and to_her.length() <= float(s.attackReach) * 1.4 * world.px:
					(prey as Villager).hit.hurt(float(s.attackDamage))
				elif prey is Damageable and to_her.length() <= float(s.attackReach) * 1.4 * world.px:
					(prey as Damageable).hurt(float(s.attackDamage))   # (a shield shikigami that drew it off)
				elif prey != null and prey == p and to_her.length() <= float(s.attackReach) * 1.4 * world.px:
					hurt_player(float(s.attackDamage), to_her.normalized() * float(s.knockback) * world.px, 0.2)
			if f >= (s.attackFront as Array).size():
				state = State.CHASE if hunting else State.STAND
				state_until = t + 1.0
		State.WALK:
			var to := target - position
			if to.length() < 0.15 * world.px or t >= state_until:
				_stand(t)
			else:
				var dir := to.normalized()
				velocity = Vector2(dir.x, dir.y) * float(s.walkSpeed) * world.px
				face(to, 0.1)   # (in px: it counts up the screen past a tenth of a unit as away)
				# Bumping into something: give up on that spot.
				_stuck = _stuck + delta if position.distance_to(_last_pos) < 0.2 * delta * float(s.walkSpeed) * world.px else 0.0
				if _stuck > 0.6:
					_stand(t)
	_last_pos = position
	# Never into the water: a step that would end in the river stops at the bank.
	if velocity != Vector2.ZERO and world.wet(position + velocity * delta * 4.0):
		velocity = Vector2.ZERO
		_stand(t)
	move_and_slide()
	_show()
	paint_flash()


# Whether it's after Miko: she's up, in the mist (not on cleared ground), within its sight (and once after her, not yet
# got away).
func _hunting(p: Miko) -> bool:
	if p == null or p.stats == null or p.stats.hp <= 0.0:
		return false
	if world.mist == null or world.mist.tier_at(p.position) == Mist.Tier.CLEAR:
		return false
	var far := float(s.giveUpAt if state == State.CHASE else s.sight) * world.px
	return p.position.distance_to(position) <= far


# Who it's after now, or null: Miko as [method _hunting] says; raiding, the nearest of her and the villagers in sight.
func _pick_prey(p: Miko) -> Node2D:
	# Drawn off by a shield shikigami: that instead.
	var drawn := taunter()
	if drawn != null:
		return drawn
	if raid_to == Vector2.INF:
		return p if _hunting(p) else null
	var best: Node2D = null
	var best_d := float(s.giveUpAt if state == State.CHASE and prey != null else s.sight) * world.px
	if p != null and p.stats != null and p.stats.hp > 0.0 and p.position.distance_to(position) < best_d:
		best = p
		best_d = p.position.distance_to(position)
	for v in Villager.all:
		if is_instance_valid(v) and v.visible and v.hit.alive() and v.position.distance_to(position) < best_d:
			best = v
			best_d = v.position.distance_to(position)
	return best


func _stand(t: float) -> void:
	state = State.STAND
	velocity = Vector2.ZERO
	var idle: Array = s.idle
	state_until = t + randf_range(float(idle[0]), float(idle[1]))


# Somewhere dry a little way off, out of the village, not across water (back towards home if it's wandered far).
func _pick_walk() -> void:
	var reach := float(s.wander) * world.px
	var from := home if position.distance_to(home) > reach else position
	for i in 8:
		var r := Vector2.from_angle(randf() * TAU) * randf_range(0.4, 1.0) * reach
		var spot := from + Vector2(r.x, r.y * 0.5)
		if not world.village.contains(spot, 1.0) and Wilds.dry(world, spot, 0.5) and Wilds.dry_way(world, position, spot):
			target = spot
			state = State.WALK
			_stuck = 0.0
			state_until = now() + position.distance_to(spot) / (float(s.walkSpeed) * world.px) + 1.5
			return
	_stand(now())


func _show() -> void:
	var sheet: Array = s.back if facing_back else s.front
	if state == State.ATTACK:
		var swing: Array = s.attackBack if facing_back else s.attackFront
		show_art(int(swing[mini(int(_attack_clock * float(s.attackFps)), swing.size() - 1)]))
	elif velocity.length_squared() > 1.0:
		var fps := float(s.chaseFps if state == State.CHASE else s.walkFps)
		show_art(int(sheet[int(clock * fps) % sheet.size()]))
	else:
		show_art(int(sheet[int(s.standFrame)]))


func hostile() -> bool:
	return prey != null and (state == State.CHASE or state == State.ATTACK)


func _hurt(_amount: float) -> void:
	flash_until = now() + 0.12
	var p := player()
	if p != null:
		position += (position - p.position).normalized() * 0.15 * world.px


func _died() -> void:
	var p := player()
	if p != null and p.stats != null:
		p.stats.gain_xp(int(s.xp))
	var coins: Array = s.coins
	Pickup.drop(world, "Gold", randi_range(int(coins[0]), int(coins[1])), position)
	# A mist crystal now and then (for cleansing crystals), two from one that came raiding.
	var crystals := (2 if raid_to != Vector2.INF else 1) if randf() < float(s.get("crystalChance", 0.5)) else 0
	if crystals > 0:
		Pickup.launch_icon(world, "Crystal", crystals, position, 2.2)
	drop_seed()
	Puffs.burst(world, position + Vector2(0, -0.4 * world.px), 1.0, 10)
	queue_free()
