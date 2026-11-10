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
## the right.
##
## They work by day (6 to 18), as set in the jobs window (any work, or one kind): farming (harvesting ripe plots and
## carrying the crop to storage, planting bare ones from the seed in storage), cooking at a fire in the village from
## the raw food in storage until the kitchen's targets are met (lighting it from storage first), clearing up logs and
## stones left lying in the village and the work areas, and felling trees and mining rocks inside the areas marked with
## a sign (on cleared ground), until storage holds the wood and stone it's set to keep. What they gather goes into
## their arms, and to the nearest chest when they're full. Tools from storage make them quicker (and wear out); a bag
## lets them carry more. At dusk they light the fires and torches from storage.

enum State { STAND, WALK, HOME, ASLEEP, FIGHT, TO_EAT, TO_MEAL, EATING, TO_CHAT, CHAT, CHAT_WAIT, TO_DOOR,
	TO_WORK, WORK, TO_STORE, TO_PICKUP, TO_FARM, FARM, TO_COOK, COOK, TO_LIGHT, TO_BUILD, BUILD, TO_CRAFT, CRAFT, TO_REPAIR, REPAIR, FLEE }

enum Job { ANY, MINING, LUMBERING, REST, FARMING, BUILDING, COOKING, CRAFTING }

const BAG_TRIPS := 40             ## trips to storage a bag lasts
const TOOL_USES := 150            ## uses a set of tools lasts
const TOOL_BOOST := 1.35          ## how much quicker tools make the work
const WORK_PACE := 0.6            ## how fast they chop and mine, against their animations' own pace
const NO_SWING_FRAMES := 6
const NO_SWING_STRIKES := [3]

static var claimed := {}          ## Gatherable -> true: rocks and trees being worked, so two don't crowd one
static var gathering := {}        ## Pickup -> true: being fetched
static var out_of_reach := {}     ## Pickup -> until when it's left alone
static var tending := {}          ## plot key -> true
static var cooking_at := {}       ## fire key -> true
static var lighting := {}         ## fire key -> true
static var building := {}         ## blueprint piece -> true: being built
static var unreachable := {}      ## blueprint piece -> until when it's left (walled off)
static var mending := {}          ## barricade (wall key) -> true: someone's on the way to repair it, or at it
static var crafting_now := {}     ## stock key -> true: one villager on each kind of thing at a time

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
var talking := false              ## in a conversation with Miko (Talk): standing still, facing her
var _bark: SpeechBubble           ## a short line over their head (barks), shown a moment
var _bark_until := 0.0
var _bark_next := 0.0
static var _bark_any := 0.0       ## the village's next moment for a bark (not all at once)
var _last_state := -1
var _was_raining := false
var mood := ""                    ## an animated mood bubble over their head for a while (cheerful, worried, alarm, info,
var mood_until := 0.0             ## success, ellipsis, frustration, affection, relaxed, idea): how they feel just now
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
var job: Gatherable                ## the rock or tree they're at (or heading to)
var carry_kind := ""
var carrying := 0
var loose: Pickup
var plot: Dictionary = {}
var planting := false
var farm_task := ""              ## what they're at a plot for: "harvest", "plant", "pests" or "water"
var stove: Dictionary = {}        ## the fire they cook at
var dish := ""
var dishes := 0
var fire: Dictionary = {}         ## the fire or torch they're off to light
var _next_till := 0.0
var _sizzle: AudioStreamPlayer2D
var piece: Dictionary = {}        ## the blueprint piece they're building
var mend: Variant = null           ## the barricade (wall key) they're repairing, or null
var flee_from: Damageable = null   ## the monster they're running from
var _threat_told := 0.0            ## when being in danger outside the village may next be told
## For their dust (DustTrail): moving at all, and running (fleeing).
var moving: bool:
	get: return velocity.length_squared() > 1.0
var running: bool:
	get: return state == State.FLEE
var _next_refuge := 0.0
var _flee_bark_at := 0.0
var _next_smoke := 0.0
var _next_knock := 0.0
var craft_bench: Dictionary = {}
var craft_at := Vector2.ZERO
var craft_recipe: Dictionary = {}


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
		bark("bark.hurt")
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
	# Dust at their feet as they walk (more running for their life), as at Miko's.
	var dust := DustTrail.new()
	dust.name = "Dust"
	dust.target = self
	dust.unit = world.px
	dust.walk_rate = 6.0   # (they only walk: as much as she kicks up running)
	dust.run_rate = 9.0
	world.things.add_child.call_deferred(dust)
	var fx := HitFx.add_to(self, art, wade, world.px)
	fx.thud = world
	hit.damaged.connect(func(_a): fx.play())
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
	_let_go()
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


const MEALS := [7.0, 12.0, 18.0]  ## breakfast, lunch and dinner: the hours they start (each is on for two hours)

# The meal that's on now (0 to 2), or -1 between meals.
func _meal_now() -> int:
	var h := _hour(world)
	for i in MEALS.size():
		if h >= float(MEALS[i]) and h < float(MEALS[i]) + 2.0:
			return i
	return -1


# Whether it's a mealtime they haven't eaten at yet (three a day, hungry or not; skipped when they're full).
func _meal_due() -> bool:
	var m := _meal_now()
	if m < 0 or world.clock == null:
		return false
	var id := world.clock.day() * 3 + m
	if int(person.get("lastMeal", -1)) == id:
		return false
	if float(person.get("hunger", 100.0)) >= 92.0:
		person["lastMeal"] = id
		return false
	return true


# ---- Each tick ----

# Lying in bed they draw over the bed (z 1), which would lift them over the roof too: under a roof that's shown they
# fade out with it, and back in as it fades away (Miko stepping inside).
func _process(delta: float) -> void:
	var __t := Time.get_ticks_usec()
	_process_timed(delta)
	Perf.add(&"villager.process", __t)


func _process_timed(_delta: float) -> void:
	if in_bed and world.roofs != null:
		modulate.a = 1.0 - world.roofs.alpha_over(position)
	elif modulate.a < 1.0:
		modulate.a = 1.0


func _physics_process(delta: float) -> void:
	var __t := Time.get_ticks_usec()
	_physics_process_timed(delta)
	Perf.add(&"villager.physics", __t)


func _physics_process_timed(delta: float) -> void:
	var t := now()
	_needs()
	_unstick(t, delta)
	_close_behind()
	_status()
	# Talking with Miko: standing still, facing her.
	if talking and world.player != null:
		velocity = Vector2.ZERO
		var to := world.player.position - position
		facing_right = to.x > 0.0
		facing_up = to.y < 0.0
		_show_idle()
		return
	# A slime about: go for it (unless asleep, or already at one).
	# Badly hurt (under a fifth of their health) with a monster near: they run instead.
	if state != State.ASLEEP and state != State.FIGHT and state != State.FLEE and t >= next_look:
		next_look = t + 0.5
		var danger := _danger() if _low() else null
		# Out of the village with a monster close: the village hears of it, and they call out.
		if not world.village.contains(position, 1.0) and world.village.founded() and t >= _threat_told:
			var near := danger if danger != null else _danger(4.0)
			if near != null:
				_threat_told = t + 20.0
				VillageLog.problem("threat:" + name, "%s is in danger outside the village: a monster is after them" % person.name, VillageLog.Kind.DANGER)
				bark("bark.threat", {}, true)
				show_mood("alarm", 4.0)
		if danger != null:
			_flee(danger)
		else:
			var threat := _threat() if not _low() else null
			if threat != null:
				_fight(threat)
	match state:
		State.STAND:
			velocity = Vector2.ZERO
			if _night() and not home.is_empty():
				_go_home()
			elif t >= state_until:
				var chance := float(s.workChance)
				# Three meals a day; between them only when they're close to starving.
				if (_meal_due() or float(person.get("hunger", 100.0)) < 12.0) and _go_eat(): pass
				elif _go_door_duty(): pass
				# (in winter the fires and torches are kept burning all day: lit again as each burns down)
				elif (_hour(world) >= 17.5 or (_fires() != null and _fires().winter() and not _night())) and _go_light(): pass
				elif not _work_hours() and not _night() and randf() < 0.45 and _go_chat(t): pass
				elif _work_hours() and _go_repair(): pass
				elif _work_hours() and (randf() < chance or _crops_need_care()) and _go_farm(): pass
				elif _work_hours() and randf() < chance and _go_cook(): pass
				elif _work_hours() and randf() < chance and _go_build(): pass
				elif _work_hours() and _go_pick_up(): pass
				elif _work_hours() and randf() < chance and _go_craft(): pass
				elif _work_hours() and randf() < chance and _find_work():
					state = State.TO_WORK
					clock = 0.0
					state_until = t + 30.0
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
		State.FLEE:
			_fleeing(t, delta)
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
		State.TO_WORK:
			if _night() or not _workable(job) or t >= state_until: _stop_work(t)
			else: _walk(t, delta)
		State.WORK:
			_work(t, delta)
		State.TO_STORE:
			_walk(t, delta)
		State.TO_PICKUP:
			if loose == null or not is_instance_valid(loose) or not loose.settled(): _done_pick_up(t)
			else: _walk(t, delta)
		State.TO_FARM:
			if plot.is_empty() or _night(): _done_farming(t)
			else: _walk(t, delta)
		State.FARM:
			_farming(t)
		State.TO_COOK:
			if stove.is_empty() or _night() or t > state_until: _done_cooking(t)
			else: _walk(t, delta)
		State.COOK:
			_cooking(t, delta)
		State.TO_LIGHT:
			if fire.is_empty() or _fires().lit(fire): _done_lighting(t)
			else: _walk(t, delta)
		State.TO_BUILD:
			if piece.is_empty() or _night() or Construction.active == null or not Construction.active.has(piece): _done_building(t)
			elif t > state_until:
				unreachable[piece] = t + 30.0
				_done_building(t)
			else: _walk(t, delta)
		State.BUILD:
			_building(t)
		State.TO_REPAIR:
			if not _mend_worn() or t > state_until: _done_repairing(t)
			else: _walk(t, delta)
		State.REPAIR:
			_repairing(t)
		State.TO_CRAFT:
			if _night() or craft_bench.is_empty(): _done_crafting(t)
			else: _walk(t, delta)
		State.CRAFT:
			_crafting(t, delta)
	# Called off cooking any other way (a slime, bedtime): the pan goes quiet.
	if state != State.COOK and _sizzle != null and _sizzle.playing and not _sizzle.stream_paused:
		Sfx.keep_going(_sizzle, false)
	if not in_bed:
		_keep_out_of_mist(t, delta)
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
	var mid := walls.wall_middle(_door_to_close.key())
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
	var speed := float(s.walkSpeed) * world.px * (1.7 if state == State.FLEE else 1.0)   # (running for it)
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
		if state == State.TO_WORK:
			if last and dir.length() < 0.8 * world.px: _arrive(t)
			else: _stop_work(t)
			return
		# Up against it on the way to a chest, a fire or a plot, a step short: close enough.
		if last and dir.length() < 0.6 * world.px and state != State.WALK:
			_arrive(t)
			return
		if state == State.TO_COOK:
			if not stove.is_empty() and position.distance_to(stove.pos) < 1.3 * world.px: _arrive(t)
			else: _done_cooking(t)
			return
		if state == State.TO_REPAIR:
			if mend != null and position.distance_to(_mend_at()) < 1.6 * world.px: _arrive(t)
			else: _done_repairing(t)
			return
		if state == State.TO_BUILD:
			# Close enough to reach it: build from here. Otherwise leave it a while and do something else.
			if dir.length() < world.px or (not piece.is_empty() and position.distance_to(Construction.active.position_of(piece)) < 1.1 * world.px): _arrive(t)
			else:
				if not piece.is_empty(): unreachable[piece] = t + 30.0
				_done_building(t)
			return
	velocity = v


func _arrive(t: float) -> void:
	velocity = Vector2.ZERO
	match state:
		State.TO_EAT: _eat(t)
		State.TO_MEAL: _start_eating(t)
		State.TO_DOOR: _see_to_door(t)
		State.TO_CHAT: _start_chat(t)
		State.TO_WORK: _start_work(t)
		State.TO_STORE: _unload(t)
		State.TO_PICKUP: _pick_up(t)
		State.TO_FARM: _start_farming(t)
		State.TO_COOK: _start_cooking(t)
		State.TO_LIGHT: _light_it(t)
		State.TO_BUILD: _start_building(t)
		State.TO_REPAIR: _start_repairing(t)
		State.FLEE: _next_refuge = 0.0   # (somewhere further next: still running)
		State.TO_CRAFT: _start_crafting(t)
		State.HOME:
			# Into bed, unless Miko's in it: then they wait beside it till morning.
			if not home.is_empty() and not Needs.occupants.has(Needs.bed_key(home.pos)):
				_go_to_sleep()
			else:
				_stand(t, 5.0)
		_:
			_stand(t, randf_range(2.0, 6.0))


func _going() -> bool:
	return state in [State.WALK, State.HOME, State.TO_EAT, State.TO_MEAL, State.TO_CHAT, State.TO_DOOR, State.TO_WORK,
		State.TO_STORE, State.TO_PICKUP, State.TO_FARM, State.TO_COOK, State.TO_LIGHT, State.TO_BUILD, State.TO_CRAFT, State.TO_REPAIR, State.FLEE]


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
	_abandon(t)
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
	return World.BODY_SCALE   # one scale for every person (villagers.json's look scale no longer counts)


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
# Villagers live on cleared ground (the village, a crystal's clearing): a step from there into the mist isn't taken,
# and whatever they were walking to is given up. Caught out in it (the mist came back over them), they may walk out.
func _keep_out_of_mist(t: float, delta: float) -> void:
	if velocity == Vector2.ZERO or world.mist == null or not safe_ground(world, position):
		return
	var ahead := position + velocity * maxf(delta, 0.016) * 4.0
	if safe_ground(world, ahead):
		return
	velocity = Vector2.ZERO
	# A stroll or a chat is just given up; a job is left to its own "stuck" handling (it lets go of what it claimed).
	if state == State.WALK or state == State.TO_CHAT:
		_stand(t, randf_range(0.5, 1.5))


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
	lie_in_bed()
	collision_layer = 0
	if shadow != null:
		shadow.visible = false
	Needs.occupants[Needs.bed_key(home.pos)] = self
	in_bed = true
	z_index = 1   # drawn over the bed
	sleep_clock = 0.0


## Which sleeping pose they're in: "sleepUp" (seen from behind) or "sleepDown".
func sleep_pose() -> String:
	return "sleepUp" if facing_up else "sleepDown"


## Puts them where they lie on their bed: head on the pillow, turned along it, and then as adjusted by hand
## (SleepTune: x, y px and degrees for their look and pose, mirrored with them).
func lie_in_bed() -> void:
	var lying: Variant = look.get("lying", {}).get(sleep_pose())
	var lie: Array = Needs.lie_on_bed(world, home, lying, facing_right, 1.0)
	var tune := SleepTune.of(int(person.get("look", 0)), sleep_pose())
	var side := -1.0 if facing_right else 1.0
	position = (lie[0] as Vector2) + Vector2(float(tune[0]) * side, float(tune[1]))
	art.rotation = float(lie[1]) + deg_to_rad(float(tune[2])) * side
	reset_physics_interpolation()


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
	# A cold night told on waking: they say so, and work slower today.
	var was_cold := _cold_hours >= 3.0
	_cold_hours = 0.0
	if was_cold != bool(person.get("cold", false)):
		person["cold"] = was_cold
	if was_cold:
		bark("bark.cold", {}, true)
		show_mood("frustration", 5.0)
		VillageLog.problem("cold-night", "Villagers slept cold: a house needs a fireplace, and wood to burn in it", VillageLog.Kind.DANGER)
	if in_bed:
		in_bed = false
		if Needs.occupants.get(Needs.bed_key(home.pos)) == self:
			Needs.occupants.erase(Needs.bed_key(home.pos))
		position = _door()
		art.rotation = 0.0
		reset_physics_interpolation()
		collision_layer = 8
		if shadow != null:
			shadow.visible = true
		z_index = 0
	visible = true
	facing_up = false
	_stand(t, randf_range(0.1, 0.5))   # (up and off: not standing by the bed)


# ---- Needs ----

var _next_chilly := 0.0

## How cold they are now: 0 not (not winter, under a roof, by a burning fire), 1 cold, 2 freezing (out in the snow).
## A scarf takes it down a step. Cold, they work slower (and slower still freezing) and say so now and then.
func chill() -> int:
	var c := world.clock
	if c == null or c.season() != GameClock.Season.WINTER or in_bed:
		return 0
	if world.roofs != null and world.roofs.covers(position):
		return 0
	var fires := _fires()
	if fires != null and fires.warm(position, Needs.WARMTH * world.px):
		return 0
	var cold := 2 if c.weather() == GameClock.Weather.SNOW else 1
	return maxi(0, cold - (1 if bool(person.get("scarf", false)) else 0))


# Winter, and no scarf: one from storage, if there is one. And now and then, cold, they say so.
func _winter_wear(t: float) -> void:
	var c := world.clock
	if c == null or c.season() != GameClock.Season.WINTER:
		return
	if not bool(person.get("scarf", false)) and world.village.founded():
		var v := world.village
		for i in v.items.size():
			if UiKit.item(v.items[i]).get("kind", "") == "Scarf":
				v.items.remove_at(i)
				v.changed.emit()
				person["scarf"] = true
				VillageLog.event("scarf:" + name, "%s took a scarf from storage" % name)
				bark("bark.scarf", {}, true)
				show_mood("relaxed", 4.0)
				break
	if t >= _next_chilly:
		_next_chilly = t + randf_range(40.0, 80.0)
		if chill() > 0 and state != State.ASLEEP:
			bark("bark.chilly.scarf" if bool(person.get("scarf", false)) else "bark.chilly")
			show_mood("worried", 3.0)


var _cold_hours := 0.0           ## hours of this sleep spent cold

# Whether they're sleeping cold: winter, and no fire burning in their house.
func _sleeping_cold() -> bool:
	var fires := _fires()
	if fires == null or not fires.winter() or home.is_empty() or world.roofs == null:
		return false
	var room: Variant = world.roofs.room_on(home.pos)
	return room == null or not fires.warm_room(room)


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
	# Asleep in winter with no fire burning in the house: a cold night. They rest half as well, don't mend, and
	# work slower the day after.
	_winter_wear(now())
	var cold_night := sleeping and in_bed and _sleeping_cold()
	# A leaking roof over them (the house worn past half): they rest a quarter worse; a house fallen to nothing is
	# no shelter, as bad a night as a cold one.
	var shelter := Upkeep.active.condition_at(home.pos) if sleeping and in_bed and Upkeep.active != null and not home.is_empty() else 100.0
	if shelter <= 0.0 and sleeping and in_bed:
		cold_night = true
	if sleeping:
		_cold_hours = _cold_hours + dh if cold_night else maxf(0.0, _cold_hours - dh)
	p.energy = clampf(float(p.energy) + ((7.0 if cold_night else (10.5 if shelter < Upkeep.LEAKY else 14.0)) if sleeping else -6.0 / stamina) * dh, 0.0, 100.0)
	# Long days on their feet build stamina.
	if not sleeping:
		_awake_hours += dh
		if _awake_hours >= 2.0:
			_awake_hours = 0.0
			people.practise(p, LifeSkills.Skill.STAMINA)
	if sleeping and not cold_night and float(p.hunger) > 0.0 and hit.hp < hit.max_hp:
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
		n += world.village.spare(f[0])   # (not what's kept for planting)
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
	# One sitting: as much as fills them (the most filling things first, a few at most), so they don't come back for
	# more before the next meal.
	for helping in 4:
		if took and float(person.hunger) >= 85.0:
			break
		var had := false
		for f in FOODS:
			if world.village.spare(f[0]) > 0 and world.village.take_from_stash(f[0], 1):
				person.hunger = minf(100.0, float(person.hunger) + float(f[1]))
				if not took:
					meal = f[0]
				took = true
				had = true
				break
		if not had:
			break
	# That's this mealtime's meal eaten.
	if took and _meal_now() >= 0 and world.clock != null:
		person["lastMeal"] = world.clock.day() * 3 + _meal_now()
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
		Sfx.play(world, Sfx.stream(path), position, 0.6)
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
# ---- Barks: a short line over their head now and then (lang/en.json's bark.*), as things happen ----

## Says one of [param key]'s lines over their head for a moment (not again for a while, and not two villagers at once
## unless [param force]).
func bark(key: String, values := {}, force := false) -> void:
	var t := now()
	if not force and (t < _bark_next or t < _bark_any):
		return
	var line := Loc.pick(key, values)
	if line == "":
		return
	_bark_next = t + 25.0
	_bark_any = t + 2.5
	if _bark == null:
		_bark = SpeechBubble.new()
		add_child(_bark)
	_bark.say(line, bark_kind(key))
	_bark.visible = true
	_bark_until = t + 2.8


## How a line is said: thought (hungry, tired, rain), shouted (a fight, no food), in alarm (hurt, a raid, starving),
## else spoken.
static func bark_kind(key: String) -> int:
	if key in ["bark.hurt", "bark.raid", "bark.flee", "bark.threat", "miko.starving"]:
		return SpeechBubble.Kind.ALARM
	if key in ["bark.fight", "bark.no_food"]:
		return SpeechBubble.Kind.SHOUT
	if key in ["bark.hungry", "bark.tired", "bark.rain", "bark.chilly", "bark.chilly.scarf", "miko.hungry"]:
		return SpeechBubble.Kind.THINK
	return SpeechBubble.Kind.SAY


# What happens to them, said out loud: turning hungry or for bed, pests, a fight; rain starting.
func _barks() -> void:
	var t := now()
	if _bark != null and _bark.visible:
		if t >= _bark_until or talking:   # (talking: the talk bubble says it)
			_bark.visible = false
		else:
			_bark.place(Vector2(0, -_top() + 0.02 * world.px))
	if state != _last_state:
		_last_state = state
		match state:
			State.TO_EAT:
				bark("bark.hungry" if _food_in_storage() > 0 else "bark.no_food")
				if _food_in_storage() == 0:
					show_mood("frustration", 7.0)
			State.HOME: bark("bark.tired")
			State.FIGHT: bark("bark.fight")
			State.TO_FARM: if farm_task == "pests": bark("bark.pests")
	var raining := world.clock != null and world.clock.weather() in [GameClock.Weather.RAIN, GameClock.Weather.STORM]
	if raining and not _was_raining and not in_bed and randf() < 0.3:
		bark("bark.rain")
	_was_raining = raining


## Shows [param m] (a mood bubble's name) over their head for [param seconds].
func show_mood(m: String, seconds := 3.0) -> void:
	mood = m
	mood_until = now() + seconds


func _status() -> void:
	_barks()
	if _bark != null and _bark.visible:
		_emote("")   # (the line's showing: no emote over it)
		return
	if mood != "" and now() < mood_until:
		_emote("mood." + mood)
		return
	mood = ""
	if bubble != null and bubble.visible:
		_emote("")
		return
	var e := ""
	match state:
		State.EATING: e = "eating"
		State.TO_EAT: e = "hungry"
		State.HOME: e = "sleepy"
		State.TO_STORE: e = "transporting" if carrying > 0 else ""
		State.TO_PICKUP: e = "gathering"
		State.COOK: e = "cooking"
		State.TO_FARM, State.FARM: e = {"pests": "pests", "water": "watering", "plant": "planting"}.get(farm_task, "")
		State.BUILD: e = "building"
		State.TO_REPAIR, State.REPAIR: e = "repairing"
		State.FLEE: e = "crying"
		State.CRAFT:
			if craft_bench.get("skill", "") == "Cooking": e = "cooking"
			elif str(craft_bench.get("title", "")).contains("Alchemy"): e = "alchemy"
			else: e = "workbench"
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
const EATING_SHEET := "res://assets/Resources/Emotes/Emote_eating.png"
const EATING_FRAMES := 8
static var _eating_tex: Texture2D


func _emote(e: String) -> void:
	if e == "eating" and ResourceLoader.exists(EATING_SHEET):
		_eating_emote()
		return
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
	emote.modulate = world.daylight_undo()   # as drawn, whatever the hour (the evening's tint would grey it)
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


# The eating emote (its own art: a happy face with a spoon), 160 ms a frame, its tail towards their head.
func _eating_emote() -> void:
	if _eating_tex == null:
		_eating_tex = load(EATING_SHEET)
	if emote == null:
		emote = Sprite2D.new()
		emote.z_as_relative = false
		emote.z_index = 3998
		emote.add_child(Sprite2D.new())
		add_child(emote)
	emote.visible = true
	emote.modulate = world.daylight_undo()   # as drawn, whatever the hour (the evening's tint would grey it)
	(emote.get_child(0) as Sprite2D).visible = false
	@warning_ignore("integer_division")
	var fw := _eating_tex.get_width() / EATING_FRAMES
	var fh := _eating_tex.get_height()
	var frame := int(now() / 0.16) % EATING_FRAMES
	emote.texture = _eating_tex
	emote.region_enabled = true
	emote.region_rect = Rect2(frame * fw, 0, fw, fh)
	emote.centered = false
	emote.offset = Vector2(-fw / 2.0, -fh)
	emote.scale = Vector2.ONE * EMOTE_WIDTH * world.px / float(fw)
	emote.flip_h = not facing_right
	var bob := sin(now() * BOB_SPEED) * BOB_HEIGHT * world.px
	emote.position = Vector2((0.24 if facing_right else -0.24) * world.px, -_top() - 0.06 * world.px + bob)


# How tall their standing art is above their feet, px.
func _top() -> float:
	var id := int(s.idleDown)
	var info: Dictionary = world.sprites[id]
	return (float(info.pivot[1]) - _head_room(id)) * world.px / float(info.ppu) * _scale()


static var _head_rooms := {}     ## idle sprite -> px of empty frame above the head

# How far down its frame the head of sprite [param id] starts (the empty space above it), measured once.
func _head_room(id: int) -> float:
	if not _head_rooms.has(id):
		var info: Dictionary = world.sprites[id]
		var tex := world._texture(info.tex)
		var img := tex.get_image() if tex != null else null
		var room := 0.0
		if img != null:
			var used := img.get_region(Rect2i(int(info.rect[0]), int(info.rect[1]), int(info.rect[2]), int(info.rect[3]))).get_used_rect()
			room = float(used.position.y) if used.size.y > 0 else 0.0
		_head_rooms[id] = room
	return float(_head_rooms[id])


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
		# Half the time a mood of the chat instead (the bubble set's).
		if randf() < 0.5:
			bubble_frames = people.d.get("emotes", {}).get("mood." + ["cheerful", "relaxed", "affection", "idea", "ellipsis", "info"].pick_random(), bubble_frames)
		if bubble_frames.is_empty():
			bubble_frames = [still]
		bubble_start = now()
	bubble.visible = on
	if not on:
		return
	bubble.modulate = world.daylight_undo()   # as drawn, whatever the hour (as the emotes)
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
	if job != null:
		claimed.erase(job)
		job = null
	foe = threat
	state = State.FIGHT
	clock = 0.0
	last_frame = -1
	next_chase = 0.0


func _fighting(t: float, delta: float) -> void:
	# Too badly hurt to keep at it: off they run.
	if _low():
		var danger := _danger()
		if danger != null:
			_flee(danger)
			return
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
				# The thrust heard (the spear's stab, as the shikigami's).
				Sfx.play(world, Sfx.stream("res://assets/Sounds/shiki_spear_stab.mp3"), position, 0.55, 0.1)
				people.practise(person, LifeSkills.Skill.STRENGTH)
	last_frame = frame



# ---- Running away: under a fifth of their health, with a monster near, they drop everything and run, away from
# it (home, if that's away from it), faster than they walk, till it's well behind them. ----

const FLEE_BELOW := 0.2          ## share of their health under which they run
const DANGER_RANGE := 6.0        ## units: a monster this near sends them running
const SAFE_RANGE := 9.0          ## units: this far from it, they stop

func _low() -> bool:
	return hit != null and hit.hp < hit.max_hp * FLEE_BELOW


# The nearest monster within [param within] units (any, in the village or out), or null.
func _danger(within := DANGER_RANGE) -> Damageable:
	var best: Damageable = null
	var best_d := within * world.px
	for d in Damageable.all:
		if d.team != Damageable.Team.ENEMY or not d.alive() or d.dummy:
			continue
		# Monsters only (not a corrupted tree), awake, and not a rabbit or a boar left in peace.
		var c := d.get_parent() as Creature
		if c == null or c.asleep or c is Rabbit or (c is Boar and (c as Boar).angry_until < Creature.now()):
			continue
		var dd := d.global_position.distance_to(position)
		if dd < best_d:
			best_d = dd
			best = d
	return best


func _flee(from: Damageable) -> void:
	if partner != null:
		_end_chat(now())
	_let_go()
	job = null
	mend = null
	piece = {}
	foe = null
	flee_from = from
	state = State.FLEE
	clock = 0.0
	_next_refuge = 0.0
	if now() >= _flee_bark_at:   # (once, not again every time they turn to run)
		_flee_bark_at = now() + 10.0
		bark("bark.flee", {}, true)
	mood = ""   # (crying while they run: no other mood over it)


func _fleeing(t: float, delta: float) -> void:
	var d := flee_from
	if d == null or not is_instance_valid(d) or not d.alive() or d.global_position.distance_to(position) > SAFE_RANGE * world.px:
		# Safe: nearer monsters still about? Run from that one; else catch their breath.
		var other := _danger()
		if other != null:
			flee_from = other
		else:
			flee_from = null
			show_mood("worried", 3.0)
			_stand(t, randf_range(2.0, 3.0))
			return
	if t >= _next_refuge:
		_next_refuge = t + 1.0
		_set_goal(_refuge(flee_from.global_position))
	_walk(t, delta)
	if state != State.FLEE and flee_from != null:
		state = State.FLEE   # (getting there isn't arriving anywhere: still running)


# Somewhere to run to from a monster at [param from]: their door if it's away from it; else a spot a few units
# off, the way most directly away from it that can be walked to.
func _refuge(from: Vector2) -> Vector2:
	var here := position.distance_to(from)
	if not home.is_empty():
		var door := _door()
		if door.distance_to(from) > here + 0.5 * world.px and (door - position).dot(position - from) > 0.0 and door.distance_to(position) < 14.0 * world.px:
			return door
	var away := (position - from).normalized()
	if away.length() < 0.5:
		away = Vector2.from_angle(randf() * TAU)
	for turn in [0.0, 0.5, -0.5, 1.0, -1.0, 1.5, -1.5]:
		var dir := away.rotated(turn)
		var spot := position + Vector2(dir.x, dir.y * 0.5).normalized() * 5.0 * world.px
		if Wilds.dry(world, spot, 0.3) and VillagerRoute.find(world, position, spot) != null:
			return spot
	return position + away * 3.0 * world.px


# ---- Work ----

func _job() -> int:
	return int(person.get("job", Job.ANY))


func _fires() -> Fires:
	return world.player.get_node_or_null("Fires") as Fires


func _farming_node() -> Farming:
	return world.player.get_node_or_null("Farming") as Farming


# Lets go of whatever they were on the way to (so someone else can take it), and stands a moment.
func _abandon(t: float) -> void:
	match state:
		State.TO_WORK: _stop_work(t)
		State.TO_COOK: _done_cooking(t)
		State.TO_FARM: _done_farming(t)
		State.TO_LIGHT: _done_lighting(t)
		State.TO_CHAT: _end_chat(t)
		State.TO_BUILD:
			if not piece.is_empty(): unreachable[piece] = t + 30.0
			_done_building(t)
		State.TO_CRAFT: _done_crafting(t)
		State.TO_REPAIR: _done_repairing(t)
		State.FLEE: _next_refuge = 0.0   # (stuck: somewhere else to run, still running)
		State.TO_PICKUP:
			if loose != null:
				out_of_reach[loose] = t + 60.0
			_done_pick_up(t)
		_: _stand(t, randf_range(0.5, 1.5))


# Everything they'd claimed, let go (leaving, or dying).
func _let_go() -> void:
	if job != null: claimed.erase(job)
	if loose != null: gathering.erase(loose)
	if not plot.is_empty(): tending.erase(plot.key)
	if not stove.is_empty(): cooking_at.erase(stove.key)
	if not fire.is_empty(): lighting.erase(fire.key)
	if not piece.is_empty(): building.erase(piece)
	if mend != null: mending.erase(mend)
	if not craft_recipe.is_empty(): crafting_now.erase(_recipe_key(craft_recipe))


# Strength lets them carry more: one more for every two levels past the first, and a bag more again.
func _carry_most() -> int:
	@warning_ignore("integer_division")
	return int(s.carryMost) + (Villagers.skill(person, LifeSkills.Skill.STRENGTH) - 1) / 2 + int(person.get("bagSlots", 0))


func _has_tools() -> bool:
	return int(person.get("toolsLeft", 0)) > 0


func _tool_pace() -> float:
	return (TOOL_BOOST if _has_tools() else 1.0) * Villagers.heart * (0.8 if bool(person.get("cold", false)) else 1.0) * [1.0, 0.88, 0.72][chill()]   # (Village Heart: quicker with Miko about)


# Tools and a bag from storage, picked up when they start on work that wants them.
func _kit() -> void:
	var v := world.village
	if not v.founded():
		return
	if not _has_tools():
		for i in v.items.size():
			if UiKit.item(v.items[i]).get("kind", "") == "Tools":
				var nm: String = v.items[i]
				v.items.remove_at(i)
				v.changed.emit()
				person.toolsLeft = TOOL_USES
				VillageLog.event("tools:" + name, "%s took a set of %s from storage" % [name, str(UiKit.item(nm).get("name", nm)).to_lower()])
				break
	if str(person.get("bag", "")) != "" and int(person.get("bagLeft", 0)) <= 0:
		person.bagLeft = BAG_TRIPS
	if str(person.get("bag", "")) == "":
		for i in v.items.size():
			if UiKit.item(v.items[i]).get("kind", "") == "Bag":
				var nm: String = v.items[i]
				v.items.remove_at(i)
				v.changed.emit()
				person.bag = nm
				person.bagSlots = int(UiKit.item(nm).get("bagSlots", 0))
				person.bagLeft = BAG_TRIPS
				VillageLog.event("bag:" + name, "%s took a %s from storage: carries %d more" % [name, str(UiKit.item(nm).get("name", nm)).to_lower(), person.bagSlots])
				break


# One use of their tools; worn out, they're gone.
func _wear_tools() -> void:
	if not _has_tools():
		return
	person.toolsLeft = int(person.toolsLeft) - 1
	if int(person.toolsLeft) == 0:
		VillageLog.event("tools:" + name, "%s's tools wore out: make more at the workbench" % name, VillageLog.Kind.WARNING)


func _workable(g: Gatherable) -> bool:
	return g != null and is_instance_valid(g) and not g.depleted()


## The work areas (the signs' areas) for [param kind] ("Lumbering", "Mining"): [[centre, radius px]].
func _areas(kind: String) -> Array:
	var out := []
	var defs: Dictionary = people.d.get("workAreas", {})
	for prop in defs:
		if defs[prop].kind == kind:
			for at in world.props_named(prop):
				out.append([at, float(defs[prop].radius) * world.px])
	return out


func _in_area(areas: Array, at: Vector2) -> bool:
	for a in areas:
		if a[0].distance_to(at) <= a[1]:
			return true
	return false


# A rock or a tree (a coin toss which they'd rather; the other if there's none), the nearest to home in a work area,
# on cleared ground, nobody else's; not while storage holds the wood or stone it's set to keep.
func _find_work() -> bool:
	var choice := _job()
	if choice in [Job.REST, Job.FARMING, Job.BUILDING, Job.COOKING, Job.CRAFTING]:
		return false
	var chop := not Kitchen.stocked(world.village, "Wood")
	var mine := not Kitchen.stocked(world.village, "Stone")
	var spot: Gatherable = null
	if choice == Job.MINING:
		spot = _nearest_work(false) if mine else null
	elif choice == Job.LUMBERING:
		spot = _nearest_work(true) if chop else null
	else:
		var first := randf() < 0.5
		if (chop if first else mine): spot = _nearest_work(first)
		if spot == null and (mine if first else chop): spot = _nearest_work(not first)
	if spot == null:
		return false
	job = spot
	claimed[job] = true
	_set_goal(_work_spot(job))
	return true


func _nearest_work(axe: bool) -> Gatherable:
	var kind := "Lumbering" if axe else "Mining"
	var areas := _areas(kind)
	if areas.is_empty():
		VillageLog.problem("no-area:" + kind, ("No lumbering area: place a Lumbering Sign where the villagers may fell trees" if axe
			else "No mining area: place a Mining Sign where the villagers may mine"), VillageLog.Kind.NEWS)
		return null
	var home_at := _home_at()
	var candidates := []
	var in_mist := false
	for g in Gatherable.all:
		if g.axe != axe or not _workable(g) or claimed.has(g) or not _in_area(areas, g.foot):
			continue
		if not safe_ground(world, g.foot):
			in_mist = true
			continue
		candidates.append([g, g.foot.distance_to(home_at)])
	candidates.sort_custom(func(a, b): return a[1] < b[1])
	for i in mini(candidates.size(), 8):
		if _safe_way_to(_work_spot(candidates[i][0])):
			return candidates[i][0]
	if candidates.is_empty() and in_mist:
		VillageLog.problem("mist-area:" + kind, "The %s area is in the mist: clear it with a cleansing crystal, or put the sign on cleared ground" % kind.to_lower())
	return null


# Just off its edge, on this side of it.
func _work_spot(g: Gatherable) -> Vector2:
	var away := position - g.foot
	if away.length_squared() < 1.0:
		away = Vector2(0, 1)
	var dir := away.normalized()
	# Step in from here until the edge is a third of a unit off.
	var p := g.foot + dir * 0.5 * world.px
	for i in 12:
		var q := g.foot + dir * (0.2 + i * 0.1) * world.px
		if g.distance_to(q) >= 0.3 * world.px:
			p = q
			break
	return p


func _start_work(t: float) -> void:
	_kit()
	state = State.WORK
	clock = 0.0
	last_frame = -1
	state_until = t + randf_range(float(s.shift[0]), float(s.shift[1]))
	var toward: Vector2 = job.foot - position if _workable(job) else Vector2(0, 1)
	facing_up = toward.y < 0.0
	facing_right = toward.x > 0.0


func _work(t: float, delta: float) -> void:
	velocity = Vector2.ZERO
	if _night() or not _workable(job) or t >= state_until:
		_stop_work(t)
		return
	var axe := job.axe
	var down: Array = s.chopDown if axe else s.mineDown
	var up: Array = s.chopUp if axe else s.mineUp
	var use_up := facing_up and not up.is_empty()
	var frames := up if use_up else down
	var animated := not frames.is_empty()
	var strikes: Array = NO_SWING_STRIKES
	if animated:
		if axe: strikes = s.chopStrikesUp if use_up else s.chopStrikesDown
		else: strikes = s.mineStrikesUp if use_up else s.mineStrikesDown
	clock += delta
	# Skill quickens the swing: a master works twice as fast as a novice. All of it at WORK_PACE: slow, heavy work.
	var skill := Villagers.skill(person, LifeSkills.Skill.LUMBERING if axe else LifeSkills.Skill.MINING)
	var fps := float(s.chopFps) if axe else float(s.mineFps)
	var frame := int(clock * fps * (0.8 + 0.12 * skill) * WORK_PACE * _tool_pace())
	var length := frames.size() if animated else NO_SWING_FRAMES
	if animated:
		_show(int(frames[frame % frames.size()]))
	else:
		_show_idle()
	for f in range(last_frame + 1, frame + 1):
		for st in strikes:
			if f % length == int(st):
				_strike()
	last_frame = frame


func _strike() -> void:
	if not _workable(job):
		return
	_wear_tools()
	var path: Variant = s.axeSound if job.axe else s.pickaxeSound
	if path is String and ResourceLoader.exists(path):
		Sfx.play(world, Sfx.stream(path), job.foot, float(s.toolVolume), 0.08)
	var spot := job
	var got := spot.strike()
	# Felling a tree: now and then a seed, brought home for planting.
	if spot.axe and spot.depleted() and randf() < 0.35:
		world.village.deposit("Seed", 1, spot.foot)
	if got > 0:
		people.practise(person, LifeSkills.Skill.LUMBERING if spot.axe else LifeSkills.Skill.MINING)
		# Into their arms (one kind at a time); full arms, off to storage.
		if carrying > 0 and carry_kind != spot.resource:
			_unload(now(), false)
		carry_kind = spot.resource
		carrying += got
		if carrying >= _carry_most():
			_stop_work(now())


func _stop_work(t: float) -> void:
	if job != null:
		claimed.erase(job)
	job = null
	if carrying > 0 and _go_store():
		return
	_stand(t, randf_range(2.0, 5.0))


# ---- Clearing up: logs, stones and crops left lying, taken to storage ----

func _gatherable(r: String) -> bool:
	return r == "Wood" or r == "Stone" or Farming.CROPS.has(r)


func _nearest_loose(within: float) -> Pickup:
	var best: Pickup = null
	var best_d := within
	var lumber := _areas("Lumbering")
	var mining := _areas("Mining")
	var t := now()
	for p in Pickup.all:
		if not p.settled() or gathering.has(p) or not _gatherable(p.resource):
			continue
		if carrying > 0 and p.resource != carry_kind:
			continue
		# Storage full of it: carrying it back would only see it dropped again.
		if world.village.stored(p.resource) >= world.village.stash_cap(p.resource):
			continue
		if t < float(out_of_reach.get(p, -1.0)):
			continue
		var at := p.ground
		if not world.village.contains(at, 1.0) and not _in_area(lumber, at) and not _in_area(mining, at):
			continue
		var dd := at.distance_to(position)
		if dd < best_d:
			best_d = dd
			best = p
	return best


func _go_pick_up() -> bool:
	var choice := _job()
	if choice != Job.ANY and choice != Job.LUMBERING and choice != Job.MINING:
		return false
	if carrying >= _carry_most():
		return false
	var p := _nearest_loose(25.0 * world.px)
	if p == null:
		return false
	var walled := world.walls != null and VillagerRoute.find(world, position, p.ground) == null and position.distance_to(p.ground) > 1.2 * world.px
	if not safe_ground(world, p.ground) or walled:
		out_of_reach[p] = now() + 60.0
		return false
	loose = p
	gathering[p] = true
	state = State.TO_PICKUP
	clock = 0.0
	_set_goal(p.ground)
	return true


# Into their arms; more lying close by of the same, on to that; arms full (or nothing near), off to storage.
func _pick_up(t: float) -> void:
	if loose != null and is_instance_valid(loose) and loose.settled():
		if carrying == 0:
			carry_kind = loose.resource
		carrying += loose.amount
		gathering.erase(loose)
		loose.take_away()
		people.practise(person, LifeSkills.Skill.STRENGTH)
	elif loose != null:
		gathering.erase(loose)
	loose = null
	if carrying < _carry_most():
		var nxt := _nearest_loose(3.0 * world.px)
		if nxt != null:
			loose = nxt
			gathering[nxt] = true
			state = State.TO_PICKUP
			_set_goal(nxt.ground)
			return
	if carrying > 0 and _go_store():
		return
	_stand(t, randf_range(0.5, 1.5))


func _done_pick_up(t: float) -> void:
	if loose != null:
		gathering.erase(loose)
	loose = null
	if carrying > 0 and _go_store():
		return
	_stand(t, randf_range(0.5, 1.5))


# ---- Carrying to storage ----

func _go_store() -> bool:
	var spot: Variant = UseSpots.nearest_chest_spot(world, position)
	if spot == null:
		VillageLog.problem("no-storage", "No storage: build a chest in the village for the villagers' haul")
		return false
	state = State.TO_STORE
	clock = 0.0
	_set_goal(spot)
	return true


# Puts down what they carry: into the stash as far as it holds, the rest on the ground beside them.
func _unload(t: float, stand := true) -> void:
	if carrying > 0:
		var v := world.village
		v.deposit(carry_kind, carrying, position + Vector2(0, -0.3 * world.px))
		if carrying >= 4:
			people.practise(person, LifeSkills.Skill.STRENGTH)
		# Their bag wears with each trip; worn through, it's gone.
		if str(person.get("bag", "")) != "":
			person.bagLeft = int(person.bagLeft) - 1
			if int(person.bagLeft) <= 0:
				VillageLog.event("bag:" + name, "%s's bag wore through: make more at the workbench" % name, VillageLog.Kind.WARNING)
				person.bag = ""
				person.bagSlots = 0
				person.bagLeft = 0
		var cap := v.stash_cap(carry_kind)
		var have := v.stored(carry_kind)
		var what := UiKit.resource_name(carry_kind).to_lower()
		if cap > 0 and have >= cap:
			VillageLog.problem("storage-full", "Storage is full of %s: build more chests (the rest is left on the ground)" % what, VillageLog.Kind.DANGER)
		elif cap > 0 and have >= cap * 0.85:
			VillageLog.problem("storage-nearly", "Storage is nearly full of %s" % what)
		carrying = 0
	if stand:
		_stand(t, randf_range(2.0, 4.0))


# ---- Farming: ripe plots first (the crop carried to storage), then pests cleared, then dry crops watered, then bare
# ones planted from storage ----

func _go_farm() -> bool:
	var choice := _job()
	if choice != Job.ANY and choice != Job.FARMING:
		return false
	if carrying > 0 and not Farming.CROPS.has(carry_kind):
		return false
	var farm := _farming_node()
	if farm == null:
		return false
	farm._give_starter()
	var ripe: Dictionary = {}
	var bare: Dictionary = {}
	var pest: Dictionary = {}
	var dry: Dictionary = {}
	var ripe_d := INF
	var bare_d := INF
	var pest_d := INF
	var dry_d := INF
	for p in farm.plots:
		if tending.has(p.key) or not world.village.contains(p.pos, 3.0):
			continue
		var dd: float = p.pos.distance_to(position)
		var st := farm.stage(p)
		if st == 2 and dd < ripe_d:
			ripe_d = dd
			ripe = p
		elif st == 0 and dd < bare_d and farm.plantable(p):
			bare_d = dd
			bare = p
		elif st == 1 and farm.pests(p) and dd < pest_d:
			pest_d = dd
			pest = p
		elif st == 1 and farm.dry(p) and dd < dry_d:
			dry_d = dd
			dry = p
	var goal := ripe
	planting = false
	farm_task = "harvest"
	# Tending what's growing (not with a crop in their arms: that goes to storage first).
	if goal.is_empty() and carrying == 0:
		goal = pest if not pest.is_empty() else dry
		farm_task = "pests" if not pest.is_empty() else "water"
	if goal.is_empty() and not bare.is_empty():
		var pick := farm.pick_from_storage(bare)
		if not pick[0]:
			VillageLog.problem("no-seed", "No %s in storage to plant the bare farm plots" % UiKit.resource_name(Farming.CROPS[pick[1]].seed).to_lower())
			return false
		goal = bare
		planting = true
		farm_task = "plant"
	if goal.is_empty():
		return false
	_go_to_plot(goal)
	return true


func _go_to_plot(p: Dictionary) -> void:
	plot = p
	tending[p.key] = true
	state = State.TO_FARM
	clock = 0.0
	var away: Vector2 = position - p.pos
	var dir := away.normalized() if away.length_squared() > 1.0 else Vector2(0, 1)
	_set_goal(p.pos + dir * 0.45 * world.px)


func _start_farming(t: float) -> void:
	state = State.FARM
	clock = 0.0
	var toward: Vector2 = plot.pos - position if not plot.is_empty() else Vector2(0, 1)
	facing_up = toward.y < 0.0
	facing_right = toward.x > 0.0
	_kit()
	var skill := Villagers.skill(person, LifeSkills.Skill.FARMING)
	state_until = t + lerpf(3.0, 1.2, (skill - 1) / float(LifeSkills.MOST - 1)) / _tool_pace()


# Working the soil a moment, then the crop up, or a seed in.
func _farming(t: float) -> void:
	velocity = Vector2.ZERO
	var farm := _farming_node()
	if plot.is_empty() or farm == null:
		_done_farming(t)
		return
	_show_idle()
	if t >= _next_till:
		# Pouring water as they water (the field's watering sound), else working the soil.
		var took := farm.splash(plot) if farm_task == "water" else farm.till(plot)
		_next_till = t + maxf(0.6, took) + randf_range(0.1, 0.3)
	if t < state_until:
		return
	_wear_tools()
	if farm_task == "pests" or farm_task == "water":
		if farm_task == "pests" and farm.pests(plot):
			farm.clear_pests(plot)
			show_mood("success", 2.5)
			people.practise(person, LifeSkills.Skill.FARMING)
		elif farm_task == "water" and farm.dry(plot):
			farm.water(plot, false)   # (heard while they were at it)
			people.practise(person, LifeSkills.Skill.FARMING)
		# On to the next plot close by wanting the same (the rest of the field), before anything else.
		var nxt := _next_tending(farm)
		if not nxt.is_empty():
			tending.erase(plot.key)
			_go_to_plot(nxt)
			return
		_done_farming(t)
		return
	if planting:
		if farm.plantable(plot):
			var pick := farm.pick_from_storage(plot)
			if pick[0] and world.village.take_from_stash(Farming.CROPS[pick[1]].seed, 1):
				farm.sow(plot, pick[1])
				people.practise(person, LifeSkills.Skill.FARMING)
	else:
		var kind := farm.crop(plot)
		# Arms full of another crop: that goes to storage first.
		if carrying > 0 and carry_kind != kind:
			_done_farming(t, true)
			return
		var got := farm.harvest(plot)
		if int(got[2]) > 0:
			world.village.deposit(Farming.CROPS[kind].seed, int(got[2]), plot.pos)
		if int(got[1]) > 0:
			carry_kind = kind
			carrying += int(got[1])
			people.practise(person, LifeSkills.Skill.FARMING)
	var had_load := carrying > 0 and not planting
	# Room in their arms and more ripe close by: on to it before the trip to storage.
	if had_load and carrying < _carry_most():
		var nxt := _next_ripe(farm)
		if not nxt.is_empty():
			tending.erase(plot.key)
			_go_to_plot(nxt)
			return
	_done_farming(t, had_load)


# The nearest plot (within a few units) wanting what they're doing now (pests cleared, or water), or {}.
func _next_tending(farm: Farming) -> Dictionary:
	var best := {}
	var best_d := 6.0 * world.px
	for p in farm.plots:
		if p == plot or tending.has(p.key):
			continue
		var wants: bool = farm.pests(p) if farm_task == "pests" else farm.dry(p)
		var dd: float = p.pos.distance_to(position)
		if wants and dd < best_d:
			best_d = dd
			best = p
	return best


## Whether a crop in the village wants seeing to now (pests in it, or dry), for a farmer to go to first.
func _crops_need_care() -> bool:
	var farm := _farming_node()
	if farm == null or carrying > 0 or not (_job() == Job.ANY or _job() == Job.FARMING):
		return false
	for p in farm.plots:
		if not tending.has(p.key) and (farm.pests(p) or farm.dry(p)) and world.village.contains(p.pos, 3.0):
			return true
	return false


func _next_ripe(farm: Farming) -> Dictionary:
	var best := {}
	var best_d := 6.0 * world.px
	for p in farm.plots:
		if p == plot or tending.has(p.key) or farm.stage(p) != 2 or farm.crop(p) != carry_kind:
			continue
		var dd: float = p.pos.distance_to(position)
		if dd < best_d:
			best_d = dd
			best = p
	return best


func _done_farming(t: float, store := false) -> void:
	if not plot.is_empty():
		tending.erase(plot.key)
	plot = {}
	if store and _go_store():
		return
	_stand(t, randf_range(1.0, 2.0))


# ---- Cooking: at a fire in the village, from the raw food in storage, until the kitchen's targets are met ----

func _cook_skill() -> int:
	return Villagers.skill(person, LifeSkills.Skill.COOKING)


func _go_cook() -> bool:
	var choice := _job()
	if choice != Job.ANY and choice != Job.COOKING:
		return false
	if _cook_skill() <= 0 or Kitchen.next(world.village).is_empty():
		return false
	var fires := _fires()
	if fires == null:
		return false
	var best := {}
	var best_d := INF
	var any_fire := false
	for f in fires.fires:
		if bool(f.s.torch) or not world.village.contains(f.pos, 1.0):
			continue
		any_fire = true
		if cooking_at.has(f.key):
			continue
		var dd: float = f.pos.distance_to(position) + (0.0 if fires.lit(f) else 6.0 * world.px)
		if dd < best_d:
			best_d = dd
			best = f
	if best.is_empty():
		if not any_fire:
			VillageLog.problem("no-kitchen", "Food to cook but no fire in the village: build a bonfire")
		return false
	if not fires.lit(best) and not _can_pay(best):
		VillageLog.problem("no-fuel", "Not enough wood and stone in storage to light a fire for cooking")
		return false
	stove = best
	cooking_at[stove.key] = true
	state = State.TO_COOK
	clock = 0.0
	state_until = now() + 40.0
	_set_goal(_beside(stove.pos, 0.7))
	return true


func _can_pay(f: Dictionary) -> bool:
	return world.village.stored("Wood") >= int(f.s.woodToLight) and world.village.stored("Stone") >= int(f.s.stoneToLight)


func _pay(f: Dictionary) -> bool:
	if not _can_pay(f):
		return false
	world.village.take_from_stash("Wood", int(f.s.woodToLight))
	world.village.take_from_stash("Stone", int(f.s.stoneToLight))
	return true


# Where to stand beside something: the nearest clear spot round it with a way there.
func _beside(at: Vector2, reach: float) -> Vector2:
	var best := at + Vector2(0, reach * world.px)
	var best_d := INF
	for i in 16:
		if i == 8 and best_d < INF:
			break
		var a := (i % 8) * PI / 4.0
		var r := (reach if i < 8 else reach + 0.3) * world.px
		var p := at + Vector2(cos(a) * r, sin(a) * r * 0.5)
		if UseSpots._solid(world, p):
			continue
		if world.walls != null and VillagerRoute.find(world, position, p) == null:
			continue
		var dd := position.distance_to(p)
		if dd < best_d:
			best_d = dd
			best = p
	return best


func _start_cooking(t: float) -> void:
	var fires := _fires()
	if stove.is_empty() or fires == null:
		_done_cooking(t)
		return
	# A fire gone out is lit again first, from storage.
	if not fires.lit(stove):
		if _pay(stove):
			fires.light(stove)
		else:
			VillageLog.problem("no-fuel", "Not enough wood and stone in storage to light a fire for cooking")
			_done_cooking(t)
			return
	var nxt := Kitchen.next(world.village)
	if nxt.is_empty():
		_done_cooking(t)
		return
	dish = nxt[1]
	state = State.COOK
	clock = 0.0
	dishes = 0
	var to: Vector2 = stove.pos - position
	facing_up = to.y < -0.02 * world.px
	facing_right = to.x > 0.0
	velocity = Vector2.ZERO


# One dish per run through the sheet (or 2 seconds without one); on to the next while the kitchen wants more, up to a
# batch, then off to do something else.
func _cooking(t: float, delta: float) -> void:
	velocity = Vector2.ZERO
	var fires := _fires()
	if stove.is_empty() or fires == null or not _work_hours() or _hungry():
		_done_cooking(t)
		return
	fires.keep_burning(stove)
	_sizzle_on()
	clock += delta
	var up: Array = s.cookUp
	var frames: Array = up if facing_up and not up.is_empty() else s.cookDown
	var fps := float(s.cookFps) * (1.0 + 0.06 * (maxi(1, _cook_skill()) - 1))
	var length := frames.size() / fps if not frames.is_empty() else 2.0
	if not frames.is_empty():
		_show(int(frames[mini(frames.size() - 1, int(clock * fps))]))
	else:
		_show_idle()
	if clock < length:
		return
	clock = 0.0
	var nxt := Kitchen.next(world.village)
	if not nxt.is_empty() and world.village.take_from_stash(nxt[0], 1):
		world.village.deposit(nxt[1], 1, position)
		FloatingText.spawn(world, "+1 " + UiKit.resource_name(nxt[1]), position + Vector2(0, -1.4 * world.px), Color(0.96, 0.68, 0.32))
		people.practise(person, LifeSkills.Skill.COOKING)
		dishes += 1
	if dishes >= 8 or Kitchen.next(world.village).is_empty():
		if dishes > 0:
			show_mood("success", 2.5)   # the cooking done
		_done_cooking(t)


# The pan sizzling while they cook (Miko's own recording), softer than hers.
func _sizzle_on() -> void:
	if _sizzle == null:
		var path: Variant = (_fires().d.get("cooking", {}) as Dictionary).get("sizzle")
		if not (path is String and ResourceLoader.exists(path)):
			return
		_sizzle = AudioStreamPlayer2D.new()
		_sizzle.stream = Sfx.stream(path)
		_sizzle.volume_db = linear_to_db(0.45)
		_sizzle.max_distance = 3000.0
		_sizzle.finished.connect(func(): if state == State.COOK: _sizzle.play())
		add_child(_sizzle)
	if not _sizzle.playing or _sizzle.stream_paused:
		_sizzle.pitch_scale = randf_range(0.95, 1.05)
		Sfx.keep_going(_sizzle, true)   # on from where it last stopped (no seeking into the MP3)


func _done_cooking(t: float) -> void:
	if _sizzle != null:
		Sfx.keep_going(_sizzle, false)
	if not stove.is_empty():
		cooking_at.erase(stove.key)
	stove = {}
	_stand(t, randf_range(1.0, 2.0))


# ---- Lighting the fires and torches at dusk, from storage ----

func _go_light() -> bool:
	var fires := _fires()
	if fires == null:
		return false
	var best := {}
	var best_d := INF
	for f in fires.fires:
		if fires.lit(f) or lighting.has(f.key) or not fires.tended(f):
			continue
		# A house's fireplace: only on winter evenings, for the night.
		if bool(f.s.get("hearth", false)) and not (fires.winter() and _hour(world) >= 17.5):
			continue
		var dd: float = f.pos.distance_to(position)
		if dd < best_d:
			best_d = dd
			best = f
	if best.is_empty():
		return false
	if not _can_pay(best):
		VillageLog.problem("no-fuel", "Not enough wood and stone in storage to light the %s" % ("torches" if bool(best.s.torch) else "fires"))
		return false
	fire = best
	lighting[fire.key] = true
	state = State.TO_LIGHT
	clock = 0.0
	_set_goal(_beside(fire.pos, 0.5))
	return true


func _light_it(t: float) -> void:
	var fires := _fires()
	if not fire.is_empty() and fires != null and not fires.lit(fire):
		if _pay(fire):
			fires.light(fire)
		else:
			VillageLog.problem("no-fuel", "Not enough wood and stone in storage to light the fires")
	_done_lighting(t)


func _done_lighting(t: float) -> void:
	if not fire.is_empty():
		lighting.erase(fire.key)
	fire = {}
	_stand(t, randf_range(1.0, 2.0))



# ---- Building from blueprints: ready pieces, paid for from storage ----

func _go_build() -> bool:
	var choice := _job()
	if choice != Job.ANY and choice != Job.BUILDING:
		return false
	var c := Construction.active
	if c == null:
		return false
	var t := now()
	var skip: Array = building.keys()
	for p in unreachable:
		if float(unreachable[p]) > t:
			skip.append(p)
	for tries in 4:
		var nxt := c.next(position, skip)
		if nxt.is_empty():
			return false
		var goal: Variant = _way_to(nxt)
		if goal == null:
			# Walled off from here for now (say, inside a finished room): try others, and this one again later.
			unreachable[nxt] = t + 30.0
			skip.append(nxt)
			continue
		piece = nxt
		building[piece] = true
		state = State.TO_BUILD
		clock = 0.0
		state_until = t + 40.0
		target = goal
		route = VillagerRoute.find(world, position, goal)
		leg = 0
		return true
	return false


# Where to stand to build a piece: on the tile for a floor; for a wall, beside it in whichever of the two squares it
# divides can be walked to (the nearer if both); null when neither can.
func _way_to(p: Dictionary) -> Variant:
	var at := Construction.active.position_of(p)
	var walls := world.walls
	if not bool(p.get("wall", false)) or walls == null:
		return at
	var v := Vector2i(int(p.x), int(p.y))
	var other := v - (Vector2i(1, 0) if bool(p.alongY) else Vector2i(0, 1))
	var best: Variant = null
	var best_d := INF
	var here := VillagerRoute.square_at(walls, position)
	for square in [v, other]:
		var spot := VillagerRoute.square_centre(walls, square).lerp(at, 0.45)
		if here != square and VillagerRoute.find(world, position, spot) == null:
			continue
		var dd := position.distance_to(spot)
		if dd < best_d:
			best_d = dd
			best = spot
	return best


func _start_building(t: float) -> void:
	state = State.BUILD
	clock = 0.0
	var to: Vector2 = Construction.active.position_of(piece) - position if not piece.is_empty() else Vector2(0, 1)
	facing_up = to.y < -0.02 * world.px
	facing_right = to.x > 0.0
	_kit()
	var skill := 1.0 + 0.08 * (maxi(1, Villagers.skill(person, LifeSkills.Skill.BUILDING)) - 1)
	state_until = t + (2.5 if bool(piece.get("wall", false)) else 1.6) / skill / _tool_pace()


# Hammering away a moment, then the piece paid for and put in place.
func _building(t: float) -> void:
	velocity = Vector2.ZERO
	var c := Construction.active
	if piece.is_empty() or c == null or not c.has(piece):
		_done_building(t)
		return
	var at := c.position_of(piece)
	# A puff of grey dust now and then, for the drama of it.
	if t >= _next_smoke:
		_next_smoke = t + randf_range(0.45, 0.8)
		Puffs.burst(world, at + Vector2(randf_range(-0.2, 0.2), -randf_range(0.05, 0.35)) * world.px, 0.45, 6)
	# The sound of the work: one of the building sounds, again each time the last has finished.
	var sounds: Array = s.get("buildSounds", [])
	if t >= _next_knock and not sounds.is_empty():
		var path: Variant = sounds[randi() % sounds.size()]
		if path is String and ResourceLoader.exists(path):
			var clip: AudioStream = Sfx.stream(path)
			Sfx.play(world, clip, at, float(s.toolVolume), 0.08)
			_next_knock = t + clip.get_length() + randf_range(0.1, 0.4)
	_show_idle()
	if t < state_until:
		return
	if c.build(piece):
		people.practise(person, LifeSkills.Skill.BUILDING)
		_wear_tools()
		# The last piece of what was planned: the whole building done, and everyone who built it pleased.
		if c.ready_left() == 0:
			for v in Villager.all:
				if is_instance_valid(v) and (v == self or v.state == State.BUILD or v.state == State.TO_BUILD):
					v.show_mood("success", 4.0)
			VillageLog.event("built", "The building work is finished")
	_done_building(t)


func _done_building(t: float) -> void:
	if not piece.is_empty():
		building.erase(piece)
	piece = {}
	_stand(t, randf_range(0.5, 1.5))


# ---- Repairs: a barricade worn down by monsters is mended in the day, a piece of wood from storage for each go,
# hammering as they build. One villager to a barricade; the most worn nearby first. ----

const REPAIR_COST := 1            ## wood a go at a barricade takes from storage

func _go_repair() -> bool:
	var choice := _job()
	if choice != Job.ANY and choice != Job.BUILDING:
		return false
	var walls := world.walls
	if walls == null or world.village.stored("Wood") < REPAIR_COST:
		return false
	var t := now()
	var best: Variant = null
	var best_score := INF
	for k in walls.hp:
		if mending.has(k) or not walls.walls.has(k) or float(unreachable.get(k, 0.0)) > t:
			continue
		var top := walls.max_hp(walls.walls[k])
		var left := float(walls.hp[k])
		if top <= 0.0 or left >= top:
			continue
		# Nearest first, the badly worn sooner.
		var score := position.distance_to(walls.wall_middle(k)) * (0.5 + left / top)
		if score < best_score:
			best_score = score
			best = k
	if best == null:
		return _go_mend_house(t)
	var goal: Variant = _beside_wall(best)
	if goal == null:
		unreachable[best] = t + 30.0
		return false
	mend = best
	mending[best] = true
	state = State.TO_REPAIR
	clock = 0.0
	state_until = t + 40.0
	target = goal
	route = VillagerRoute.find(world, position, goal)
	leg = 0
	return true


# A worn house (Upkeep), the worst first, with the wood and stone for a go at it in storage: off to it.
func _go_mend_house(t: float) -> bool:
	var up := Upkeep.active
	if up == null:
		return false
	var best := {}
	for h in up.houses():
		if float(h.condition) >= Upkeep.WORN or mending.has(h.key) or float(unreachable.get(h.key, 0.0)) > t:
			continue
		if best.is_empty() or float(h.condition) < float(best.condition):
			best = h
	if best.is_empty():
		return false
	var cost := Upkeep.cost(best.cells)
	if world.village.stored("Wood") < int(cost[0]) or world.village.stored("Stone") < int(cost[1]):
		VillageLog.problem("no-upkeep", "Not enough wood and stone in storage to repair a house (%d wood, %d stone)" % [cost[0], cost[1]])
		return false
	# Somewhere to stand in it that can be walked to: the cells nearest its middle first.
	var cells: Array = (best.cells as Dictionary).keys()
	var mid: Vector2 = best.middle
	cells.sort_custom(func(a, b): return world.floors.cell_centre(a).distance_squared_to(mid) < world.floors.cell_centre(b).distance_squared_to(mid))
	var goal: Variant = null
	for i in mini(5, cells.size()):
		var spot := world.floors.cell_centre(cells[i])
		if VillagerRoute.find(world, position, spot) != null:
			goal = spot
			break
	if goal == null:
		unreachable[best.key] = t + 60.0
		return false
	mend = best.key
	mending[mend] = true
	state = State.TO_REPAIR
	clock = 0.0
	state_until = t + 60.0
	target = goal
	route = VillagerRoute.find(world, position, goal)
	leg = 0
	return true


# Whether what they're mending is a house (not a barricade or gate).
func _mend_house() -> bool:
	return mend is Vector2i


# Where what they're mending is (px): a barricade's middle, or where they stand in a house.
func _mend_at() -> Vector2:
	return target if _mend_house() else world.walls.wall_middle(mend)


# Where to stand to repair the barricade at [param k]: beside its middle, on whichever side can be walked to (the
# nearer if both); null when neither can.
func _beside_wall(k: Vector3i) -> Variant:
	var walls := world.walls
	var mid := walls.wall_middle(k)
	var e := WallMap.Edge.of(k)
	var across := Vector2.RIGHT if e.along_y else Vector2.DOWN
	# (one step across, in the ground's squashed view)
	var step := (walls.vertex_position(e.vertex + (Vector2i(1, 0) if e.along_y else Vector2i(0, 1))) - walls.vertex_position(e.vertex)) * 0.55
	if step.length() < 1.0:
		step = across * 0.5 * world.px
	var best: Variant = null
	var best_d := INF
	for side in [mid + step, mid - step]:
		if VillagerRoute.find(world, position, side) == null and position.distance_to(side) > 0.6 * world.px:
			continue
		var dd := position.distance_to(side)
		if dd < best_d:
			best_d = dd
			best = side
	return best


# What they're repairing ("barricade", "gate").
func _mend_name() -> String:
	if _mend_house():
		return "house"
	var walls := world.walls
	if mend == null or walls == null or not walls.walls.has(mend):
		return "barricade"
	var type: Dictionary = walls.types[walls.walls[mend]]
	return str(type.get("display", "barricade")).to_lower().trim_prefix("open ")


func _mend_worn() -> bool:
	if _mend_house():
		return Upkeep.active != null and float(Upkeep.active.condition.get(mend, 100.0)) < 100.0 - Upkeep.A_REPAIR * 0.5
	var walls := world.walls
	return mend != null and walls != null and walls.walls.has(mend) and walls.hp.has(mend) \
		and float(walls.hp[mend]) < walls.max_hp(walls.walls[mend])


func _start_repairing(t: float) -> void:
	if not _mend_worn() or not _pay_mend():
		_done_repairing(t)
		return
	state = State.REPAIR
	clock = 0.0
	var to: Vector2 = _mend_at() - position + (Vector2(0, -0.5 * world.px) if _mend_house() else Vector2.ZERO)
	facing_up = to.y < -0.02 * world.px
	facing_right = to.x > 0.0
	_kit()
	var skill := 1.0 + 0.08 * (maxi(1, Villagers.skill(person, LifeSkills.Skill.BUILDING)) - 1)
	state_until = t + (6.0 if _mend_house() else 3.0) / skill / _tool_pace()


# The wood (and for a house, stone) a go at it takes, out of storage; false when there isn't enough.
func _pay_mend() -> bool:
	if not _mend_house():
		return world.village.take_from_stash("Wood", REPAIR_COST)
	for h in Upkeep.active.houses():
		if h.key == mend:
			var cost := Upkeep.cost(h.cells)
			if world.village.stored("Wood") < int(cost[0]) or world.village.stored("Stone") < int(cost[1]):
				return false
			world.village.take_from_stash("Wood", int(cost[0]))
			world.village.take_from_stash("Stone", int(cost[1]))
			return true
	return false


# Hammering at it a while (as they build), then its health back: all of it, or a good share when badly broken.
func _repairing(t: float) -> void:
	velocity = Vector2.ZERO
	if not _mend_worn():
		_done_repairing(t)
		return
	var walls := world.walls
	var at := _mend_at()
	if t >= _next_smoke:
		_next_smoke = t + randf_range(0.45, 0.8)
		Puffs.burst(world, at + Vector2(randf_range(-0.3, 0.3), -randf_range(0.05, 0.4)) * world.px, 0.45, 6)
	var sounds: Array = s.get("buildSounds", [])
	if t >= _next_knock and not sounds.is_empty():
		var path: Variant = sounds[randi() % sounds.size()]
		if path is String and ResourceLoader.exists(path):
			var clip: AudioStream = Sfx.stream(path)
			Sfx.play(world, clip, at, float(s.toolVolume), 0.08)
			_next_knock = t + clip.get_length() + randf_range(0.1, 0.4)
	_show_idle()
	if t < state_until:
		return
	if _mend_house():
		var now_at := Upkeep.active.repair(mend)
		FloatingText.spawn(world, "House %d%%" % roundi(now_at), at + Vector2(0, -1.4 * world.px), Color(0.55, 0.9, 0.5))
		people.practise(person, LifeSkills.Skill.BUILDING)
		_wear_tools()
		if now_at >= 99.0:
			show_mood("success", 4.0)
		_done_repairing(t)
		return
	var top := walls.max_hp(walls.walls[mend])
	var mended := minf(top - float(walls.hp[mend]), top * 0.6)
	walls.set_hp(mend, float(walls.hp[mend]) + mended)
	FloatingText.spawn(world, "+%d" % roundi(mended), at + Vector2(0, -0.9 * world.px), Color(0.55, 0.9, 0.5))
	people.practise(person, LifeSkills.Skill.BUILDING)
	_wear_tools()
	if float(walls.hp[mend]) >= top:
		show_mood("success", 4.0)
	_done_repairing(t)


func _done_repairing(t: float) -> void:
	if mend != null:
		mending.erase(mend)
	mend = null
	_stand(t, randf_range(0.5, 1.5))


# ---- Crafting: at a workbench in the village, whatever is furthest below what's to be kept in storage, out of
# what's in storage. One villager on each kind of thing at a time. ----

## How many of what [param r] makes are in storage.
func _in_storage(r: Dictionary) -> int:
	if bool(r.makesResource):
		return world.village.stored(r.resource)
	return world.village.items.count(r.item)


static func _recipe_key(r: Dictionary) -> String:
	return str(r.resource) if bool(r.makesResource) else "item:" + str(r.item)


func _storage_has(cost: Array) -> bool:
	for c in cost:
		if world.village.spare(c.resource) < int(c.amount):   # (not what's kept for planting)
			return false
	return true


func _go_craft() -> bool:
	var choice := _job()
	if choice != Job.ANY and choice != Job.CRAFTING and choice != Job.COOKING:
		return false
	var benches: Dictionary = people.d.get("workbenches", {})
	var best := {}
	var best_recipe := {}
	var best_at := Vector2.ZERO
	var worst := 1.0
	for prop in benches:
		var bench: Dictionary = benches[prop]
		var cooks: bool = bench.skill == "Cooking"
		# The cooking bench is a cook's (those who can cook); the others a crafter's.
		if (choice == Job.CRAFTING) if cooks else (choice == Job.COOKING):
			continue
		if cooks and _cook_skill() <= 0:
			continue
		var sk := LifeSkills.NAMES.find(bench.skill)
		for at in world.props_named(prop):
			if not world.village.contains(at):
				continue
			for r in bench.recipes:
				var need := 1
				if cooks and bool(r.makesResource) and r.resource in ["CarrotStew", "CabbageSoup"]:
					need = 3
				if sk >= 0 and need > Villagers.skill(person, sk):
					continue
				var key := _recipe_key(r)
				var want := Kitchen.target(key)
				if want <= 0 or crafting_now.has(key):
					continue
				var have := _in_storage(r)
				if have >= want or not _storage_has(r.cost):
					continue
				var share := have / float(want)
				if share >= worst:
					continue
				worst = share
				best = bench
				best_recipe = r
				best_at = at
	if best.is_empty():
		return false
	var spot := _beside(best_at, 0.7)
	if world.walls != null and VillagerRoute.find(world, position, spot) == null:
		return false
	craft_bench = best
	craft_at = best_at
	craft_recipe = best_recipe
	crafting_now[_recipe_key(best_recipe)] = true
	state = State.TO_CRAFT
	clock = 0.0
	_set_goal(spot)
	return true


func _start_crafting(t: float) -> void:
	if craft_recipe.is_empty() or not _storage_has(craft_recipe.cost):
		_done_crafting(t)
		return
	for c in craft_recipe.cost:
		world.village.take_from_stash(c.resource, int(c.amount))
	state = State.CRAFT
	clock = 0.0
	var toward := craft_at - position
	facing_up = toward.y < 0.0
	facing_right = toward.x > 0.0
	var sk := LifeSkills.NAMES.find(craft_bench.skill)
	var factor := 1.0 + 0.08 * (maxi(1, Villagers.skill(person, sk if sk >= 0 else LifeSkills.Skill.BUILDING)) - 1)
	state_until = t + 4.0 / factor / _tool_pace()


# Working at the bench a moment (a cook at the cooking bench cooks), then the thing made, into storage.
func _crafting(t: float, delta: float) -> void:
	velocity = Vector2.ZERO
	var up: Array = s.cookUp
	var cook_frames: Array = up if facing_up and not up.is_empty() else s.cookDown
	if craft_bench.get("skill", "") == "Cooking" and not cook_frames.is_empty():
		clock += delta
		_show(int(cook_frames[int(clock * float(s.cookFps)) % cook_frames.size()]))
	else:
		_show_idle()
	if t < state_until:
		return
	var r := craft_recipe
	if bool(r.makesResource):
		world.village.deposit(r.resource, int(r.amount), craft_at)
	elif world.village.items.size() < world.village.item_slots():
		world.village.items.append(r.item)
		world.village.changed.emit()
	var nm: String = UiKit.resource_name(r.resource) if bool(r.makesResource) else str(UiKit.item(r.item).get("name", r.item))
	FloatingText.spawn(world, "Made: " + nm, position + Vector2(0, -1.4 * world.px), Color(0.96, 0.85, 0.5))
	show_mood("success", 2.5)
	var sk := LifeSkills.NAMES.find(craft_bench.skill)
	people.practise(person, sk if sk >= 0 else LifeSkills.Skill.BUILDING)
	_done_crafting(t)


func _done_crafting(t: float) -> void:
	if not craft_recipe.is_empty():
		crafting_now.erase(_recipe_key(craft_recipe))
	craft_recipe = {}
	craft_bench = {}
	_stand(t, randf_range(1.0, 2.0))


## What they're doing right now, in a few words (the jobs window shows it).
func activity() -> String:
	var lower := func(r: String) -> String: return UiKit.resource_name(r).to_lower()
	var what := "a tree" if job != null and job.axe else "a rock"
	var made := func() -> String:
		if craft_recipe.is_empty(): return ""
		return lower.call(craft_recipe.resource) if bool(craft_recipe.makesResource) else str(craft_recipe.item).to_lower()
	var kind := "furniture" if bool(piece.get("prop", false)) else ("a wall" if bool(piece.get("wall", false)) else "a floor")
	match state:
		State.ASLEEP: return "Asleep in bed" if in_bed else "Asleep"
		State.HOME: return "Going home to bed"
		State.TO_WORK: return ("Off to fell " if what == "a tree" else "Off to mine ") + what if job != null else "Off to work"
		State.WORK: return (("Felling " if what == "a tree" else "Mining ") + what + (" (carrying %d)" % carrying if carrying > 0 else "")) if job != null else "Working"
		State.TO_STORE: return "Taking %d %s to storage" % [carrying, lower.call(carry_kind)]
		State.TO_EAT: return "Going to get something to eat"
		State.TO_MEAL: return "Taking %s off to eat" % lower.call(meal)
		State.EATING: return "Eating %s" % lower.call(meal)
		State.TO_CRAFT: return "Off to make %s" % made.call() if not craft_recipe.is_empty() else "Off to the workbench"
		State.CRAFT: return "Making %s" % made.call() if not craft_recipe.is_empty() else "Crafting"
		State.TO_DOOR: return "Opening up the house for the day" if duty_opens else "Shutting the house for the night"
		State.TO_LIGHT: return "Going to light the fire"
		State.TO_FARM: return {"plant": "Off to plant", "pests": "Off to clear pests", "water": "Off to water the crops"}.get(farm_task, "Off to harvest")
		State.FARM: return {"plant": "Planting", "pests": "Clearing pests", "water": "Watering"}.get(farm_task, "Harvesting")
		State.TO_CHAT: return "Going over to chat with %s" % partner.person.name if partner != null else "Off to chat"
		State.CHAT, State.CHAT_WAIT: return "Chatting with %s" % partner.person.name if partner != null else "Chatting"
		State.TO_BUILD: return "Off to build " + kind
		State.BUILD: return "Building " + kind
		State.TO_REPAIR: return "Off to repair the " + _mend_name()
		State.REPAIR: return "Repairing the " + _mend_name()
		State.TO_COOK: return "Off to the fire to cook"
		State.COOK: return "Cooking %s (%d/%d)" % [lower.call(dish), world.village.stored(dish), Kitchen.target(dish)]
		State.TO_PICKUP: return "Clearing up"
		State.FIGHT: return "Fighting a slime"
		State.FLEE: return "Running for their life"
		State.WALK: return "Strolling" if _work_hours() else "Free time: strolling"
	if _night(): return "Getting ready for bed"
	if _hungry() and _food_in_storage() == 0: return "Hungry: no food in storage"
	if not _work_hours(): return "Free time"
	if _job() == Job.REST: return "Resting (no work set)"
	return "Idle"
