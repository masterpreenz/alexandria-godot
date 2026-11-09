class_name Shikigami
extends Damageable
## A summoned paper spirit (from Unity's Shikigami): it floats beside its summoner, bobbing and drifting from spot to
## spot, falling in behind when they walk and gliding to catch up. It lasts a while (flickering for its last couple of
## seconds) and then fades away upward; only so many follow at once (one, plus Max Summons), a new one sending the
## oldest away. Its power is raised by Summon Effect (and an attacker's by Summon Damage), its time by Summon Duration
## and its HP by Summon HP.
## - Healer: lays healing circles at its summoner's feet and circles them while they heal; its presence alone mends a
##   little faster.
## - Attacker: picks on enemies Miko has hit herself (within its leash of her), hovers round them, draws back and
##   thrusts its spear straight through; too far from her, it drops the fight and hurries back.
## - Defender: flies to where it was sent and raises a ward there (ShieldBubble).
## Its skill can start cooling down only once it's gone (cooldownAfterSummon).

static var active: Array[Shikigami] = []

var s: Dictionary                ## its settings (shikigami.json)
var kind := "Healer"
var owner_node: Node2D
var owner_stats: CharacterStats
var spell_name := ""
var caster: SpellCaster
var body: Sprite2D
var born_at := 0.0
var ends_at := 0.0
var next_act := 0.0
var dismissed_at := -1.0
var power := 0.0
var slot := 0
var foe: Damageable
var recalled := false
var velocity := Vector2.ZERO
var wander := Vector2.ZERO
var next_wander := 0.0
var last_owner := Vector2.ZERO
var owner_velocity := Vector2.ZERO
var last_pos := Vector2.ZERO
var facing_up := false
var facing_right := false
var motion := 0                  # 0 idle, 1 starting, 2 gliding, 3 stopping
var motion_at := 0.0
var healing_at := Vector2.ZERO
var healing_until := -1.0
var circles_laid := 0
var heal_loop: AudioStreamPlayer2D
var guard_at := Vector2.ZERO
var guard_radius := 0.0
var bubble: ShieldBubble
var strike := 0                  # 0 none, 1 wind-up, 2 thrust
var strike_at := 0.0
var strike_from := Vector2.ZERO
var strike_back := Vector2.ZERO
var strike_to := Vector2.ZERO
var strike_dir := Vector2.RIGHT
var strike_hit := false
var stab_sounded := false


static func now() -> float:
	return Time.get_ticks_msec() / 1000.0


## Summons the shikigami [param spell] calls for, for [param who] (Miko), at [param target] (where a ward goes).
static func summon(w: World, spell: String, settings: Dictionary, who: Node2D, stats: CharacterStats, from: SpellCaster, target: Vector2) -> Shikigami:
	var k := Shikigami.new()
	k.world = w
	k.s = settings
	k.kind = settings.kind
	k.owner_node = who
	k.owner_stats = stats
	k.spell_name = spell
	k.caster = from
	k._begin(target)
	return k


func _px(v) -> float:
	return float(v) * world.px


func _begin(target: Vector2) -> void:
	var t := owner_stats.total()
	var effect := CharacterStats.percent(float(t.get("summonEffect", 0.0)))
	power = float(s.power) * effect * (CharacterStats.percent(float(t.get("summonDamage", 0.0))) if kind == "Attacker" else 1.0)
	born_at = now()
	ends_at = born_at + float(s.lifetime) * CharacterStats.percent(float(t.get("summonDuration", 0.0)))
	next_act = born_at + (0.4 if kind == "Attacker" else 0.2)
	# Only so many at once: the oldest of this summoner's goes. (A ward isn't a follower and doesn't count.)
	if kind != "Defender":
		var cap := 1 + maxi(0, floori(float(t.get("maxSummons", 0.0)) + 0.001))
		var mine := active.filter(func(a): return is_instance_valid(a) and a.owner_stats == owner_stats and a.dismissed_at < 0.0 and a.kind != "Defender")
		for i in range(0, mine.size() - cap + 1):
			mine[i].dismiss()
	else:
		guard_at = target
		guard_radius = float(caster.spells[spell_name].aoeRadius)
	slot = active.size()
	active.append(self)
	setup(world, Damageable.Team.ALLY, float(s.hp) * CharacterStats.percent(float(t.get("summonHp", 0.0))), 0.25 * world.px, 1.1 * world.px)
	body = Sprite2D.new()
	add_child(body)
	_show(int(s.idleDown[0]) if s.idleDown.size() > 0 else -1)
	last_owner = owner_node.position
	# A ward sets off from its summoner; the others appear beside them.
	position = (owner_node.position if kind == "Defender" else _home()) + Vector2(0, -0.4 * world.px)
	last_pos = position
	world.things.add_child(self)
	# Its presence alone mends a little faster.
	if kind == "Healer" and float(s.regenBonus) > 0.0:
		owner_stats.buffs[self] = {"hpRegen": float(s.regenBonus) * effect}
		owner_stats.changed.emit()


func _show(id: int) -> void:
	if id < 0:
		return
	world.show_frame(body, id, Vector2.ONE * float(s.artScale))
	body.centered = true
	body.offset = Vector2.ZERO
	var info: Dictionary = world.sprites[id]
	# The pivot isn't always the middle: keep the art where Unity drew it.
	body.offset = Vector2(info.rect[2] * 0.5 - info.pivot[0], info.rect[3] * 0.5 - info.pivot[1])


## Sends it away (its time is up, or a newer one took its place).
func dismiss() -> void:
	if dismissed_at >= 0.0:
		return
	dismissed_at = now()
	if bubble != null and is_instance_valid(bubble):
		bubble.end()
	_drop_buff()


func _drop_buff() -> void:
	if owner_stats != null and owner_stats.buffs.has(self):
		owner_stats.buffs.erase(self)
		owner_stats.changed.emit()


func _exit_tree() -> void:
	super._exit_tree()
	active.erase(self)
	_stop_heal_loop()
	if bubble != null and is_instance_valid(bubble):
		bubble.end()
	_drop_buff()
	# Gone: now its skill starts cooling down.
	if caster != null and bool(caster.spells.get(spell_name, {}).get("cooldownAfterSummon", false)):
		caster.start_cooldown(spell_name)


func _stop_heal_loop() -> void:
	if heal_loop == null or not is_instance_valid(heal_loop):
		heal_loop = null
		return
	var p := heal_loop
	heal_loop = null
	var tw := p.create_tween()
	tw.tween_property(p, "volume_db", -40.0, 0.35)
	tw.tween_callback(p.queue_free)


func _start_heal_loop(at: Vector2) -> void:
	var path: Variant = s.get("healSound")
	if heal_loop != null and is_instance_valid(heal_loop):
		heal_loop.position = at
		return
	if path == null or not ResourceLoader.exists(path):
		return
	heal_loop = AudioStreamPlayer2D.new()
	heal_loop.stream = load(path)
	heal_loop.volume_db = linear_to_db(maxf(float(s.healVolume), 0.0001))
	heal_loop.max_distance = 3000.0
	heal_loop.attenuation = 1.5
	heal_loop.position = at
	world.add_child(heal_loop)
	heal_loop.finished.connect(func(): if heal_loop != null and is_instance_valid(heal_loop): heal_loop.play())
	heal_loop.play()


func _process(delta: float) -> void:
	var __t := Time.get_ticks_usec()
	_process_timed(delta)
	Perf.add(&"shikigami.process", __t)


func _process_timed(delta: float) -> void:
	super._process_timed(delta)
	if owner_node == null or not is_instance_valid(owner_node):
		queue_free()
		return
	var t := now()
	if heal_loop != null and (t >= healing_until or dismissed_at >= 0.0):
		_stop_heal_loop()
	if dismissed_at < 0.0 and t >= ends_at:
		dismiss()
	if dismissed_at >= 0.0:
		var k := clampf((t - dismissed_at) / 0.5, 0.0, 1.0)
		body.modulate.a = 1.0 - k
		position += Vector2(0, -1.2 * world.px * delta)
		if k >= 1.0:
			queue_free()
		return
	# The last couple of seconds it flickers, to say it's going.
	body.modulate.a = 0.55 + 0.45 * absf(sin(t * 9.0)) if ends_at - t < 2.0 else 1.0
	if delta > 0.0:
		var step := (owner_node.position - last_owner) / delta
		owner_velocity = owner_velocity.lerp(step, 1.0 - exp(-8.0 * delta))
	last_owner = owner_node.position
	var goal := _home()
	if kind == "Attacker":
		goal = _attack(t, goal)
	elif kind == "Defender":
		# Arrived: raise the ward, and hover over its middle.
		if bubble == null and position.distance_to(guard_at) < 0.2 * world.px:
			bubble = ShieldBubble.spawn(world, owner_stats, owner_node, guard_at, guard_radius, float(s.guardPercent), power, float(s.shieldFillTime), int(s.circleSprite) if s.circleSprite != null else -1, _color(s.wardTint))
	elif t >= next_act:
		next_act = t + float(s.interval)
		if kind == "Healer" and circles_laid < int(s.maxCircles) and s.circleSprite != null:
			HealingCircle.spawn(self, owner_node.position)
			circles_laid += 1
			# The circle stays where it was laid; the healer circles it until it fades.
			healing_at = owner_node.position
			healing_until = t + float(s.circleTime)
			_start_heal_loop(healing_at)
	# Eases after where it's going rather than sticking to it: it lags, speeds up and settles. (A thrust moves it itself.)
	if not (kind == "Attacker" and strike != 0):
		var walking := owner_velocity.length_squared() > 0.3 * world.px * world.px
		var eased := float(s.followEase)
		if kind == "Healer" and t < healing_until: eased = 0.12
		elif recalled: eased *= 0.5
		elif walking: eased *= 0.55
		position = _smooth_damp(position, goal, eased, _px(s.speed) * (1.6 if recalled else 1.0), delta)
	else:
		velocity = Vector2.ZERO
	# Floats and bobs; faces the way it's going.
	body.position = Vector2(0, -_px(s.floatHeight) - sin((t - born_at) * 3.0 + slot) * 0.08 * world.px)
	var moved := position - last_pos
	if absf(moved.x) > 0.002 * world.px: facing_right = moved.x > 0.0
	if absf(moved.y) > 0.002 * world.px: facing_up = moved.y < 0.0
	# Fighting, it keeps its face (and spear) to its target; striking, to the line of its thrust.
	if kind == "Attacker" and foe != null and is_instance_valid(foe) and not recalled:
		var to := strike_dir if strike != 0 else foe.global_position - position
		facing_right = to.x > 0.0
		facing_up = to.y < -0.05 * world.px
	var pose: Array = []
	if strike != 0:
		pose = s.thrustUp if facing_up and s.thrustUp.size() > 0 else s.thrustDown
	if pose.size() > 0:
		_show(int(pose[floori((t - strike_at) * float(s.fps)) % pose.size()]))
		body.flip_h = facing_right  # the thrust pose faces left
	else:
		var f := _frame(t, position.distance_to(goal), t < healing_until)
		if f >= 0:
			_show(f)
			body.flip_h = not facing_right if s.artFacesRight else facing_right
	last_pos = position


# Unity's SmoothDamp: a critically damped spring after the goal, capped in speed.
func _smooth_damp(from: Vector2, to: Vector2, smooth: float, max_speed: float, dt: float) -> Vector2:
	smooth = maxf(0.0001, smooth)
	var omega := 2.0 / smooth
	var x := omega * dt
	var e := 1.0 / (1.0 + x + 0.48 * x * x + 0.235 * x * x * x)
	var change := (from - to).limit_length(max_speed * smooth)
	var goal := from - change
	var temp := (velocity + omega * change) * dt
	velocity = (velocity - omega * temp) * e
	var out := goal + (change + temp) * e
	# Don't overshoot.
	if (to - from).dot(out - to) > 0.0:
		out = to
		velocity = (out - to) / dt if dt > 0.0 else Vector2.ZERO
	return out


# Idle, or gliding: leans into a glide when it falls behind, loops it while catching up, and settles back once there.
func _frame(t: float, behind: float, keep_gliding: bool) -> int:
	var glide: Array = s.glideUp if facing_up and s.glideUp.size() > 0 else s.glideDown
	var idle: Array = s.idleUp if facing_up and s.idleUp.size() > 0 else s.idleDown
	var start := int(s.glideStartFrames)
	var loop := int(s.glideLoopFrames)
	var gfps := float(s.glideFps)
	var can_glide := glide.size() > start + loop
	var threshold := float(s.glideFrom) if motion == 0 or motion == 3 else float(s.glideUntil)
	var moving := keep_gliding or behind > threshold * world.px
	var frame := floori((t - motion_at) * gfps)
	if not can_glide:
		motion = 0
	else:
		match motion:
			0:
				if moving: _go(1, t)
			1:
				if not moving: _go(3, t)
				elif frame >= start: _go(2, t)
			2:
				if not moving: _go(3, t)
			3:
				if moving: _go(1, t)
				elif frame >= glide.size() - start - loop: _go(0, t)
	frame = floori((t - motion_at) * gfps)
	match motion:
		1: return int(glide[mini(frame, start - 1)])
		2:
			var hold := int(s.glideHoldFrame)
			return int(glide[hold]) if hold >= 0 and hold < glide.size() else int(glide[start + frame % loop])
		3: return int(glide[mini(start + loop + frame, glide.size() - 1)])
	return int(idle[floori((t - born_at) * float(s.fps)) % idle.size()]) if idle.size() > 0 else -1


func _go(next: int, t: float) -> void:
	motion = next
	motion_at = t


# Beside the summoner: each one its own spot around them; a healer circles its circle while it heals.
func _home() -> Vector2:
	if kind == "Defender":
		return guard_at
	if kind == "Healer" and now() < healing_until:
		var c := deg_to_rad((now() - born_at) * float(s.circleOrbitSpeed) + slot * 120.0)
		var ring := maxf(0.2, float(s.circleRadius) - float(s.circleOrbitInset)) * world.px
		return healing_at + Vector2(cos(c) * ring, -sin(c) * ring * 0.5)
	return owner_node.position + _wander()


# Its spot beside the summoner, which it keeps changing: every few seconds another (to one side, a different distance);
# when the summoner walks off it falls in behind them; and it drifts about the spot too.
func _wander() -> Vector2:
	var t := now()
	var moving := owner_velocity.length_squared() > 0.3 * world.px * world.px
	var ahead := moving and wander.normalized().dot(owner_velocity.normalized()) > 0.15  # in the way: drop back
	if t >= next_wander or wander == Vector2.ZERO or ahead:
		var angle: float
		if moving:
			angle = atan2(-owner_velocity.y, -owner_velocity.x) + randf_range(-1.1, 1.1)
		else:
			angle = (0.0 if randf() < 0.5 else PI) + randf_range(-1.2, 1.2) + slot * 0.7
		var fr := float(s.followRadius)
		var dist := (randf_range(0.45, fr * 0.7) if moving else randf_range(0.65, fr)) * world.px
		wander = Vector2(cos(angle) * dist, sin(angle) * dist * 0.5)
		var every := float(s.wanderEvery)
		next_wander = t + randf_range(every * 0.6, every * 1.4)
	# A slow drift about it, so it never quite holds still.
	var a := t * 0.6 + slot * 11.0
	var drift := Vector2(sin(a * 1.3) * 0.5 + sin(a * 0.71 + 2.0) * 0.5, (sin(a * 0.9 + 1.0) * 0.5 + sin(a * 1.7) * 0.5) * 0.5) * 0.25 * world.px
	return wander + drift


# Follows its summoner; picks on an enemy Miko has hit, hovers round it striking every so often; and if the summoner
# gets too far away, drops everything and goes back to them (picking no fight until it's caught up).
func _attack(t: float, home: Vector2) -> Vector2:
	var o := owner_node.position
	var d := o - position
	var from_owner := Vector2(d.x, d.y * 2.0).length()
	var leash := _px(s.leash)
	if recalled:
		if from_owner > 1.5 * world.px:
			return home
		recalled = false
	if from_owner > leash:
		recalled = true
		foe = null
		strike = 0
		return home
	if foe == null or not is_instance_valid(foe) or not foe.alive() or foe.ground_distance(o) > leash:
		# Only what Miko has attacked herself: neutral monsters are left alone until she starts the fight.
		foe = null
		var best := _px(s.reach)
		for e in Damageable.all:
			if e.team == Damageable.Team.ENEMY and e.alive() and e.hit_by_player:
				var g := e.ground_distance(position)
				if g < best and e.ground_distance(o) <= leash:
					best = g
					foe = e
	if foe == null:
		strike = 0
		return home
	if strike != 0:
		return _striking(t)
	var a := deg_to_rad((t - born_at) * float(s.hoverSpeed) + slot * 120.0)
	var ring := foe.radius + _px(s.hoverRadius)
	var spot := foe.global_position + Vector2(cos(a) * ring, -sin(a) * ring * 0.5)
	if position.distance_to(spot) < 0.4 * world.px and t >= next_act:
		# Draws back along the line to the target, to charge.
		strike = 1
		strike_at = t
		strike_from = position
		var to := foe.global_position - position
		strike_dir = to.normalized() if to.length_squared() > 1.0 else Vector2.RIGHT
		strike_back = strike_from - strike_dir * _px(s.windBack)
		stab_sounded = false
		return _striking(t)
	return spot


# The attack, moving it itself: glides back while it charges (easing to a stop, a little shake at the end), then shoots
# straight through the target, a slash streaking along the line, carrying on a little past.
func _striking(t: float) -> Vector2:
	var e := t - strike_at
	var wind := float(s.windTime)
	if strike == 1:
		var k := clampf(e / wind, 0.0, 1.0)
		var eased := 1.0 - (1.0 - k) * (1.0 - k)
		var shake := Vector2.from_angle(randf() * TAU) * randf() * 0.025 * world.px if k > 0.7 else Vector2.ZERO
		position = strike_from.lerp(strike_back, eased) + shake
		if not stab_sounded and e >= wind - float(s.stabLead):
			stab_sounded = true
			if s.stabSound != null:
				SpellEffects.sound(world, s.stabSound, position, float(s.stabVolume))
		if k >= 1.0:
			strike = 2
			strike_at = t
			strike_hit = false
			# Aimed afresh at where the target is now, carrying through past it.
			var to := foe.global_position - strike_back
			if to.length_squared() > 1.0:
				strike_dir = to.normalized()
			strike_to = foe.global_position + strike_dir * (foe.radius + _px(s.followThrough))
			strike_from = strike_back
			var lift := Vector2(0, -_px(s.floatHeight))
			SpearThrust.play(world, strike_from + lift, strike_to + lift)
		return position
	var p := clampf(e / maxf(0.01, float(s.thrustTime)), 0.0, 1.0)
	position = strike_from.lerp(strike_to, 1.0 - pow(1.0 - p, 3.0))
	if not strike_hit and p >= 0.45:
		strike_hit = true
		if is_instance_valid(foe):
			foe.hurt(power)
	if p >= 1.0:
		strike = 0
		next_act = t + float(s.interval)
	return position


## Heals the summoner and every ally standing within [param r] (px) of [param at], each showing a green number.
func heal_around(at: Vector2, r: float) -> void:
	if owner_stats == null:
		return
	var d := owner_node.position - at
	if Vector2(d.x, d.y * 2.0).length() <= r:
		var before := owner_stats.hp
		owner_stats.heal(power)
		_show_heal(owner_stats.hp - before, owner_node.position + Vector2(0, -0.8 * world.px))
	for a in Damageable.all.duplicate():
		if is_instance_valid(a) and a.team == Damageable.Team.ALLY and a.alive() and a.ground_distance(at) <= r:
			var b: float = a.hp
			a.heal(power)
			_show_heal(a.hp - b, a.global_position + Vector2(0, -a.height * 0.6))


func _show_heal(healed: float, at: Vector2) -> void:
	if healed >= 0.5:  # already full: nothing healed, nothing shown
		FloatingText.spawn(world, "+%d" % maxi(1, roundi(healed)), at, Color(0.5, 1.0, 0.5))


static func _color(c: Array) -> Color:
	return Color(c[0], c[1], c[2], c[3])
