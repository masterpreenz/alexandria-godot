class_name MutatedVillager
extends Creature
## A villager the mist has taken, early on (one arm swollen purple): it shambles slowly about the mist, standing a
## while, then walking a little way to somewhere dry nearby, and back towards where it started when it strays. While
## Miko is in the mist and it sees her (sight), it comes after her, a little quicker but far slower than she walks, and
## hits her if it reaches her (a touch, for now: it has no attack of its own yet); out of the mist, or far enough off
## (giveUpAt), and it gives up. Hit, it flashes pale and is knocked back a little; when it falls it gives Miko some XP and
## drops a few coins.
##
## Its sheets (front: facing south-west, back: north-west; mirrored for the east) are 16 walking frames; standing still
## shows one of them (standFrame).

enum State { STAND, WALK, CHASE }

var state := State.STAND
var home := Vector2.ZERO
var target := Vector2.ZERO
var state_until := 0.0
var clock := 0.0
var _last_pos := Vector2.ZERO
var _stuck := 0.0
var _next_touch := 0.0


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
	# Miko in the mist and in sight: after her. Out of the mist, or got away: back to its wandering.
	var p := player()
	var hunting := _hunting(p)
	if hunting and state != State.CHASE:
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
			var to := p.position - position
			var reach := float(s.touchReach) * world.px
			face(to, 0.1)
			if to.length() > reach:
				velocity = to.normalized() * float(s.chaseSpeed) * world.px
			else:
				velocity = Vector2.ZERO
				if t >= _next_touch:
					_next_touch = t + float(s.touchEvery)
					hurt_player(float(s.touchDamage), to.normalized() * float(s.knockback) * world.px, 0.2)
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
	if velocity.length_squared() > 1.0:
		var fps := float(s.chaseFps if state == State.CHASE else s.walkFps)
		show_art(int(sheet[int(clock * fps) % sheet.size()]))
	else:
		show_art(int(sheet[int(s.standFrame)]))


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
	Puffs.burst(world, position + Vector2(0, -0.4 * world.px), 1.0, 10)
	queue_free()
