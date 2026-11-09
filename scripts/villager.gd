class_name Villager
extends CharacterBody2D
## A villager (from Unity's Villager). Each bed in a house in the village has one living in it (Villagers): a person
## with a level, HP, attack and skills, who gets hungry and tired. Their day: up at 6, about the village till 21
## (strolling, chatting with each other in the evening), then home to bed (earlier when worn out), getting up again in
## the morning. If Miko has taken their bed they wait beside it, and get up if she lies down in it while they sleep.
## Hungry, they go to a chest and take the most filling food in storage, and eat it out in the open; with none they
## starve, losing HP. HP comes back as they sleep. At 0 HP they die, and their bed waits for a newcomer.
##
## They find their way round walls (VillagerRoute), opening shut doors on the way and shutting them behind them; at
## bedtime the doors of their house are shut, and houses kept open are opened in the morning by one of them. A slime
## that gets into the village near one (or near home) is met with a spear until it's gone or out again. What they're
## doing shows over their head (eating, hungry, sleepy, sick...), and chats are little picture bubbles.
##
## Art: idle is one frame each facing down-left and up-left; the walk a strip each way; drawn facing left, mirrored for
## the right. (Their work comes in the next step.)

enum State { STAND, WALK, HOME, ASLEEP, FIGHT, TO_EAT, TO_MEAL, EATING, TO_CHAT, CHAT, CHAT_WAIT, TO_DOOR }

const FOODS := [["CarrotStew", 55.0], ["CabbageSoup", 50.0], ["Meal", 60.0], ["BakedPotato", 45.0], ["Bread", 40.0],
	["Candy", 35.0], ["Food", 20.0], ["Cabbage", 15.0], ["Carrot", 12.0], ["Potato", 10.0]]
const EMOTE_FPS := 5.0
const BOB_HEIGHT := 0.045
const BOB_SPEED := 4.0
const EMOTE_WIDTH := 0.66

static var all: Array[Villager] = []
static var door_keeper: Villager

var world: World
var people: Villagers
var s: Dictionary                 ## this look's settings (villagers.json)
var look: Dictionary
var person: Dictionary            ## who they are (Villagers.Person): name, level, hp, skills, hunger, energy...
var home: Dictionary = {}         ## their bed (Needs.all_beds' entry), or {} (waiting for one)
var art: Sprite2D
var shadow: Sprite2D
var emote: Sprite2D
var bubble: Sprite2D
var hit: Damageable
var steer: Steer
var shape: CircleShape2D
var outline: OccludedOutline
var state := State.STAND
var state_until := 0.0
var clock := 0.0
var facing_up := false
var facing_right := false
var target := Vector2.ZERO
var route: Variant = null          ## the way there round walls (VillagerRoute points), or null: straight there
var leg := 0
var in_bed := false
var sleep_clock := 0.0
var next_z := 0.0
var meal := ""
var foe: Damageable
var next_look := 0.0
var next_chase := 0.0
var stab_clock := 0.0
var last_frame := -1
var partner: Villager
var chat_until := 0.0
var speak_phase := 0.0
var last_emoji := -1
var bubble_frames: Array = []
var bubble_start := 0.0
var duty_door: WallMap.Edge
var duty_opens := false
var _close_door := false
var _door_to_close: WallMap.Edge
var _close_at := 0
var _door_wait := -1.0
var _last_hours := -1.0
var _awake_hours := 0.0
var _stuck_from := Vector2.ZERO
var _trying_for := 0.0
var _last_stuck := -999.0
var _stuck_times := 0
var _next_wall_check := 0.0


static func now() -> float:
	return Time.get_ticks_msec() / 1000.0


func setup(w: World, vs: Villagers, l: Dictionary, who: Dictionary, bed: Dictionary) -> void:
	world = w
	people = vs
	look = l
	s = l.settings
	person = who
	home = bed
	name = str(who.name)
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	collision_layer = 8          # villagers: they walk through each other, Miko and the creatures
	collision_mask = 1
	var c := CollisionShape2D.new()
	shape = CircleShape2D.new()
	shape.radius = float(l.collider.r) if l.has("collider") else 18.0
	c.shape = shape
	c.position = Vector2(l.collider.x, l.collider.y) if l.has("collider") else Vector2.ZERO
	add_child(c)
	if l.has("shadow"):
		shadow = Sprite2D.new()
		world.show_frame(shadow, int(l.shadow.s), Vector2(l.shadow.sx, l.shadow.sy))
		shadow.position = Vector2(l.shadow.x, l.shadow.y)
		shadow.modulate.a = l.shadow.a
		add_child(shadow)
	art = Sprite2D.new()
	add_child(art)
	steer = Steer.new(self, shape, c.position, 0.35 * world.px)
	facing_right = randf() < 0.5
	# They can be hurt: HP from who they are.
	hit = Damageable.new()
	hit.name = "Hit"
	add_child(hit)
	hit.setup(world, Damageable.Team.ALLY, float(who.get("maxHp", 40.0)), 0.18 * world.px, 0.9 * world.px)
	hit.hp = clampf(float(who.get("hp", hit.max_hp)), 1.0, hit.max_hp)
	hit.damaged.connect(func(_a):
		person.hp = hit.hp
		VillageLog.event("hurt:" + name, "%s is under attack!" % name, VillageLog.Kind.DANGER))
	hit.died.connect(func():
		person.hp = 0.0
		VillageLog.event("died:" + name, "%s has died" % name, VillageLog.Kind.DANGER)
		move_out())
	var wade := Wading.new()
	wade.name = "Wading"
	add_child(wade)
	wade.setup(world, self, art, shadow)
	outline = OccludedOutline.new()
	outline.name = "OccludedOutline"
	outline.fade_covers = false
	add_child(outline)
	outline.setup(world, art, Color(0.45, 0.7, 1.0, 1.0))
	position = _door() if not home.is_empty() else position
	_show_idle()
	state_until = now() + randf_range(0.5, 2.0)
	world.things.add_child(self)


func _enter_tree() -> void:
	all.append(self)


func _exit_tree() -> void:
	all.erase(self)
	if partner != null and is_instance_valid(partner) and partner.partner == self:
		partner.partner = null
	if door_keeper == self:
		door_keeper = null


## Leaves (their bed or house is gone, or they died): just vanishes for now.
func move_out() -> void:
	if in_bed and Needs.occupants.get(Needs.bed_key(home.pos)) == self:
		Needs.occupants.erase(Needs.bed_key(home.pos))
	queue_free()


# ---- The clock ----

static func _hour(w: World) -> float:
	return w.clock.hour() if w.clock != null else 12.0


# Time to get up: morning (6 to 18) unless worn right out; gone to bed early (tired, from 18), not till well rested.
func _wake_time() -> bool:
	var h := _hour(world)
	var energy := float(person.get("energy", 100.0))
	if h < 6.0 or h >= 21.0 or energy < 20.0:
		return false
	return h < 18.0 or energy >= 60.0


# Bedtime: 21 to 6, or from 18 when worn out (and any time when exhausted).
func _night() -> bool:
	var h := _hour(world)
	var tired := float(person.get("energy", 100.0))
	return h >= 21.0 or h < 6.0 or (tired < 25.0 and h >= 18.0) or tired < 5.0


func _work_hours() -> bool:
	var h := _hour(world)
	return h >= 6.0 and h < 18.0


## Bedtime to morning (21 to 6): every door shut, even in houses kept open.
static func sleep_hours(w: World) -> bool:
	var h := _hour(w)
	return h >= 21.0 or h < 6.0


func _hungry() -> bool:
	return float(person.get("hunger", 100.0)) < 35.0


# ---- Each tick ----

func _physics_process(delta: float) -> void:
	var t := now()
	_needs()
	_unstick(t, delta)
	_close_behind()
	_status()
	# A slime about: go for it (unless asleep, or already at one).
	if state != State.ASLEEP and state != State.FIGHT and t >= next_look:
		next_look = t + 0.5
		var threat := _threat()
		if threat != null:
			_fight(threat)
	match state:
		State.STAND:
			velocity = Vector2.ZERO
			if _night() and not home.is_empty():
				_go_home()
			elif t >= state_until:
				if _hungry() and _go_eat(): pass
				elif _go_door_duty(): pass
				elif not _work_hours() and not _night() and randf() < 0.45 and _go_chat(t): pass
				elif _pick_spot():
					state = State.WALK
					clock = 0.0
				else:
					state_until = t + randf_range(1.0, 3.0)
		State.WALK:
			if _night() and not home.is_empty(): _go_home()
			else: _walk(t, delta)
		State.HOME, State.TO_EAT, State.TO_MEAL:
			_walk(t, delta)
		State.TO_DOOR:
			if _night() and not home.is_empty():
				door_keeper = null
				_go_home()
			else:
				_walk(t, delta)
		State.ASLEEP:
			velocity = Vector2.ZERO
			# Morning, or Miko has lain down in their bed: up they get.
			var occupant: Variant = Needs.occupants.get(Needs.bed_key(home.pos)) if not home.is_empty() else null
			if _wake_time() or (in_bed and occupant != self):
				_wake_up(t)
			else:
				_sleeping(delta)
		State.FIGHT:
			_fighting(t, delta)
		State.EATING:
			_eating(t)
		State.TO_CHAT:
			if partner == null or not is_instance_valid(partner) or _night() or partner.partner != self: _end_chat(t)
			else: _walk(t, delta)
		State.CHAT_WAIT:
			velocity = Vector2.ZERO
			if partner == null or not is_instance_valid(partner) or _night() or partner.partner != self or t > chat_until: _end_chat(t)
			else: _face_partner()
		State.CHAT:
			_chatting(t)
	if not in_bed:
		move_and_slide()


# ---- Walking ----

# Beside the bed, where they get in and out: its way in (UseSpots), else a clear spot beside it in its room.
func _door() -> Vector2:
	if home.is_empty():
		return position
	var spot: Variant = UseSpots.bed_spot(world, home)
	return spot if spot != null else home.pos + Vector2(0, 0.35 * world.px)


func _go_home() -> void:
	state = State.HOME
	clock = 0.0
	_set_goal(_door())


## Heads for [param p], round any walls in the way.
func _set_goal(p: Vector2) -> void:
	target = p
	route = VillagerRoute.find(world, position, p)
	leg = 0


# The point to walk to now: along the route, cutting past the in-between points they can see beyond.
func _aim() -> Vector2:
	if route == null or route.is_empty():
		return target
	while leg < route.size() - 1 and not route[leg].exact and _clear(route[leg + 1].at):
		leg += 1
	return route[leg].at


# Nothing fixed between here and p.
func _clear(p: Vector2) -> bool:
	var q := PhysicsShapeQueryParameters2D.new()
	var c := CircleShape2D.new()
	c.radius = 0.15 * world.px
	q.shape = c
	q.transform = Transform2D(0.0, position)
	q.motion = p - position
	q.collision_mask = 1
	var r := get_world_2d().direct_space_state.cast_motion(q)
	return r.size() == 0 or r[0] >= 1.0


# A shut door on the way: they stop at it a moment, open it, go through, and shut it behind them. True while stopped.
func _doors(t: float) -> bool:
	var walls := world.walls
	if walls == null or route == null or leg >= route.size():
		return false
	var here: Dictionary = route[leg]
	if not here.door or not VillagerRoute.is_closed_door(walls, here.door_edge) or position.distance_to(here.at) > 0.6 * world.px:
		_door_wait = -1.0
		return false
	if _door_wait < 0.0:
		_door_wait = t + 0.35  # reaching for the handle
	if t < _door_wait:
		velocity = Vector2.ZERO
		_show_idle()
		return true
	_door_wait = -1.0
	walls.toggle(here.door_edge)
	_close_door = true
	_door_to_close = here.door_edge
	_close_at = leg + 2
	return false


# The door they opened, shut once they're clear of it: never on themselves or anyone else in the doorway; left open if
# it's since been set to stay open.
func _close_behind() -> void:
	if not _close_door:
		return
	var walls := world.walls
	if walls == null or not VillagerRoute.is_open_door(walls, _door_to_close) or walls.kept_open(_door_to_close):
		_close_door = false
		return
	var mid := walls.edge_middle(_door_to_close)
	if _someone_near(mid, true):
		return
	_close_door = false
	walls.toggle(_door_to_close)


# Anyone in a doorway at [param mid] (themselves too, when [param me]).
func _someone_near(mid: Vector2, me: bool) -> bool:
	if me and position.distance_to(mid) < 1.0 * world.px:
		return true
	if world.player != null and world.player.position.distance_to(mid) < 0.9 * world.px:
		return true
	for v in all:
		if v != self and v.position.distance_to(mid) < 0.7 * world.px:
			return true
	return false


func _walk(t: float, delta: float) -> void:
	if _doors(t):
		return
	var aim := _aim()
	var dir := aim - position
	var last: bool = route == null or leg >= route.size() - 1
	var near := 0.12 if last or route[leg].exact else 0.35
	if dir.length() < near * world.px:
		if not last:
			leg += 1
			return
		_arrive(t)
		return
	if dir.y < -0.02 * world.px: facing_up = true
	elif dir.y > 0.02 * world.px: facing_up = false
	if dir.x > 0.02 * world.px: facing_right = true
	elif dir.x < -0.02 * world.px: facing_right = false
	clock += delta
	var frames: Array = s.walkUp if facing_up else s.walkDown
	if not frames.is_empty():
		_show(int(frames[int(clock * float(s.walkFps)) % frames.size()]))
	var speed := float(s.walkSpeed) * world.px
	var v := dir.normalized() * minf(speed, dir.length() / maxf(delta, 0.001))
	v = steer.around(v, delta)
	if steer.stuck:
		# Nearly home but can't quite reach: in they go anyway. Otherwise, somewhere else.
		if state == State.HOME and last and dir.length() < 1.2 * world.px:
			_arrive(t)
			return
		if state == State.HOME:
			_set_goal(_door())
			return
		if state == State.WALK and not _pick_spot():
			_stand(t, 1.0)
			return
		if last and dir.length() < 0.6 * world.px and state != State.WALK:
			_arrive(t)
			return
	velocity = v


func _arrive(t: float) -> void:
	velocity = Vector2.ZERO
	match state:
		State.TO_EAT: _eat(t)
		State.TO_MEAL: _start_eating(t)
		State.TO_DOOR: _see_to_door(t)
		State.TO_CHAT: _start_chat(t)
		State.HOME:
			# Into bed, unless Miko's in it: then they wait beside it till morning.
			if not home.is_empty() and not Needs.occupants.has(Needs.bed_key(home.pos)):
				_go_to_sleep()
			else:
				_stand(t, 5.0)
		_:
			_stand(t, randf_range(2.0, 6.0))


func _going() -> bool:
	return state in [State.WALK, State.HOME, State.TO_EAT, State.TO_MEAL, State.TO_CHAT, State.TO_DOOR]


# Time spent trying to get somewhere adds up until they get more than a step from where it started. Five seconds of
# that: they give up and do something else; stuck again soon after, or walled in, they hop free by the banner.
func _unstick(t: float, delta: float) -> void:
	if position.distance_to(_stuck_from) > 0.6 * world.px:
		_stuck_from = position
		_trying_for = 0.0
		return
	if not _going():
		return
	_trying_for += delta
	var walled_in := false
	if t >= _next_wall_check:
		_next_wall_check = t + 3.0
		var c := world.village.centre()
		walled_in = world.walls != null and world.village.founded() and position.distance_to(c) < 25.0 * world.px \
			and VillagerRoute.find(world, position, c) == null
	if _trying_for < 5.0 and not walled_in:
		return
	_trying_for = 0.0
	_stuck_times = _stuck_times + 1 if t - _last_stuck < 60.0 else 1
	_last_stuck = t
	if state == State.HOME and not home.is_empty():
		# Can't get to bed: straight into it.
		if _stuck_times >= 2 or walled_in:
			_hop_to(_door())
			_arrive(t)
		else:
			_set_goal(_door())
		return
	if state == State.TO_CHAT:
		_end_chat(t)
	else:
		_stand(t, randf_range(0.5, 1.5))
	if _stuck_times >= 2 or walled_in:
		_hop_to(_clear_spot_by_banner())


func _hop_to(at: Vector2) -> void:
	Puffs.burst(world, position + Vector2(0, -0.3 * world.px), 0.6, 8)
	position = at
	velocity = Vector2.ZERO
	Puffs.burst(world, at + Vector2(0, -0.3 * world.px), 0.6, 8)
	_stuck_from = at
	_stuck_times = 0
	route = null
	target = at
	reset_physics_interpolation()


func _clear_spot_by_banner() -> Vector2:
	var c := world.village.centre() if world.village.founded() else Vector2.ZERO
	for i in 30:
		var r := Vector2.from_angle(randf() * TAU) * sqrt(randf()) * (1.2 + i * 0.15) * world.px
		var at := c + Vector2(r.x, r.y * 0.5 + 0.8 * world.px)
		if Wilds.open(world, at, -999.0, 0.25) and VillagerRoute.find(world, at, c + Vector2(0, 0.8 * world.px)) != null:
			return at
	return c + Vector2(0, 0.9 * world.px)


func _stand(t: float, seconds: float) -> void:
	state = State.STAND
	state_until = t + seconds
	velocity = Vector2.ZERO
	_show_idle()


func _show(id: int) -> void:
	var k := _scale()
	world.show_frame(art, id, Vector2(-k if facing_right else k, k))


# How big they're drawn: their look's scale (villagers are scaled to Miko's size, as she is).
func _scale() -> float:
	return float(look.get("scale", 1.0))


func _show_idle() -> void:
	_show(int(s.idleUp if facing_up else s.idleDown))


# Somewhere to wander to: out in the open (not indoors), near where they are or about the village's middle, on cleared
# ground, and somewhere they can get to.
func _pick_spot() -> bool:
	var v := world.village
	for i in 10:
		var around := v.centre() if i % 2 == 0 and v.founded() else position
		var r := Vector2.from_angle(randf() * TAU) * sqrt(randf()) * float(s.roam) * world.px
		var p := around + r
		if v.founded() and not v.contains(p, -0.6):
			continue
		if world.water_depth(p) > 0.01:
			continue
		if world.roofs != null and world.roofs.room_on(p) != null:
			continue
		if not Wilds.open(world, p, -999.0, 0.25):
			continue
		if not _safe_way_to(p):
			continue
		_set_goal(p)
		return true
	return false


## Whether [param at] is clear of the mist (villagers keep to cleared ground).
static func safe_ground(w: World, at: Vector2) -> bool:
	return w.mist == null or w.mist.tier_at(at) == Mist.Tier.CLEAR


# A way from here to [param to] on cleared ground all along (caught out in the mist, the way out of it is allowed).
func _safe_way_to(to: Vector2) -> bool:
	if not safe_ground(world, to):
		return false
	var points: Array = [position]
	var way: Variant = VillagerRoute.find(world, position, to) if world.walls != null else null
	if world.walls != null and way == null:
		return false
	if way != null:
		for p in way:
			points.append(p.at)
	else:
		points.append(to)
	var on_clear := safe_ground(world, position)
	for i in range(1, points.size()):
		var a: Vector2 = points[i - 1]
		var b: Vector2 = points[i]
		var steps := maxi(1, ceili(a.distance_to(b) / (0.4 * world.px)))
		for k in range(1, steps + 1):
			var safe := safe_ground(world, a.lerp(b, k / float(steps)))
			if safe: on_clear = true
			elif on_clear: return false
	return true


# ---- Sleep ----

func _sleep_frames() -> Array:
	var up: Array = s.sleepUp
	return up if facing_up and up.size() > int(s.lieDownFrames) else s.sleepDown


func _go_to_sleep() -> void:
	state = State.ASLEEP
	_shut_house()
	var frames: Array = s.sleepDown
	if frames.size() <= int(s.lieDownFrames) or home.is_empty():
		visible = false
		return
	# Onto the bed, facing its foot, head on the pillow (as Miko lies in one).
	var turn := int(home.e.turn)
	facing_right = turn == 1 or turn == 2
	facing_up = turn >= 2
	var lying: Variant = look.get("lying", {}).get("sleepUp" if facing_up else "sleepDown")
	position = Needs.fit_on_bed(world, home, lying, facing_right, 1.0)
	reset_physics_interpolation()
	collision_layer = 0
	if shadow != null:
		shadow.visible = false
	Needs.occupants[Needs.bed_key(home.pos)] = self
	in_bed = true
	z_index = 1   # drawn over the bed
	sleep_clock = 0.0


# Lying down, then breathing slowly in their sleep; a "z" floating up now and then.
func _sleeping(delta: float) -> void:
	if not in_bed:
		return
	sleep_clock += delta
	var lie := int(s.lieDownFrames)
	var lie_time := lie / float(s.lieDownFps)
	if sleep_clock > lie_time and now() >= next_z:
		next_z = now() + randf_range(1.4, 2.2)
		var head := position + Vector2((-0.2 if facing_right else 0.2) * world.px, -0.45 * world.px)
		FloatingText.spawn(world, "z" if randf() < 0.5 else "Z", head, Color(0.78, 0.84, 1.0))
	var frames := _sleep_frames()
	var down := sleep_clock * float(s.lieDownFps)
	var frame: int
	if down < lie:
		frame = int(down)
	else:
		frame = lie + int((sleep_clock - lie_time) * float(s.asleepFps)) % maxi(1, frames.size() - lie)
	_show(int(frames[clampi(frame, 0, frames.size() - 1)]))


func _wake_up(t: float) -> void:
	if in_bed:
		in_bed = false
		if Needs.occupants.get(Needs.bed_key(home.pos)) == self:
			Needs.occupants.erase(Needs.bed_key(home.pos))
		position = _door()
		reset_physics_interpolation()
		collision_layer = 8
		if shadow != null:
			shadow.visible = true
		z_index = 0
	visible = true
	facing_up = false
	_stand(t, randf_range(1.0, 3.0))


# ---- Needs ----

# Hunger falls and tiredness grows with the game's hours (more slowly asleep, when they also mend).
func _needs() -> void:
	if world.clock == null:
		return
	var h := world.clock.hours
	if _last_hours < 0.0 or h < _last_hours:
		_last_hours = h
		return
	var dh := minf(2.0, h - _last_hours)
	_last_hours = h
	if dh <= 0.0:
		return
	var p := person
	var sleeping := state == State.ASLEEP
	# A night's sleep leaves them hungry for breakfast, but never starving.
	var hunger := float(p.hunger)
	p.hunger = maxf(minf(hunger, 15.0), hunger - 7.0 * dh) if sleeping else maxf(0.0, hunger - 4.0 * dh)
	var stamina := 1.0 + 0.06 * (maxi(1, Villagers.skill(p, LifeSkills.Skill.STAMINA)) - 1)
	p.energy = clampf(float(p.energy) + (14.0 if sleeping else -6.0 / stamina) * dh, 0.0, 100.0)
	# Long days on their feet build stamina.
	if not sleeping:
		_awake_hours += dh
		if _awake_hours >= 2.0:
			_awake_hours = 0.0
			people.practise(p, LifeSkills.Skill.STAMINA)
	if sleeping and float(p.hunger) > 0.0 and hit.hp < hit.max_hp:
		hit.heal(4.0 * dh)
	if float(p.hunger) <= 0.0:
		# Starving: HP slips away.
		var loss := 2.0 * dh
		if hit.hp - loss <= 0.5:
			hit.hurt(loss)
		else:
			hit.hp -= loss
		VillageLog.problem("starving:" + name, "%s is starving: put food in storage" % name, VillageLog.Kind.DANGER)
	p.hp = hit.hp
	if hit.alive() and hit.hp < hit.max_hp * 0.3:
		VillageLog.problem("dying:" + name, "%s is badly hurt (%d HP)" % [name, ceili(hit.hp)], VillageLog.Kind.DANGER)


func _food_in_storage() -> int:
	var n := 0
	for f in FOODS:
		n += world.village.stored(f[0])
	return n


# Off to the nearest chest in the village, if there's food in storage.
func _go_eat() -> bool:
	if _food_in_storage() == 0:
		VillageLog.problem("no-food", "No food in storage: the villagers are hungry")
		return false
	var spot: Variant = UseSpots.nearest_chest_spot(world, position)
	if spot == null:
		return false
	state = State.TO_EAT
	clock = 0.0
	_set_goal(spot)
	return true


# At the chest: the most filling thing in storage, then off somewhere out in the open to eat it.
func _eat(t: float) -> void:
	var took := false
	for f in FOODS:
		if world.village.take_from_stash(f[0], 1):
			person.hunger = minf(100.0, float(person.hunger) + float(f[1]))
			meal = f[0]
			took = true
			break
	if not took:
		_stand(t, randf_range(2.0, 4.0))
		return
	if _pick_spot():
		state = State.TO_MEAL
		clock = 0.0
	else:
		_start_eating(t)


func _start_eating(t: float) -> void:
	var path: Variant = people.d.get("eatSound")
	if path is String and ResourceLoader.exists(path):
		Sfx.play(world, load(path), position, 0.6)
	state = State.EATING
	state_until = t + randf_range(5.0, 7.0)
	velocity = Vector2.ZERO
	_show_idle()


func _eating(t: float) -> void:
	velocity = Vector2.ZERO
	if t >= state_until:
		_stand(t, randf_range(1.0, 2.0))


# ---- Doors ----

# Going to bed: the doors of their house shut (not on anyone in a doorway), kept open or not.
func _shut_house() -> void:
	var walls := world.walls
	if walls == null or world.roofs == null or home.is_empty():
		return
	var room: Variant = world.roofs.room_on(home.pos)
	if room == null:
		return
	for door in VillagerRoute.doors_of(walls, room):
		if not VillagerRoute.is_open_door(walls, door):
			continue
		if not _someone_near(walls.edge_middle(door), false):
			walls.toggle(door)


# Houses set to keep their doors open stand open by day; storage houses shut from 18; every door at bedtime. One
# villager sees to it.
func _go_door_duty() -> bool:
	var walls := world.walls
	if walls == null or _night():
		return false
	if door_keeper != null and is_instance_valid(door_keeper) and door_keeper != self and door_keeper.state == State.TO_DOOR:
		return false
	for k in walls.keep_open:
		var start := WallMap.Edge.new(Vector2i(k.x, k.y), k.z == 1)
		var t: String = walls.walls.get(k, "")
		if t == "" or walls.types[t].toggle == "":
			continue
		var a := start.vertex - (Vector2i(1, 0) if start.along_y else Vector2i(0, 1))
		var b := start.vertex
		var ca := world.floors.cell_centre(a)
		var cb := world.floors.cell_centre(b)
		var kind := world.village.room_kind_at(ca)
		if kind == "":
			kind = world.village.room_kind_at(cb)
		var want := not sleep_hours(world) and (kind != "Storage" or _hour(world) < 18.0)
		if VillagerRoute.is_open_door(walls, start) == want:
			continue
		# Stand at it on the side nearer them, with a way there.
		var mid := walls.edge_middle(start)
		var side := ca if ca.distance_to(position) < cb.distance_to(position) else cb
		var spot := mid.lerp(side, 0.6)
		if VillagerRoute.find(world, position, spot) == null:
			continue
		duty_door = start
		duty_opens = want
		door_keeper = self
		state = State.TO_DOOR
		clock = 0.0
		_set_goal(spot)
		return true
	return false


func _see_to_door(t: float) -> void:
	door_keeper = null
	var walls := world.walls
	if walls != null and VillagerRoute.is_open_door(walls, duty_door) != duty_opens:
		if not _someone_near(walls.edge_middle(duty_door), false):
			walls.toggle(duty_door)
	_stand(t, randf_range(1.0, 2.0))


# ---- Emotes ----

# What they're up to or how they're doing, over their head (not while chatting): eating, hungry on the way to get
# food, sleepy on the way to bed, sick when badly hurt.
func _status() -> void:
	if bubble != null and bubble.visible:
		_emote("")
		return
	var e := ""
	match state:
		State.EATING: e = "eating"
		State.TO_EAT: e = "hungry"
		State.HOME: e = "sleepy"
		_:
			if state != State.ASLEEP and hit.hp < hit.max_hp * 0.35:
				e = "sick"
	_emote(e)


## The frame of an emote's animation showing now (160 ms a frame), or -1 if there's no art for it.
func _emote_frame(e: String) -> int:
	var frames: Array = people.d.get("emotes", {}).get(e, [])
	if frames.is_empty():
		return -1
	return int(frames[int(now() / 0.16) % frames.size()])


# An emote over their head (its art, bubble and all); for eating with no art of its own, the food in a plain bubble.
func _emote(e: String) -> void:
	var id := _emote_frame(e) if e != "" else -1
	var food := -1
	if e == "eating" and id < 0:
		id = _emote_frame("blank")
		var icon: Variant = UiKit.data.resources.get(meal, {}).get("icon")
		food = int(icon.s) if icon is Dictionary and icon.has("s") else -1
	if id < 0:
		if emote != null:
			emote.visible = false
		return
	if emote == null:
		emote = Sprite2D.new()
		emote.z_as_relative = false
		emote.z_index = 3998
		emote.add_child(Sprite2D.new())
		add_child(emote)
	emote.visible = true
	var info: Dictionary = world.sprites[id]
	var k := EMOTE_WIDTH * world.px / float(info.rect[2])
	world.show_frame(emote, id, Vector2.ONE * k * float(info.ppu) / world.px)
	emote.flip_h = not facing_right  # the tail towards their head
	var bob := sin(now() * BOB_SPEED) * BOB_HEIGHT * world.px
	emote.position = Vector2((0.24 if facing_right else -0.24) * world.px, -_top() - 0.06 * world.px + bob)
	var inner: Sprite2D = emote.get_child(0)
	inner.visible = food >= 0
	if food >= 0:
		# Chewing: a quick bob and squash.
		var chew := absf(sin(now() * 9.0))
		var fi: Dictionary = world.sprites[food]
		var fk := 0.36 * world.px / maxf(float(fi.rect[2]), float(fi.rect[3])) * float(fi.ppu) / world.px / emote.scale.x
		world.show_frame(inner, food, Vector2(fk * (1.0 + 0.08 * chew), fk * (1.0 - 0.1 * chew)))
		inner.centered = true
		inner.offset = Vector2.ZERO
		inner.position = Vector2(0, -float(info.rect[3]) * 0.6 + float(info.pivot[1]) * 0.0) + Vector2(0, 3.0 * chew)


# How tall their standing art is above their feet, px.
func _top() -> float:
	var info: Dictionary = world.sprites[int(s.idleDown)]
	return float(info.pivot[1]) * world.px / float(info.ppu) * _scale()


# ---- Chats ----

func _free() -> bool:
	return state == State.STAND or state == State.WALK


# Free time: two villagers get together and talk, in little picture bubbles.
func _go_chat(t: float) -> bool:
	if (s.emojis as Array).is_empty():
		return false
	var best: Villager = null
	var best_d := 9.0 * world.px
	for v in all:
		if v == self or v.partner != null or not v._free() or not v.visible:
			continue
		var dd := v.position.distance_to(position)
		if dd < best_d:
			best_d = dd
			best = v
	if best == null:
		return false
	partner = best
	best.partner = self
	# They wait while this one comes over.
	best.state = State.CHAT_WAIT
	best.chat_until = t + 20.0
	best.velocity = Vector2.ZERO
	state = State.TO_CHAT
	clock = 0.0
	var away := position - best.position
	_set_goal(best.position + (away.normalized() if away.length_squared() > 1.0 else Vector2.RIGHT) * 0.75 * world.px)
	return true


func _start_chat(t: float) -> void:
	if partner == null or not is_instance_valid(partner) or partner.partner != self:
		_end_chat(t)
		return
	var length := randf_range(6.0, 10.0)
	state = State.CHAT
	chat_until = t + length
	speak_phase = 0.0
	partner.state = State.CHAT
	partner.chat_until = t + length
	partner.speak_phase = 1.6
	_face_partner()
	partner._face_partner()


func _face_partner() -> void:
	if partner == null or not is_instance_valid(partner):
		return
	var to := partner.position - position
	facing_up = to.y < -0.05 * world.px
	facing_right = to.x > 0.0
	_show_idle()


# Standing together, taking turns with a bubble each.
func _chatting(t: float) -> void:
	velocity = Vector2.ZERO
	if partner == null or not is_instance_valid(partner) or partner.partner != self or _night() or t > chat_until:
		_end_chat(t)
		return
	_face_partner()
	_show_bubble(fposmod(t + speak_phase, 3.2) < 1.3)


func _show_bubble(on: bool) -> void:
	if bubble == null:
		if not on:
			return
		bubble = Sprite2D.new()
		bubble.z_as_relative = false
		bubble.z_index = 3998
		bubble.visible = false
		add_child(bubble)
	var emojis: Array = s.emojis
	if on and not bubble.visible:
		# A new picture each time (never the same twice running), animated where there's a strip for it.
		var i := randi() % emojis.size()
		if i == last_emoji:
			i = (i + 1) % emojis.size()
		last_emoji = i
		var still := int(emojis[i])
		var nm: String = world.sprites[still].name
		bubble_frames = people.d.get("emotes", {}).get(nm.substr(nm.find("_") + 1), [])
		if bubble_frames.is_empty():
			bubble_frames = [still]
		bubble_start = now()
	bubble.visible = on
	if not on:
		return
	var id := int(bubble_frames[int((now() - bubble_start) * EMOTE_FPS) % bubble_frames.size()])
	world.show_frame(bubble, id, Vector2.ONE * float(s.bubbleScale))
	var info: Dictionary = world.sprites[id]
	var bob := sin(now() * BOB_SPEED) * BOB_HEIGHT * world.px
	# Its bottom just over their head.
	var below := (float(info.rect[3]) - float(info.pivot[1])) * float(s.bubbleScale) * world.px / float(info.ppu)
	bubble.position = Vector2((0.22 if facing_right else -0.22) * world.px, -_top() - 0.02 * world.px - below + bob)


func _end_chat(t: float) -> void:
	_show_bubble(false)
	var other := partner
	partner = null
	if other != null and is_instance_valid(other) and other.partner == self:
		other.partner = null
		other._show_bubble(false)
		other._stand(t, randf_range(1.0, 3.0))
	_stand(t, randf_range(1.0, 3.0))


# ---- Standing up for the village ----

func _home_at() -> Vector2:
	return home.pos if not home.is_empty() else position


# The nearest slime come too close to them or to home, inside the village (they don't go hunting outside it).
func _threat() -> Damageable:
	if (s.stabDown as Array).is_empty():
		return null
	var best: Damageable = null
	var best_d := float(s.guardRange) * world.px
	for d in Damageable.all:
		if not d.alive() or not d.get_parent() is Slime:
			continue
		var at := d.global_position
		if not world.village.contains(at):
			continue
		var near := minf(at.distance_to(position), at.distance_to(_home_at()))
		if near < best_d:
			best_d = near
			best = d
	return best


func _fight(threat: Damageable) -> void:
	if partner != null:
		_end_chat(now())
	foe = threat
	state = State.FIGHT
	clock = 0.0
	last_frame = -1
	next_chase = 0.0


func _fighting(t: float, delta: float) -> void:
	# Gone, or out of the village (they don't follow it out): back to it.
	if foe == null or not is_instance_valid(foe) or not foe.alive() or not world.village.contains(foe.global_position, 0.5) \
			or foe.global_position.distance_to(_home_at()) > float(s.chaseRange) * world.px:
		foe = null
		_stand(t, randf_range(1.0, 2.0))
		return
	var to := foe.global_position - position
	var reach := float(s.stabReach) * world.px + foe.radius * 0.5
	if to.length() > reach:
		# After it, round walls: the way found again as it moves.
		if t >= next_chase:
			next_chase = t + 0.5
			_set_goal(foe.global_position)
		last_frame = -1
		stab_clock = 0.0
		_walk(t, delta)
		state = State.FIGHT  # walking there isn't arriving anywhere
		return
	velocity = Vector2.ZERO
	facing_up = to.y < 0.0
	facing_right = to.x > 0.0
	var up: Array = s.stabUp
	var frames: Array = up if facing_up and not up.is_empty() else s.stabDown
	stab_clock += delta
	var frame := int(stab_clock * float(s.stabFps))
	_show(int(frames[frame % frames.size()]))
	for f in range(last_frame + 1, frame + 1):
		for strike in s.stabStrikes:
			if f % frames.size() == int(strike) and foe != null and is_instance_valid(foe) and foe.alive():
				var strength := 1.0 + 0.06 * (maxi(1, Villagers.skill(person, LifeSkills.Skill.STRENGTH)) - 1)
				foe.hurt(float(person.get("atk", s.stabDamage)) * strength)
				people.practise(person, LifeSkills.Skill.STRENGTH)
	last_frame = frame
