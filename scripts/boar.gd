class_name Boar
extends Creature
## A boar (from Unity's Boar). By day it keeps to the grass: grazing, then ambling to another patch nearby, leaving
## Miko be. Hit it and it charges: it paws the ground, then barrels straight at her in a cloud of dust, hurting her and
## throwing her back (and up off her feet) if it connects. At night it goes into the nearest wood and sleeps there,
## lying down until dawn; it only wakes for someone right beside it or a hit (and then charges). It never goes into the
## village. When it falls it vanishes in a puff of dust and its meat and hide fly out.
##
## Its sheets (front: facing south-west, back: north-west; mirrored for the east) are 13 frames: 0 standing, 1-12 a
## gallop. Walking uses every other gallop frame, slowly; the charge uses them all, fast. Lying down: 0-11 settling,
## then it holds 11 asleep.

enum State { GRAZE, WALK, WIND_UP, CHARGE, RECOVER, TO_BED, LYING_DOWN, SLEEP, GETTING_UP }

const WALK_FRAMES := [1, 3, 5, 7, 9, 11]
const SETTLED := 11

var state := State.GRAZE
var home := Vector2.ZERO
var target := Vector2.ZERO
var bed := Vector2.ZERO
var charge_dir := Vector2.LEFT
var state_until := 0.0
var clock := 0.0
var angry_until := -1.0
var next_z := 0.0
var bed_tries := 0
var hit_this_charge := false
var charge_on_waking := false
var dust: CPUParticles2D
var warn: Telegraph               ## where the charge will go, on the ground, while it paws
const AIM_LOCK := 0.25            ## seconds before it goes when its line is set (a step aside, then, and it misses)


static func spawn(w: World, d: Dictionary, at: Vector2) -> Boar:
	var b := Boar.new()
	b.build(w, d, float(d.settings.hp), 0.32, 0.8, 0.45)
	b.name = "Boar"
	b.position = at
	b.home = at
	b.target = at
	b.state_until = now() + randf_range(1.0, 4.0)
	b.dust = CPUParticles2D.new()
	b.dust.emitting = false
	b.dust.amount = 60
	b.dust.lifetime = 0.8
	b.dust.local_coords = false
	b.dust.texture = Puffs.TEX
	b.dust.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	b.dust.emission_sphere_radius = 0.15 * w.px
	b.dust.spread = 180.0
	b.dust.gravity = Vector2.ZERO
	b.dust.initial_velocity_min = 0.2 * w.px
	b.dust.initial_velocity_max = 0.7 * w.px
	var tex_size := float(Puffs.TEX.get_width())
	b.dust.scale_amount_min = 0.25 * w.px / tex_size
	b.dust.scale_amount_max = 0.5 * w.px / tex_size
	var grows := Curve.new()
	grows.add_point(Vector2(0, 0.6))
	grows.add_point(Vector2(1, 1.8))
	b.dust.scale_amount_curve = grows
	var g := Gradient.new()
	g.set_color(0, Color(0.72, 0.62, 0.5, 0.75))
	g.set_color(1, Color(0.55, 0.48, 0.4, 0.0))
	g.add_point(0.4, Color(0.65, 0.56, 0.46, 0.45))
	b.dust.color_ramp = g
	b.dust.position = Vector2(0, -0.05 * w.px)
	b.add_child(b.dust)
	w.things.add_child(b)
	b._show(0)
	return b


func _night() -> bool:
	if world.clock == null:
		return false
	var h: float = world.clock.hour()
	return h >= 20.0 or h < 5.5


func _physics_process(delta: float) -> void:
	var __t := Time.get_ticks_usec()
	_physics_process_timed(delta)
	Perf.add(&"boar.physics", __t)


func _physics_process_timed(delta: float) -> void:
	if resting():
		return
	var t := now()
	var p := player()
	var to_player := p.position - position if p != null else Vector2.ZERO
	var player_out := p != null and not world.village.contains(p.position) and (p.stats == null or p.stats.hp > 0.0)
	# (hunted: it's the hunter it goes for)
	var h := hunted_by()
	if h != null:
		to_player = h.position - position
		player_out = true
	var near := 7.0 * world.px
	if state == State.WIND_UP or state == State.CHARGE:
		angry_until = maxf(angry_until, t + 6.0)
	match state:
		State.GRAZE, State.WALK:
			if _night():
				_go_to_bed()
			elif player_out and t < angry_until and to_player.length() < near:
				_begin_wind_up()
			elif state == State.GRAZE:
				_graze(t)
			else:
				_walk(t, float(s.walkSpeed), delta)
		State.WIND_UP:
			_wind_up(t, to_player)
		State.CHARGE:
			_charge(t, to_player, delta)
		State.RECOVER:
			velocity = Vector2.ZERO
			_show(0)
			if t >= state_until:
				state = State.GRAZE
				state_until = t + randf_range(0.5, 1.5)
				home = position
		State.TO_BED:
			if not _night():
				_wake()
			elif t < angry_until and player_out and to_player.length() < near:
				_begin_wind_up()
			else:
				target = bed
				_walk(t, float(s.walkSpeed) * 1.4, delta)
				if position.distance_to(bed) < 0.25 * world.px:
					state = State.LYING_DOWN
					clock = 0.0
					velocity = Vector2.ZERO
		State.LYING_DOWN:
			velocity = Vector2.ZERO
			clock += delta * float(s.lieDownFps)
			var f := floori(clock)
			_show_sleep(mini(f, SETTLED))
			if f >= SETTLED:
				state = State.SLEEP
				next_z = t + 1.0
			if not _night() or (player_out and to_player.length() < 0.9 * world.px):
				_get_up(false)
		State.SLEEP:
			_sleep(t, to_player, player_out)
		State.GETTING_UP:
			velocity = Vector2.ZERO
			clock -= delta * float(s.getUpFps)
			_show_sleep(clampi(ceili(clock), 0, SETTLED))
			if clock <= 0.0:
				_wake()
				if charge_on_waking:
					_begin_wind_up()
	# Never into the water: a step that would end in the river stops at the bank.
	if velocity != Vector2.ZERO and world.wet(position + velocity * get_physics_process_delta_time() * 4.0):
		velocity = Vector2.ZERO
	slide()
	paint_flash(Color(1, 0.75, 0.72))


# Head down in the grass, nibbling: a small bob, then off to another patch.
func _graze(t: float) -> void:
	velocity = Vector2.ZERO
	_show(0, 0.97 if sin(t * 5.0 + home.x / world.px) > 0.6 else 1.0)
	if t >= state_until:
		if _pick_grass():
			state = State.WALK
			clock = 0.0
		else:
			state_until = t + randf_range(1.0, 3.0)


func _walk(t: float, speed: float, delta: float) -> void:
	var dir := target - position
	if dir.length() < 0.2 * world.px:
		velocity = Vector2.ZERO
		if state == State.WALK:
			state = State.GRAZE
			state_until = t + randf_range(2.5, 6.0)
		return
	face(dir, 0.15)
	clock += delta * float(s.walkFps) * (speed / float(s.walkSpeed))
	_show(WALK_FRAMES[floori(clock) % WALK_FRAMES.size()])
	var v := dir.normalized() * speed * world.px
	if world.village.contains(position + v * 0.3, 0.3):
		v = Vector2.ZERO
		if state == State.WALK:
			_pick_grass()
	v = steer.around(v, delta)
	if steer.stuck:
		_unstick()
	velocity = v


# Couldn't get where it was going: somewhere else to graze, another bed, or (after a few tries) bed down right here.
func _unstick() -> void:
	if state == State.WALK:
		if not _pick_grass():
			state = State.GRAZE
			state_until = now() + randf_range(1.0, 2.0)
		return
	if state != State.TO_BED:
		return
	bed_tries += 1
	if bed_tries <= 3:
		var other: Variant = Wilds.forest(world, position)
		if other != null:
			bed = other
			return
	bed = position
	state = State.LYING_DOWN
	clock = 0.0
	velocity = Vector2.ZERO


func _begin_wind_up() -> void:
	state = State.WIND_UP
	state_until = now() + float(s.windUp)
	velocity = Vector2.ZERO
	if warn == null:
		warn = Telegraph.make(world, 0.75)
	var p: Node2D = hunted_by() if hunted_by() != null else player()
	var to := (p.position - position) if p != null and p.position.distance_squared_to(position) > 1.0 else charge_dir
	warn.point(position, position + to.normalized() * _charge_reach(), _charge_reach())


# How far a charge goes (px).
func _charge_reach() -> float:
	return float(s.chargeSpeed) * float(s.chargeFor) * world.px


func _exit_tree() -> void:
	super._exit_tree()
	_clear_warn()


func _clear_warn() -> void:
	if warn != null:
		warn.queue_free()
		warn = null


# Pawing the ground, facing her, a little dust kicked up behind.
func _wind_up(t: float, to_player: Vector2) -> void:
	velocity = Vector2.ZERO
	face(to_player, 0.15)
	_show(0 if floori(t * 10.0) % 2 == 0 else 1)
	art.position.x = sin(t * 60.0) * 0.02 * world.px
	if randf() < 0.3:
		_puff()
	# The strip on the ground: following her, then set a moment before it goes; filling as it does.
	if warn != null:
		if t < state_until - AIM_LOCK and to_player.length_squared() > 0.01 * world.px * world.px:
			warn.point(position, position + to_player.normalized() * _charge_reach(), _charge_reach())
		warn.set_fill(1.0 - (state_until - t) / maxf(0.01, float(s.windUp)))
	if t < state_until:
		return
	art.position.x = 0.0
	charge_dir = warn.dir if warn != null else (to_player.normalized() if to_player.length_squared() > 0.01 * world.px * world.px else (Vector2.RIGHT if flip else Vector2.LEFT))
	_clear_warn()
	state = State.CHARGE
	state_until = t + float(s.chargeFor)
	hit_this_charge = false
	clock = 0.0
	dust.emitting = true


func _puff() -> void:
	dust.emitting = true
	get_tree().create_timer(0.05).timeout.connect(func(): if is_instance_valid(self) and state == State.WIND_UP: dust.emitting = false)


func _charge(t: float, to_player: Vector2, delta: float) -> void:
	face(charge_dir, 0.15)
	clock += delta * float(s.chargeFps)
	_show(1 + floori(clock) % 12)
	var v := charge_dir * float(s.chargeSpeed) * world.px
	var blocked := world.village.contains(position + v * 0.15, 0.2)
	# Into a barricade: a heavy blow to it, and the charge ends there.
	var bar := world.walls.barricade_in_way(position, position + charge_dir * 0.7 * world.px, 0.5 * world.px) if world.walls != null and not world.walls.hp.is_empty() else []
	if not bar.is_empty() and not hit_this_charge:
		hit_this_charge = true
		world.walls.damage(bar[0], float(s.damage) * 3.0)
		blocked = true
	velocity = Vector2.ZERO if blocked else v
	# Connects: hurts her and throws her back along the charge, up off her feet in an arc.
	var p := player()
	var h := hunted_by()
	if h != null:
		# (into its hunter: hurt, and the charge ends there)
		if not hit_this_charge and to_player.length() < 0.7 * world.px:
			hit_this_charge = true
			h.hit.hurt(float(s.damage))
			state_until = minf(state_until, t + 0.12)
	elif not hit_this_charge and p != null and p.stats != null and p.stats.hp > 0.0 and to_player.length() < 0.7 * world.px:
		hit_this_charge = true
		hurt_player(float(s.damage), charge_dir * float(s.knockback) * world.px, float(s.tossTime))
		p.toss(float(s.tossHeight), float(s.tossTime))
		state_until = minf(state_until, t + 0.12)
	if t >= state_until or blocked:
		dust.emitting = false
		velocity = Vector2.ZERO
		state = State.RECOVER
		state_until = t + randf_range(1.1, 1.8)


func _go_to_bed() -> void:
	var spot: Variant = Wilds.forest(world, position)
	if spot == null:
		state = State.GRAZE
		state_until = now() + 5.0
		return
	bed = spot
	state = State.TO_BED
	clock = 0.0
	bed_tries = 0
	steer.reset()


# Curled up under the trees: still, breathing, the odd "z". Only someone right beside it wakes it.
func _sleep(t: float, to_player: Vector2, player_out: bool) -> void:
	velocity = Vector2.ZERO
	_show_sleep(SETTLED, 1.0 + 0.018 * sin(t * 1.6))
	if t >= next_z:
		next_z = t + 2.4
		FloatingText.spawn(world, "z", position + Vector2((0.3 if flip else -0.3) * world.px, -0.7 * world.px), Color(0.78, 0.84, 1.0))
	if not _night() or (player_out and to_player.length() < 0.9 * world.px):
		_get_up(false)


# Up from lying down (the lying-down frames backwards), quicker when startled; then it charges if it was.
func _get_up(startled: bool) -> void:
	charge_on_waking = startled
	if state == State.SLEEP:
		clock = SETTLED
	state = State.GETTING_UP


func _wake() -> void:
	home = position
	state = State.GRAZE
	state_until = now() + randf_range(0.5, 2.0)


# Another grassy patch close by, out of the village.
func _pick_grass() -> bool:
	for i in 10:
		var r := Vector2.from_angle(randf() * TAU) * sqrt(randf()) * 3.0 * world.px
		var spot := home + Vector2(r.x, r.y * 0.5)
		if Wilds.vegetation(world, spot) and Wilds.open(world, spot, 1.0, 0.3) and Wilds.dry_way(world, position, spot):
			target = spot
			return true
	return false


func _show(frame: int, squash := 1.0) -> void:
	var sheet: Array = s.back if facing_back else s.front
	if frame < sheet.size():
		show_art(int(sheet[frame]), squash)


func _show_sleep(frame: int, squash := 1.0) -> void:
	var sheet: Array = s.sleepBack if facing_back else s.sleepFront
	if frame >= sheet.size():
		_show(0)
		return
	show_art(int(sheet[frame]), squash)


func _hurt(_amount: float) -> void:
	flash_until = now() + 0.12
	angry_until = now() + 12.0
	if state == State.SLEEP or state == State.LYING_DOWN:
		_get_up(true)
	elif state == State.GRAZE or state == State.WALK or state == State.TO_BED:
		_wake()
		_begin_wind_up()


# No death animation: a puff of dust, and its meat and hide fly out every which way.
func _died() -> void:
	var p := player()
	if p != null and p.stats != null:
		p.stats.gain_xp(int(s.xp))
	var at := position + Vector2(0, -0.2 * world.px)
	Puffs.burst(world, at, 1.2, 28)
	for i in randi_range(1, 2):
		Pickup.launch_icon(world, "Food", 1, at, 2.2)
	Pickup.launch_icon(world, "Hide", 1, at, 2.2)
	drop_seed()
	_clear_warn()
	# The dust trail stays a moment to fade, apart from the boar.
	dust.emitting = false
	var d := dust
	remove_child(d)
	world.things.add_child(d)
	d.global_position = at
	world.get_tree().create_timer(1.5).timeout.connect(d.queue_free)
	queue_free()
