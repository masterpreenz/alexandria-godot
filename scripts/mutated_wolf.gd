class_name MutatedWolf
extends Creature
## A wolf the mist has taken (a purple flame for a tail, crystal on its brow). It roams the mist, standing a while then
## trotting off somewhere dry nearby. While Miko is in the mist and it sees her, it runs her down, much faster than the
## mutated villagers; in leaping range it crouches, and a strip on the ground shows where it will land (pale red,
## filling dark red as the leap nears; its line follows her, then is set a moment before it goes, so a step aside
## makes it miss). Then it leaps along the strip: anyone on it when it lands is hit and knocked back. It lands,
## shakes itself, and comes on again. Out of the mist, or far enough off, it gives up. When it falls it gives XP, a
## few coins, and now and then a mist crystal.
##
## Its sheets (front: facing south-west, back: north-west; mirrored for the east) are 16 frames each: standing, running,
## and the leap (crouching 0-6, in the air 7-11, landing 12-15).

enum State { STAND, WALK, CHASE, CROUCH, LEAP, LAND }

var state := State.STAND
var home := Vector2.ZERO
var target := Vector2.ZERO
var state_until := 0.0
var clock := 0.0
var _last_pos := Vector2.ZERO
var _stuck := 0.0
var _next_jump := 0.0
var _leap_from := Vector2.ZERO
var _leap_to := Vector2.ZERO
var _hit_done := false
var warn: Telegraph                ## where it will land, on the ground, while it crouches
var prey: Node2D = null


static func spawn(w: World, d: Dictionary, at: Vector2) -> MutatedWolf:
	var m := MutatedWolf.new()
	m.build(w, d, float(d.settings.hp), 0.3, 0.8, 0.45)
	m.name = "Mutated Wolf"
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
	Perf.add(&"mutated_wolf.physics", __t)


func _physics_process_timed(delta: float) -> void:
	if resting():
		_clear_warn()
		return
	var t := now()
	clock += delta
	var p := player()
	prey = _pick_prey(p)
	var busy := state == State.CROUCH or state == State.LEAP or state == State.LAND
	if prey != null and not busy and state != State.CHASE:
		state = State.CHASE
	elif prey == null and state == State.CHASE:
		home = position
		_stand(t)
	match state:
		State.STAND:
			velocity = Vector2.ZERO
			if t >= state_until:
				_pick_walk()
		State.WALK:
			var to := target - position
			if to.length() < 0.15 * world.px or t >= state_until:
				_stand(t)
			else:
				velocity = to.normalized() * float(s.walkSpeed) * world.px
				face(to, 0.1)
				_stuck = _stuck + delta if position.distance_to(_last_pos) < 0.2 * delta * float(s.walkSpeed) * world.px else 0.0
				if _stuck > 0.6:
					_stand(t)
		State.CHASE:
			var to: Vector2 = prey.position - position
			face(to, 0.1)
			var far := to.length()
			if far <= float(s.jumpFrom) * world.px and t >= _next_jump and _clear_leap(prey.position):
				_crouch(t)
			elif far > float(s.jumpMin) * world.px * 0.8:
				var step := way_to(prey.position) - position
				var v := step.normalized() * float(s.chaseSpeed) * world.px
				velocity = v if _route != null else steer.around(v, delta)
				if stuck_on(prey):
					prey = null
			else:
				# (too close to leap: circling back out a little)
				velocity = -to.normalized() * float(s.walkSpeed) * world.px
		State.CROUCH:
			velocity = Vector2.ZERO
			var left := state_until - t
			# The strip: following her, then set a moment before it goes.
			if prey != null and left > float(s.aimLock):
				_aim(prey.position)
			if warn != null:
				warn.set_fill(1.0 - left / maxf(0.01, float(s.windUp)))
				face(warn.dir, 0.1)
			if t >= state_until:
				_leap(t)
		State.LEAP:
			var k := clampf(1.0 - (state_until - t) / float(s.leapTime), 0.0, 1.0)
			var at := _leap_from.lerp(_leap_to, k)
			velocity = (at - position) / maxf(delta, 0.001)
			if t >= state_until:
				velocity = Vector2.ZERO
				_land(t, p)
		State.LAND:
			velocity = Vector2.ZERO
			if t >= state_until:
				state = State.CHASE if prey != null else State.STAND
				state_until = t + randf_range(1.0, 2.0)
	_last_pos = position
	# Never into the water: a step that would end in the river stops at the bank (a leap lands short of it).
	if velocity != Vector2.ZERO and world.wet(position + velocity * delta * 4.0):
		velocity = Vector2.ZERO
		if state == State.LEAP:
			_leap_to = position
		elif state == State.WALK or state == State.CHASE:
			_stand(t)
	move_and_slide()
	_show()
	paint_flash()


# Whether it's after Miko: she's up, in the mist, within its sight (once after her, till she's got far enough away).
func _hunting(p: Miko) -> bool:
	if p == null or p.stats == null or p.stats.hp <= 0.0:
		return false
	if world.mist == null or world.mist.tier_at(p.position) == Mist.Tier.CLEAR:
		return false
	var busy := state == State.CHASE or state == State.CROUCH or state == State.LEAP or state == State.LAND
	return p.position.distance_to(position) <= float(s.giveUpAt if busy else s.sight) * world.px


func _pick_prey(p: Miko) -> Node2D:
	var drawn := taunter()
	if drawn != null:
		return drawn
	return p if _hunting(p) else null


# Nothing in the way of a leap to [param at] (no water under it, no wall across it).
func _clear_leap(at: Vector2) -> bool:
	var to := position + (at - position).normalized() * minf(at.distance_to(position), float(s.jumpReach) * world.px)
	return Wilds.dry_way(world, position, to) and not world.village.contains(to, 0.5)


# Down on its haunches, the strip shown.
func _crouch(t: float) -> void:
	state = State.CROUCH
	state_until = t + float(s.windUp)
	velocity = Vector2.ZERO
	clock = 0.0
	if warn == null:
		warn = Telegraph.make(world, float(s.strip))
	_aim(prey.position)


# The strip pointed at [param at]: as far as it leaps, at least its shortest leap.
func _aim(at: Vector2) -> void:
	if warn == null:
		return
	var d := at - position
	var most := float(s.jumpReach) * world.px
	var span := clampf(d.length() + 0.6 * world.px, float(s.jumpMin) * world.px, most)
	var dir := d.normalized() if d.length_squared() > 1.0 else warn.dir
	warn.point(position, position + dir * span, most)


func _leap(t: float) -> void:
	_leap_from = position
	_leap_to = warn.end() if warn != null else position
	state = State.LEAP
	state_until = t + float(s.leapTime)
	_hit_done = false
	clock = 0.0


# Down: whoever's on the strip now is hit (and knocked on along it); the strip goes.
func _land(t: float, p: Miko) -> void:
	if not _hit_done and warn != null:
		_hit_done = true
		var dir := warn.dir
		if p != null and p.stats != null and p.stats.hp > 0.0 and warn.covers(p.position):
			hurt_player(float(s.damage), dir * float(s.knockback) * world.px, float(s.tossTime))
		for v in Villager.all:
			if is_instance_valid(v) and v.visible and v.hit.alive() and warn.covers(v.position):
				v.hit.hurt(float(s.damage))
		var drawn := taunter()
		if drawn != null and warn.covers(drawn.global_position):
			drawn.hurt(float(s.damage))
	Puffs.burst(world, position, 0.7, 8)
	_clear_warn()
	state = State.LAND
	state_until = t + 4.0 / float(s.landFps)
	_next_jump = t + float(s.jumpEvery)
	clock = 0.0


func _clear_warn() -> void:
	if warn != null:
		warn.queue_free()
		warn = null


func _stand(t: float) -> void:
	_clear_warn()
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
	match state:
		State.CROUCH:
			# Crouching through its first frames as the strip fills.
			var k := 1.0 - (state_until - now()) / maxf(0.01, float(s.windUp))
			_frame(s.jumpBack if facing_back else s.jumpFront, mini(floori(k * float(s.crouchFrames)), int(s.crouchFrames) - 1))
		State.LEAP:
			var span: Array = s.leapFrames
			var k := clampf(1.0 - (state_until - now()) / float(s.leapTime), 0.0, 1.0)
			_frame(s.jumpBack if facing_back else s.jumpFront, int(span[0]) + mini(floori(k * float(int(span[1]) - int(span[0]) + 1)), int(span[1]) - int(span[0])))
		State.LAND:
			var first := int((s.leapFrames as Array)[1]) + 1
			_frame(s.jumpBack if facing_back else s.jumpFront, mini(first + floori(clock * float(s.landFps)), 15))
		_:
			if velocity.length_squared() > 1.0:
				var run: Array = s.runBack if facing_back else s.runFront
				var fps := float(s.runFps) if state == State.CHASE else float(s.walkFps)
				_frame(run, int(clock * fps) % run.size())
			else:
				var idle: Array = s.back if facing_back else s.front
				_frame(idle, int(clock * float(s.idleFps)) % idle.size())


func _frame(sheet: Array, i: int) -> void:
	show_art(int(sheet[clampi(i, 0, sheet.size() - 1)]))


func hostile() -> bool:
	return prey != null and state != State.STAND and state != State.WALK


func _hurt(_amount: float) -> void:
	flash_until = now() + 0.12


func _exit_tree() -> void:
	super._exit_tree()
	_clear_warn()


func _died() -> void:
	_clear_warn()
	var p := player()
	if p != null and p.stats != null:
		p.stats.gain_xp(int(s.xp))
	var coins: Array = s.coins
	Pickup.drop(world, "Gold", randi_range(int(coins[0]), int(coins[1])), position)
	if randf() < float(s.get("crystalChance", 0.5)):
		Pickup.launch_icon(world, "Crystal", 1, position, 2.2)
	drop_seed()
	Puffs.burst(world, position + Vector2(0, -0.3 * world.px), 1.0, 10)
	queue_free()
