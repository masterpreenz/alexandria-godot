class_name Rabbit
extends Creature
## A rabbit (from Unity's Rabbit). It lives in a rabbit hole: by day it hops about the grass near it, sitting up and
## nibbling between hops. At night it hops home and dives in, coming back out in the morning. Hit it and it bolts for
## home at full tilt and stays down a while. If its hole is gone it just roams, and sleeps where it sits. Miko can grab
## one alive (E) while it's out. When it falls it vanishes in a puff and drops a bit of meat.
##
## Its sheets (front: facing south-west, back: north-west; mirrored for the east) are 4x4 frames: the top row sitting
## (0-2 at rest, 3 ears back), and a hop (crouch 7, in the air 4, landing 5, sitting 6).

enum State { SIT, HOP, FLEE, HOME, DIVING, HIDDEN, EMERGING, SLEEP }

const HOP_FRAMES := [7, 4, 5, 6]
const GRAB_RANGE := 0.7      ## units: how near Miko must be to grab one

static var rabbits: Array[Rabbit] = []

var hole: Warren.Hole        ## the hole it lives in; null once that's gone (or it never had one)
var state := State.SIT
var target := Vector2.ZERO
var state_until := 0.0
var clock := 0.0
var next_z := 0.0
var _shadow_scale := Vector2.ONE
var _squash := 1.0           ## the body's size (diving in, popping out) on top of the art's own


## Born inside [param h]: it comes out after [param out_in] seconds (unless it's night).
static func spawn(w: World, d: Dictionary, h: Warren.Hole, out_in: float) -> Rabbit:
	var r := Rabbit.new()
	r.build(w, d, float(d.settings.hp), 0.16, 0.4, 0.3)
	r.name = "Rabbit"
	r.hole = h
	r.outline.queue_free()  # Unity's rabbit has no red outline: it's not a threat
	r.outline = null
	if r.shadow != null:
		r._shadow_scale = r.shadow.scale
	r.position = r._door()
	r.target = r.position
	w.things.add_child(r)
	r._hide(out_in)
	return r


func _enter_tree() -> void:
	super._enter_tree()
	rabbits.append(self)


func _exit_tree() -> void:
	super._exit_tree()
	rabbits.erase(self)


## Out and about where Miko can grab it (not down its hole, or diving in or out of it).
func grabbable() -> bool:
	return state != State.HIDDEN and state != State.DIVING and state != State.EMERGING and hit.alive()


## The nearest rabbit she could grab within [param range] px of [param at], or null.
static func nearest(at: Vector2, range: float) -> Rabbit:
	var best: Rabbit = null
	var best_d := range
	for r in rabbits:
		if not r.grabbable():
			continue
		var d := r.position.distance_to(at)
		if d < best_d:
			best_d = d
			best = r
	return best


## Grabbed alive by Miko: gone from the wild (its hole is topped up again in the morning).
func grab() -> void:
	if hole != null:
		hole.rabbits.erase(self)
	Puffs.burst(world, position + Vector2(0, -0.15 * world.px), 0.4, 8)
	queue_free()


# Where it goes in and out: the hole's mouth, a touch in front so it draws over the mound as it dives.
func _door() -> Vector2:
	return hole.position + Vector2(0, 0.06 * world.px) if hole != null else position


func _has_home() -> bool:
	return hole != null and hole.alive


func _night() -> bool:
	if world.clock == null:
		return false
	var h: float = world.clock.hour()
	return h >= 20.0 or h < 5.5


# Rabbits use their own resting (the outline was dropped).
func resting() -> bool:
	var t := now()
	if t >= _check_at:
		_check_at = t + 0.25
		var p := player()
		var d := p.position.distance_to(position) / world.px if p != null else 0.0
		asleep = d > AWAKE_WITHIN + AWAKE_MARGIN if not asleep else d > AWAKE_WITHIN
		if asleep:
			velocity = Vector2.ZERO
	return asleep


func _physics_process(delta: float) -> void:
	var __t := Time.get_ticks_usec()
	_physics_process_timed(delta)
	Perf.add(&"rabbit.physics", __t)


func _physics_process_timed(delta: float) -> void:
	if resting():
		return
	var t := now()
	# Its hole was taken away: nowhere to go but out and about.
	if not _has_home() and (state == State.HIDDEN or state == State.DIVING or state == State.HOME):
		if state != State.HOME:
			_emerge()
		else:
			state = State.SIT
			state_until = t + 1.0
	_squash = 1.0 if state != State.DIVING and state != State.EMERGING else _squash
	var nibble := 1.0
	art.position = Vector2.ZERO
	match state:
		State.SIT:
			if _night(): _go_home()
			else: nibble = _sit(t)
		State.HOP:
			if _night(): _go_home()
			else: _hop(t, float(s.hopSpeed), false, delta)
		State.FLEE:
			if _has_home():
				target = _door()
				_hop(t, float(s.fleeSpeed), true, delta)
			elif t < state_until:
				_hop(t, float(s.fleeSpeed), true, delta)
			else:
				state = State.SIT
				state_until = t + 2.0
		State.HOME:
			target = _door()
			_hop(t, float(s.hopSpeed) * 1.4, true, delta)
		State.DIVING:
			velocity = Vector2.ZERO
			clock += delta / 0.22
			position = position.lerp(_door(), 0.3)
			_squash = maxf(0.0, 1.0 - clock)
			art.position = Vector2(0, 0.1 * clock * world.px)
			if clock >= 1.0:
				_hide(0.0 if _night() else state_until - t)
		State.HIDDEN:
			velocity = Vector2.ZERO
			# Out again once it's day, its time down is up, and nobody's standing right at the door.
			var p := player()
			var near := p != null and p.position.distance_to(_door()) < 1.6 * world.px
			if not _night() and t >= state_until and not near:
				_emerge()
		State.EMERGING:
			velocity = Vector2.ZERO
			clock += delta / 0.25
			var k := minf(1.0, clock)
			_squash = k * 1.08 if k < 1.0 else 1.0
			art.position = Vector2(0, 0.1 * (1.0 - k) * world.px)
			_show(0)
			if clock >= 1.0:
				_squash = 1.0
				art.position = Vector2.ZERO
				state = State.SIT
				state_until = t + randf_range(1.0, 2.5)
		State.SLEEP:
			nibble = _sleep_out(t)
	if state != State.HIDDEN:
		_reshow(nibble)
		move_and_slide()
	if shadow != null:
		shadow.scale = _shadow_scale * _squash
	paint_flash(Color(1, 0.75, 0.72))


var _frame := 0

func _show(frame: int) -> void:
	_frame = frame


func _reshow(squash_y: float) -> void:
	var sheet: Array = s.back if facing_back else s.front
	if _frame < sheet.size():
		world.show_frame(art, int(sheet[_frame]), Vector2(-_squash if flip else _squash, _squash * squash_y))


# Sitting up: ears twitching now and then, a little nibble; then off to another spot.
func _sit(t: float) -> float:
	velocity = Vector2.ZERO
	var twitch := fposmod(t * 0.7 + position.x / world.px, 4.0)
	_show(1 if twitch < 0.15 else (2 if twitch > 2.0 and twitch < 2.12 else 0))
	if t >= state_until:
		if _pick_spot():
			state = State.HOP
			clock = 0.0
		else:
			state_until = t + randf_range(1.0, 3.0)
		return 1.0
	return 0.97 if sin(t * 9.0 + position.y / world.px) > 0.75 else 1.0


# Hops: a crouch, a leap, a landing, a sit. It only travels while in the air.
func _hop(t: float, speed: float, hurry: bool, delta: float) -> void:
	var dir := target - position
	if dir.length() < 0.12 * world.px:
		velocity = Vector2.ZERO
		if state == State.HOP:
			state = State.SIT
			state_until = t + randf_range(1.5, 4.5)
		elif (state == State.FLEE or state == State.HOME) and _has_home():
			_dive(t + randf_range(8.0, 14.0) if state == State.FLEE else t)
		else:
			state = State.SIT
			state_until = t + 2.0
		return
	face(dir, 0.15)
	clock += delta * float(s.hopFps) * (1.8 if hurry else 1.0)
	var frame: int = HOP_FRAMES[floori(clock) % HOP_FRAMES.size()]
	_show(frame)
	var airborne := frame == 4 or frame == 5
	var step := speed * 2.0 * world.px if airborne else 0.0  # all the ground covered in the half it's off its feet
	var v := dir.normalized() * minf(step, dir.length() / maxf(delta, 0.001))
	if not hurry and world.village.contains(position + v * 0.3, 0.2) and not _in_village():
		v = Vector2.ZERO
		_pick_spot()
	if v != Vector2.ZERO:
		# Round trees and rocks, not into them.
		v = steer.around(v, delta)
		if steer.stuck:
			if state == State.HOP:
				if not _pick_spot():
					state = State.SIT
					state_until = t + 1.0
			# Nearly home but can't quite reach the door: in it goes anyway.
			elif _has_home() and dir.length() < 1.2 * world.px:
				_dive(t + randf_range(8.0, 14.0) if state == State.FLEE else t)
	velocity = v


func _in_village() -> bool:
	return hole != null and world.village.contains(hole.position, 0.5)


func _go_home() -> void:
	if _has_home():
		state = State.HOME
		clock = 0.0
	else:
		state = State.SLEEP
		next_z = now() + 1.0
		velocity = Vector2.ZERO


func _dive(out_at: float) -> void:
	state = State.DIVING
	clock = 0.0
	state_until = out_at
	velocity = Vector2.ZERO


# Down the hole: out of sight and out of the way until it comes back up.
func _hide(out_in: float) -> void:
	state = State.HIDDEN
	state_until = now() + maxf(0.0, out_in)
	visible = false
	collision_layer = 0
	hit.process_mode = Node.PROCESS_MODE_DISABLED
	Damageable.all.erase(hit)  # nothing can hit it down there
	velocity = Vector2.ZERO
	if _has_home():
		position = _door()
	_squash = 1.0
	art.position = Vector2.ZERO


func _emerge() -> void:
	visible = true
	collision_layer = 2
	hit.process_mode = Node.PROCESS_MODE_INHERIT
	if not Damageable.all.has(hit):
		Damageable.all.append(hit)
	state = State.EMERGING
	clock = 0.0
	_squash = 0.0
	face(Vector2(-1.0 if randf() < 0.5 else 1.0, 1.0) * world.px)


# No hole to go to: it hunkers down where it is, ears back, the odd "z".
func _sleep_out(t: float) -> float:
	velocity = Vector2.ZERO
	_show(3)
	if t >= next_z:
		next_z = t + 2.6
		FloatingText.spawn(world, "z", position + Vector2((0.2 if flip else -0.2) * world.px, -0.45 * world.px), Color(0.78, 0.84, 1.0))
	if not _night():
		state = State.SIT
		state_until = t + 1.0
	return 1.0 + 0.02 * sin(t * 1.8)


# Another spot close to home (or to where it is, without one): open ground, not in the village.
func _pick_spot() -> bool:
	var centre := hole.position if _has_home() else position
	var in_village := _in_village()
	for i in 10:
		var r := Vector2.from_angle(randf() * TAU) * sqrt(randf()) * float(s.roam) * world.px
		var spot := centre + Vector2(r.x, r.y * 0.5)
		var ok := _clear(spot) if in_village else Wilds.open(world, spot, 0.3, 0.2)
		if ok:
			target = spot
			return true
	return false


func _clear(at: Vector2) -> bool:
	var q := PhysicsShapeQueryParameters2D.new()
	var c := CircleShape2D.new()
	c.radius = 0.2 * world.px
	q.shape = c
	q.transform = Transform2D(0.0, at)
	q.collision_mask = 1
	return get_world_2d().direct_space_state.intersect_shape(q, 1).is_empty()


# Hit: it bolts for its hole (or just away from her, without one).
func _hurt(_amount: float) -> void:
	flash_until = now() + 0.12
	clock = 0.0
	state = State.FLEE
	if not _has_home():
		var p := player()
		var away := position - p.position if p != null else Vector2.from_angle(randf() * TAU)
		if away.length_squared() < 1.0:
			away = Vector2.LEFT
		target = position + away.normalized() * 4.0 * world.px
		state_until = now() + 1.6


func _died() -> void:
	var p := player()
	if p != null and p.stats != null:
		p.stats.gain_xp(int(s.xp))
	var at := position + Vector2(0, -0.15 * world.px)
	Puffs.burst(world, at, 0.7, 14)
	Pickup.launch_icon(world, "Food", 1, at, 1.8)
	queue_free()
