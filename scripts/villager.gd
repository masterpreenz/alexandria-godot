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
	TO_WORK, WORK, TO_STORE, TO_PICKUP, TO_FARM, FARM, TO_COOK, COOK, TO_LIGHT, TO_BUILD, BUILD, TO_CRAFT, CRAFT, TO_REPAIR, REPAIR, FLEE, CELLAR, TO_FISH, FISH, TO_WELL, FOLLOW }

enum Job { ANY, MINING, LUMBERING, REST, FARMING, BUILDING, COOKING, CRAFTING, FISHING, HAULING }

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

## What they eat, and how much each fills. Raw meat, raw fish and slime jelly aren't food till they're cooked.
const SLEEP_MEND := 12.0        ## HP a game hour they mend asleep
const AWAKE_MEND := 6.0         ## ...and awake, out of a fight
const CALM_FOR := 8.0           ## seconds since they were last hurt before they mend awake
const HUNGRY := 35.0            ## hungry under this: mending at half
const FOODS := [["HeartyStew", 70.0], ["FishStew", 65.0], ["FishSoup", 60.0], ["Meal", 60.0], ["BakedPotato", 45.0], ["Bread", 40.0],
	["GrilledFish", 50.0], ["Candy", 35.0], ["SmokedFish", 40.0], ["Cabbage", 15.0], ["Carrot", 12.0]]   # (not potatoes raw: baked at a fire)
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
var cast_until := 0.0             ## a companion casting a spell (CompanionMagic): standing still till then...
var cast_toward := Vector2.ZERO   ## ...turned to where it goes
var dodge_to := Vector2.INF       ## a companion stepping out of a strip a monster has marked: where to...
var dodge_until := 0.0            ## ...till then at most
var melee_until := 0.0            ## a companion told by their tactics to close in hand to hand (even keeping their distance)
var hold_until := 0.0             ## a companion told by their tactics to come back to the leader: no fights till then
var repositions := 0              ## times a companion keeping their distance has moved to keep it (the scenarios read it)
var _reposition := Vector2.INF    ## where they're stepping to, keeping their distance
var _reposition_until := 0.0
var _next_reposition := 0.0
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
var _fight_after: Damageable = null   ## lighting a torch as a fight starts: what they'll fight once it's lit
const TORCH_FIRST := 4.0          ## units: an unlit torch this near, after dark, is lit before a fight
var _next_till := 0.0
var _sizzle: AudioStreamPlayer2D
var piece: Dictionary = {}        ## the blueprint piece they're building
var mend: Variant = null           ## the barricade (wall key) they're repairing, or null
var flee_from: Damageable = null   ## the monster they're running from
var _hit_at := -99.0                ## when they were last hit
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
	hit.damaged.connect(func(a):
		_hit_at = now()
		Companions.soften(person, hit, a)
		bark("bark.hurt")
		person.hp = hit.hp
		VillageLog.event("hurt:" + name, "%s is under attack!" % person.name, VillageLog.Kind.DANGER))
	hit.died.connect(func():
		# (a unique who's joined the village isn't lost: struck down, carried home, back on their feet in time)
		if person.has("unique"):
			person.hp = maxf(1.0, float(person.get("maxHp", 40.0)) * 0.2)
			VillageLog.event("died:" + name, "%s was struck down, and has been carried home" % person.name, VillageLog.Kind.DANGER)
		else:
			person.hp = 0.0
			VillageLog.event("died:" + name, "%s has died" % person.name, VillageLog.Kind.DANGER)
		move_out())
	# Their HP beside them in a fight (no mana: they've none).
	var bars := HeadBars.new()
	bars.name = "HeadBars"
	bars.setup(world, self)
	add_child(bars)
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


# Sleeping something off (Miyu, brought home): nothing gets them up till it's done.
func _resting() -> bool:
	return world.clock != null and world.clock.hours < float(person.get("restUntil", -1.0))


# Time to get up: morning (6 to 18) unless worn right out; gone to bed early (tired, from 18), not till well rested.
func _wake_time() -> bool:
	if world.clock != null and world.clock.hours < float(person.get("restUntil", -1.0)):
		return false   # (sleeping it off: Miyu, brought home)
	if Story.keeps_up():
		return true
	var h := _hour(world)
	var energy := float(person.get("energy", 100.0))
	if h < 6.0 or h >= 21.0 or energy < 20.0:
		return false
	return h < 18.0 or energy >= 60.0


# Bedtime: 21 to 6, or from 18 when worn out (and any time when exhausted).
func _night() -> bool:
	if _in_party():
		return false
	# (a raid on: nobody who can fight goes to bed, or stays there)
	if Raids.on() and not (s.stabDown as Array).is_empty() and not _low():
		return false
	if world.clock != null and world.clock.hours < float(person.get("restUntil", -1.0)):
		return true
	if Story.keeps_up():
		return false   # (the night of the attack: nobody sleeps till it's seen to)
	var h := _hour(world)
	var tired := float(person.get("energy", 100.0))
	return h >= 21.0 or h < 6.0 or (tired < 25.0 and h >= 18.0) or tired < 5.0


# ---- What's urgent: the village short of food to eat. Then getting some comes before everything but eating and
# sleeping, for everyone, whatever work they're set to (even none) and outside working hours: cooking what's raw in
# storage first (anyone, if nobody here can cook), then harvesting what's ripe, then fishing. ----

static var _short := false
static var _short_at := -1.0

## Whether the village is short of food that can be eaten as it is: less than a meal each in storage (what's kept
## for planting not counted). Looked at once a second.
static func food_short(w: World) -> bool:
	if now() - _short_at >= 1.0 or now() < _short_at:
		_short_at = now()
		var n := 0
		for f in FOODS:
			n += w.village.spare(f[0])
		_short = w.village.founded() and not all.is_empty() and n < maxi(3, all.size())
	return _short


## Raw food in storage that wants cooking before it's any use (meat, fish, slime jelly).
static func raw_to_cook(w: World) -> int:
	return w.village.stored("Food") + w.village.stored("Fish") + w.village.stored("Jelly")


func _urgent() -> bool:
	if _night() or not food_short(world):
		return false
	return _go_cook(true) or _go_farm(true) or _go_fish(true)


# ---- The job board: the village's jobs in an order (Villagers.board), each tried in turn; and before any of them
# the job this villager's been put on (dragged onto it on the board: "first"), which they do whenever there's any of
# it, whatever their boxes say. ----

func _board_work(t: float, chance: float) -> bool:
	var first := int(person.get("first", -1))
	if first > 0 and _do_job(first, t, true, 1.0):
		return true
	for j in people.board:
		if _do_job(int(j), t, false, chance):
			return true
	return false


# One job, if there's any of it to do (and, not put on it, if they're set to it and take it this time).
func _do_job(j: int, t: float, put_on: bool, chance: float) -> bool:
	var keen := put_on or randf() < chance
	match j:
		Job.BUILDING: return _go_repair(put_on) or (keen and _go_build(put_on))
		Job.HAULING: return _go_move_food(put_on) or _go_pick_up(put_on)
		Job.FARMING: return (keen or _crops_need_care()) and _go_farm(put_on)
		Job.COOKING: return keen and (_go_cook(put_on) or _go_craft(put_on, "cook"))
		Job.FISHING: return keen and _go_fish(put_on)
		Job.CRAFTING: return keen and _go_craft(put_on, "craft")
		Job.LUMBERING, Job.MINING:
			if keen and _find_work(j, put_on):
				state = State.TO_WORK
				clock = 0.0
				state_until = t + 30.0
				return true
	return false


## The job they're at now (one of Job), or -1: for the job board.
func doing() -> int:
	match state:
		State.TO_FARM, State.FARM: return Job.FARMING
		State.TO_COOK, State.COOK: return Job.COOKING
		State.TO_FISH, State.FISH: return Job.FISHING
		State.TO_BUILD, State.BUILD, State.TO_REPAIR, State.REPAIR: return Job.BUILDING
		State.TO_CRAFT, State.CRAFT: return Job.COOKING if str(craft_bench.get("skill", "")) == "Cooking" else Job.CRAFTING
		State.TO_WORK, State.WORK:
			if job != null and is_instance_valid(job):
				return Job.LUMBERING if job.axe else Job.MINING
		State.TO_PICKUP: return Job.HAULING
		State.TO_STORE: return Job.COOKING if _fetching_raw else Job.HAULING
	return -1


# ---- Water: drinking at the village's well, and a bucket filled there before watering ----

const THIRSTY := 35.0            ## they go for a drink under this
var _well := Vector2.INF         ## the well they're going to
var _well_for := ""              ## "drink" or "fill"
var _bucket := 0                 ## water in their bucket, for watering


func _wells() -> Wells:
	return Wells.active


func _go_well(why: String) -> bool:
	var w := _wells()
	if w == null:
		return false
	var at := w.nearest(position)
	if at == Vector2.INF:
		return false
	var goal := _beside(at, 0.75)
	if VillagerRoute.find(world, position, goal) == null:
		return false
	_well = at
	_well_for = why
	state = State.TO_WELL
	clock = 0.0
	state_until = now() + 40.0
	_set_goal(goal)
	return true


# At the well: a long drink, or the bucket filled; then on (a farmer back to the crops).
func _at_well(t: float) -> void:
	velocity = Vector2.ZERO
	var to := _well - position
	facing_up = to.y < 0.0
	facing_right = to.x > 0.0
	if _well_for == "drink":
		person["thirst"] = 100.0
		show_mood("relaxed", 2.0)
	else:
		_bucket = Wells.BUCKET_HOLDS
	Sfx.play(world, Sfx.stream(Farming.WATER_SOUND), _well, 0.35, 0.1)
	var was := _well_for
	_well = Vector2.INF
	_well_for = ""
	if was == "fill" and _go_farm(true):
		return
	_stand(t, randf_range(0.6, 1.2))


# ---- In Sera's party: following her, fighting beside her, an errand when she asks ----

var _next_follow := 0.0


func _in_party() -> bool:
	return Party.active != null and Party.active.has_member(person)


func _follow_start(t: float) -> void:
	state = State.FOLLOW
	clock = 0.0
	_next_follow = 0.0
	state_until = t


func _following(t: float, delta: float) -> void:
	if not _in_party():
		_stand(t, 0.5)
		return
	var me: Node2D = world.player
	var at := Party.active.spot_for(person)
	# (a strip a monster has marked over where they'd stand: they wait out of it till it's gone)
	if not Telegraph.live.is_empty() and Tactics.strip_at(at) != null and Tactics.strip_at(position) == null:
		velocity = Vector2.ZERO
		_show_idle()
		return
	var far := position.distance_to(at)
	# A long way behind (she teleported, or ran off): brought up to her.
	if me != null and position.distance_to(me.position) > Party.CATCH_UP * world.px and not Party.active.waiting.has(str(person.unique)):
		position = at
		reset_physics_interpolation()
		route = null
		far = 0.0
	if far < 0.5 * world.px:
		velocity = Vector2.ZERO
		if me != null:
			var to := me.position - position
			facing_right = to.x > 0.0
			facing_up = to.y < 0.0
		_show_idle()
		return
	# After her: the way found again now and then as she moves; quicker when she's pulling away.
	if t >= _next_follow:
		_next_follow = t + 0.4
		_set_goal(at)
	_walk(t, delta)
	state = State.FOLLOW   # (walking there isn't arriving anywhere)


# The monster nearest Sera (or them) going for either: a party member's fight. (Told back to the leader by their
# tactics: none for now. A defender's leash keeps them to what's near the leader, and what's right on them.)
func _party_threat() -> Damageable:
	if (s.stabDown as Array).is_empty() or world.player == null or now() < hold_until:
		return null
	var me: Vector2 = world.player.position
	var best: Damageable = null
	var leash := float(Tactics.stance(person).get("leash", Party.GUARD))
	if leash < Party.GUARD:
		var close := _danger(1.5)
		if close != null:
			return close
	var best_d := minf(leash, Party.GUARD) * world.px
	for d in Damageable.all:
		if not d.alive() or not d.get_parent() is Creature:
			continue
		var c: Creature = d.get_parent()
		if c is Rabbit:
			continue
		var near := minf(d.global_position.distance_to(me), d.global_position.distance_to(position))
		if near < best_d and (c.hostile() or near < 3.0 * world.px):
			best_d = near
			best = d
	return best


## Sera's errand: the nearest tree or rock to her, chopped or mined; what it gives into her bag. Whether there was one.
func errand_gather() -> bool:
	if world.player == null:
		return false
	var best: Gatherable = null
	var best_d := 8.0 * world.px
	for g: Gatherable in Gatherable.near(world.player.position, best_d):
		if not is_instance_valid(g) or g.depleted() or claimed.has(g):
			continue
		var dd := g.foot.distance_to(world.player.position)
		if dd < best_d:
			best_d = dd
			best = g
	if best == null:
		return false
	job = best
	claimed[job] = true
	state = State.TO_WORK
	clock = 0.0
	state_until = now() + 30.0
	_set_goal(_work_spot(job))
	return true


func _work_hours() -> bool:
	var h := _hour(world)
	return h >= 6.0 + Traits.add(person, "start") and h < 18.0 + Traits.add(person, "end")


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


## Held by the story (the messenger running to Sera): their own day set aside; the story moves them.
var held := false
var _held_moving := false


func _physics_process_timed(delta: float) -> void:
	var t := now()
	if held:
		velocity = Vector2.ZERO
		var frames: Array = s.walkUp if facing_up else s.walkDown
		if _held_moving and not frames.is_empty():
			_show(int(frames[int(t * _walk_fps()) % frames.size()]))
		else:
			_show_idle()
		_status()
		return
	var __t := Time.get_ticks_usec()
	_needs()
	Perf.add(&"villager: needs", __t)
	__t = Time.get_ticks_usec()
	_unstick(t, delta)
	_close_behind()
	_status()
	Perf.add(&"villager: unstick, doors, status", __t)
	# Talking with Miko: standing still, facing her.
	if talking and world.player != null:
		velocity = Vector2.ZERO
		var to := world.player.position - position
		facing_right = to.x > 0.0
		facing_up = to.y < 0.0
		_show_idle()
		return
	# Out of a strip a monster has marked (a companion's tactics): straight out of it, quickly.
	if t < dodge_until and dodge_to != Vector2.INF:
		if _step_to(dodge_to, delta, 1.7):
			dodge_until = 0.0
			dodge_to = Vector2.INF
		move_and_slide()
		return
	# Casting a spell (a companion with magic): a moment standing still, turned to it, arms up.
	if t < cast_until:
		velocity = Vector2.ZERO
		var aim := cast_toward - position
		if aim.length() > 1.0:
			facing_right = aim.x > 0.0
			facing_up = aim.y < 0.0
		var up: Array = s.get("stabUp", [])
		var down: Array = s.get("stabDown", [])
		var pose: Array = up if facing_up and not up.is_empty() else down
		if pose.is_empty(): _show_idle()
		else: _show(int(pose[0]))
		return
	# Stepping to keep their distance from the monsters (a companion fighting from range): there, then still again.
	if _reposition != Vector2.INF:
		if t > _reposition_until or not _in_party() or _step_to(_reposition, delta, 1.0):
			_reposition = Vector2.INF
			velocity = Vector2.ZERO
		else:
			move_and_slide()
			return
	# A slime about: go for it (unless asleep, or already at one).
	# Badly hurt (under a fifth of their health) with a monster near: they run instead.
	# A raid: everyone's up and out of whatever they were at (the sleeping too), to fight.
	# (not someone sleeping off an ordeal: Miyu, brought home)
	if Raids.on() and (state == State.ASLEEP or state == State.CELLAR) and not (s.stabDown as Array).is_empty() and not _low() and not _resting():
		if state == State.ASLEEP: _wake_up(t)
		_stand(t, 0.0)
	if state != State.ASLEEP and state != State.FIGHT and state != State.FLEE and not (state == State.TO_LIGHT and _fight_after != null) and t >= next_look:
		next_look = t + 0.5
		var __tl := Time.get_ticks_usec()
		var danger := _danger() if _low() else null
		# Out of the village and in a fight: the village hears of it, and they call out.
		if not world.village.contains(position, 1.0) and world.village.founded() and t >= _threat_told:
			# (only once it's a fight: they've just been hit, or they're fighting or running)
			if t - _hit_at < 6.0 or state == State.FIGHT or state == State.FLEE:
				_threat_told = t + 20.0
				VillageLog.problem("threat:" + name, "%s is in danger outside the village: under attack" % person.name, VillageLog.Kind.DANGER)
				bark("bark.threat", {}, true)
				show_mood("alarm", 4.0)
		if danger != null:
			_flee(danger)
		else:
			var threat := _threat() if not _low() else null
			if threat != null:
				_fight(threat)
		Perf.add(&"villager: looking for danger", __tl)
	__t = Time.get_ticks_usec()
	if t >= _next_dusk_look:
		_next_dusk_look = t + 2.0 + randf()
		_answer_dusk(t)
	var __deciding := state == State.STAND   # (standing: choosing what to do next; anything else: going about it)
	match state:
		State.STAND:
			velocity = Vector2.ZERO
			if _night() and not home.is_empty():
				_go_home()
			elif t >= state_until:
				var chance := float(s.workChance)
				# Three meals a day; between them only when they're close to starving.
				if _in_party(): _follow_start(t)
				elif (_meal_due() or float(person.get("hunger", 100.0)) < 12.0) and _go_eat(): pass
				elif float(person.get("thirst", 100.0)) < THIRSTY and _go_well("drink"): pass
				# (the village short of food: whoever can sees to it first, whatever their work's set to and the hour)
				elif _urgent(): pass
				elif _go_door_duty(): pass
				# (in winter the fires and torches are kept burning all day: lit again as each burns down)
				elif (_hour(world) >= 17.5 or (_fires() != null and _fires().winter() and not _night())) and _go_light(): pass
				elif not _work_hours() and not _night() and randf() < 0.45 * Traits.mul(person, "chat") and _go_chat(t): pass
				# (work: the job they've been put on first, then each in the job board's order)
				elif _work_hours() and _board_work(t, chance): pass
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
		State.CELLAR:
			_in_cellar(t)
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
		State.TO_FISH:
			if _night() or fish_dock == Vector2.INF or t > state_until: _done_fishing(t)
			else: _walk(t, delta)
		State.FISH:
			_fishing(t)
		State.TO_WELL:
			if t > state_until: _stand(t, 1.0)
			else: _walk(t, delta)
		State.FOLLOW:
			_following(t, delta)
	Perf.add(&"villager: deciding what to do" if __deciding else &"villager: going about it (walking, working)", __t)
	# Called off cooking any other way (a slime, bedtime): the pan goes quiet.
	if state != State.COOK and _sizzle != null and _sizzle.playing and not _sizzle.stream_paused:
		Sfx.keep_going(_sizzle, false)
	if not in_bed:
		__t = Time.get_ticks_usec()
		_keep_out_of_mist(t, delta)
		move_and_slide()
		Perf.add(&"villager: moving (physics)", __t)


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
		_show(int(frames[int(clock * _walk_fps()) % frames.size()]))
	var speed := float(s.walkSpeed) * world.px * (1.7 if state == State.FLEE else 1.0) * Traits.mul(person, "speed")   # (running for it)
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
		if state == State.TO_FISH:
			if fish_dock != Vector2.INF and position.distance_to(fish_dock) < 1.8 * world.px: _arrive(t)
			else: _done_fishing(t)
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
		State.TO_EAT:
			if _via_cellar: _go_down(t, "eat")
			else: _eat(t)
		State.TO_MEAL: _start_eating(t)
		State.TO_DOOR: _see_to_door(t)
		State.TO_CHAT: _start_chat(t)
		State.TO_WORK: _start_work(t)
		State.TO_STORE:
			if _via_cellar: _go_down(t, "raw" if _fetching_raw else "store")
			elif _fetching_raw: _take_raw(t)
			elif _fetching_food: _fetch_food(t)
			else: _unload(t)
		State.TO_PICKUP: _pick_up(t)
		State.TO_FARM: _start_farming(t)
		State.TO_COOK: _start_cooking(t)
		State.TO_LIGHT: _light_it(t)
		State.TO_BUILD: _start_building(t)
		State.TO_REPAIR: _start_repairing(t)
		State.FLEE: _next_refuge = 0.0   # (somewhere further next: still running)
		State.TO_CRAFT: _start_crafting(t)
		State.TO_FISH: _start_fishing(t)
		State.TO_WELL: _at_well(t)
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
		State.TO_STORE, State.TO_PICKUP, State.TO_FARM, State.TO_COOK, State.TO_LIGHT, State.TO_BUILD, State.TO_CRAFT, State.TO_REPAIR, State.FLEE, State.TO_FISH, State.TO_WELL]


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


# How fast their walking frames go: a look's back-facing run may have its own pace (walkFpsUp: fewer or more frames
# than its front, the same stride).
func _walk_fps() -> float:
	return float(s.walkFpsUp) if facing_up and s.has("walkFpsUp") else float(s.walkFps)


func _show(id: int) -> void:
	var k := _scale()
	world.show_frame(art, id, Vector2(-k if facing_right else k, k))


# How big they're drawn: their look's scale (villagers are scaled to Miko's size, as she is).
func _scale() -> float:
	return World.BODY_SCALE   # one scale for every person (villagers.json's look scale no longer counts)


# Something to tell Miko (a rumor), shown over their head while they're up and about with nothing else showing; or a
# story scene of theirs waiting (the elder handing over the village), shown over whatever they're doing, at home too.
func _rumor_emote() -> String:
	if state == State.ASLEEP or state == State.CELLAR:
		return ""
	if _scene_waiting():
		return "quest"
	if Rumors.active == null or state == State.HOME:
		return ""
	return "quest" if Rumors.active.has_offer(self) else ""


# Whether a story scene's waiting for Sera to talk to them.
func _scene_waiting() -> bool:
	return person.has("unique") and not Scenes.for_speaker(person).is_empty()


func _show_idle() -> void:
	# (a look with its own idle animation plays it; else the one frame)
	var anim: Array = s.get("idleUpAnim" if facing_up else "idleDownAnim", [])
	if not anim.is_empty():
		_show(int(anim[int(now() * float(s.get("idleFps", 6))) % anim.size()]))
		return
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
## (SleepTune: x, y px and degrees by which way the bed faces, mirrored with them).
func lie_in_bed() -> void:
	var lying: Variant = look.get("lying", {}).get(sleep_pose())
	var lie: Array = Needs.lie_on_bed(world, home, lying, facing_right, 1.0)
	var tune := SleepTune.of(facing_right)
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


# ---- Fishing: at a dock on cleared ground: a cast at a time (slower in winter), up to a good haul, then home with
# the fish. One villager to a dock. ----

const READ_ONE_WAY := ["quest", "excl", "note", "mood.info", "mood.idea", "mood.alarm"]   ## emotes never mirrored (a "?" backwards is wrong)
const VILLAGER_WAIT := 3.0       ## how many times longer than Miko's a villager's cast takes (about 18 seconds a cast)
const FISH_HAUL := 10            ## fish they bring back at most (as many as they can carry, if that's fewer)

var fish_dock := Vector2.INF     ## the dock they're fishing (px), or INF
var _caught_until := 0.0         ## the caught-one emote shows till then
var _fish_from := 0.0            ## when this cast began
var _fish_water := Vector2.ZERO  ## where their float sits (px)
var _fish_line: FishingLine

func _go_fish(urgent := false) -> bool:
	if not able(person, Job.FISHING) or (not urgent and not _wants(Job.FISHING)):
		return false
	var f := Fishing.active
	if f == null or carrying > 0 or Kitchen.stocked(world.village, "Fish"):
		return false
	var best := Vector2.INF
	var best_d := INF
	for at in f.village_docks():
		var by: Variant = Fishing.taken.get(at)
		if by != null and is_instance_valid(by) and by != self and (by.state == State.TO_FISH or by.state == State.FISH):
			# (put on fishing on the job board, they have the dock over someone who only happened to take it: that
			# one goes home with what they've caught)
			if int(person.get("first", -1)) != Job.FISHING or int(by.person.get("first", -1)) == Job.FISHING:
				continue
			by._done_fishing(now())
		var dd: float = at.distance_to(position)
		if dd < best_d:
			best_d = dd
			best = at
	if best == Vector2.INF:
		return false
	# (out on its planks: the dock's walked onto, not stood beside)
	var goal := f.stand_at(best)
	if not _safe_way_to(goal) or VillagerRoute.find(world, position, goal) == null:
		return false
	fish_dock = best
	Fishing.taken[best] = self
	state = State.TO_FISH
	clock = 0.0
	state_until = now() + 180.0
	_set_goal(goal)
	return true


func _start_fishing(t: float) -> void:
	if fish_dock == Vector2.INF:
		_done_fishing(t)
		return
	state = State.FISH
	clock = 0.0
	carry_kind = "Fish"
	_fish_water = Fishing.water_spot(world, fish_dock, position)
	var to: Vector2 = _fish_water - position
	facing_up = to.y < -0.02 * world.px
	facing_right = to.x > 0.0
	_fish_from = t
	state_until = t + _cast_time()


# How long one of their casts takes: slower than Miko's, quicker with skill.
func _cast_time() -> float:
	return Fishing.active.cast_time(Villagers.skill(person, LifeSkills.Skill.FISHING) + int(Traits.add(person, "fishing"))) * VILLAGER_WAIT / _tool_pace()


# Waiting on the line; then, most times, a fish; again till there's a haul.
func _fishing(t: float) -> void:
	velocity = Vector2.ZERO
	_show_fishing(t)
	if _night() or (not _work_hours() and not food_short(world)) or fish_dock == Vector2.INF:
		_done_fishing(t)
		return
	if t < state_until:
		return
	var n := Fishing.catch_now(Villagers.skill(person, LifeSkills.Skill.FISHING) + int(Traits.add(person, "fishing")))
	people.practise(person, LifeSkills.Skill.FISHING)
	if n > 0:
		carrying = mini(_carry_most(), carrying + n)
		_caught_until = t + Fishing.CAUGHT_SHOWS
		FloatingText.spawn(world, "+%d Fish" % n, position + Vector2(0, -2.0 * world.px), Color(0.6, 0.85, 1.0))
	if carrying >= mini(FISH_HAUL, _carry_most()):
		_done_fishing(t)
		return
	_fish_from = t
	state_until = t + _cast_time()


# Fishing as their look has it drawn (the cast, then waiting on it), the line and float out from the rod's tip; with
# no such art, standing there.
func _show_fishing(t: float) -> void:
	var frames: Array = s.get("fishUp" if facing_up else "fishDown", [])
	if frames.is_empty():
		_show_idle()
		return
	var since := t - _fish_from
	var i := Fishing.cast_frame(since, frames.size())
	_show(int(frames[i]))
	if _fish_line == null:
		_fish_line = Fishing.new_line(world)
		_fish_line.keep = func(): return is_instance_valid(self) and state == State.FISH
	var tip: Array = s.get("fishTipsUp" if facing_up else "fishTipsDown", [])[i]
	var k: float = world.px / float(world.sprites[int(frames[i])].ppu) * _scale()
	Fishing.draw_line_from(world, _fish_line, position + Vector2(-float(tip[0]) if facing_right else float(tip[0]), float(tip[1])) * k, _fish_water, since, state_until - t, t)


# Home with what they caught (to the cellar, where there is one).
func _done_fishing(t: float) -> void:
	if fish_dock != Vector2.INF:
		Fishing.taken.erase(fish_dock)
	fish_dock = Vector2.INF
	if carrying > 0 and _go_store():
		return
	_stand(t, randf_range(0.5, 1.5))


# ---- Down the cellar: at its doors they go down (they're in its room a moment, among its shelves), then come back
# up where they went in, and what they came for is done: the food they carried put away, or a meal fetched. ----

var _via_cellar := false         ## on their way to the cellar's doors (not a chest)
var _cellar_from := Vector2.ZERO
var _cellar_for := ""

var _fetching_food := false     ## off to a chest for food to carry down the cellar

# Food still up in the chests, and room for it down the cellar: off to a chest for a load of it (one villager at it
# at a time), then down the cellar with it.
func _go_move_food(put_on := false) -> bool:
	var c := Cellars.active
	if not able(person, Job.HAULING) or (not put_on and not _wants(Job.HAULING)) or c == null or carrying > 0 or not movers_free() or c.to_move() <= 0 or c.deposit_spot(position) == null:
		return false
	var spot: Variant = UseSpots.nearest_chest_spot(world, position)
	if spot == null:
		return false
	_fetching_food = true
	_via_cellar = false
	Cellars.movers[self] = true
	state = State.TO_STORE
	clock = 0.0
	_set_goal(spot)
	return true


func movers_free() -> bool:
	for v in Cellars.movers.keys():
		if not is_instance_valid(v) or (v.state != State.TO_STORE and v.state != State.CELLAR):
			Cellars.movers.erase(v)
	return Cellars.movers.size() < 2   # (two at it at most)


# At the chest: a load of whatever food there's most of, then off to the cellar with it.
func _fetch_food(t: float) -> void:
	_fetching_food = false
	var v := world.village
	var most := ""
	for r in Spoilage.PER_DAY:
		if v.stored(r) > 0 and (most == "" or v.stored(r) > v.stored(most)):
			most = r
	var n := mini(mini(_carry_most(), Cellars.active.to_move()), v.stored(most) if most != "" else 0)
	if n <= 0 or not v.take_from_stash(most, n):
		Cellars.movers.erase(self)
		_stand(t, 1.0)
		return
	carrying = n
	carry_kind = most
	if not _go_store() or not _via_cellar:
		# (no way to the cellar after all: back it goes)
		Cellars.movers.erase(self)
		_unload(t)


func _go_down(t: float, what: String) -> void:
	_via_cellar = false
	_cellar_from = position
	_cellar_for = what
	Cellars.active.use_doors(position)
	state = State.CELLAR
	clock = 0.0
	velocity = Vector2.ZERO
	state_until = t + randf_range(2.0, 3.0)
	position = Cellars.active.stand_spot()
	reset_physics_interpolation()
	steer.reset()
	facing_up = true
	_show_idle()


func _in_cellar(t: float) -> void:
	velocity = Vector2.ZERO
	_show_idle()
	if t < state_until:
		return
	position = _cellar_from
	reset_physics_interpolation()
	# (a jump, not a walk: the steering's watch on their progress starts afresh, or it takes them for stuck and
	# whatever they came up to do next is given up at once)
	steer.reset()
	_stuck_from = position
	_trying_for = 0.0
	facing_up = false
	Cellars.active.use_doors(position)
	if _cellar_for == "store":
		# What they carried down is in the cold now.
		if Spoilage.PER_DAY.has(carry_kind):
			Cellars.active.put(carrying)
		Cellars.movers.erase(self)
		_unload(t)
	elif _cellar_for == "raw":
		_take_raw(t)
	else:
		_eat(t)


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
	# (their traits: thick-skinned don't feel it, thin-blooded feel it worse)
	return clampi(cold - (1 if bool(person.get("scarf", false)) else 0) + int(Traits.add(person, "cold")), 0, 2)


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
				VillageLog.event("scarf:" + name, "%s took a scarf from storage" % person.name)
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
	if dh <= 0.0 or _in_party():
		return   # (out with Sera, she looks after them: for now their needs wait)
	var p := person
	var sleeping := state == State.ASLEEP
	# A night's sleep leaves them hungry for breakfast, but never starving.
	var hunger := float(p.hunger)
	p.hunger = maxf(minf(hunger, 15.0), hunger - 7.0 * dh) if sleeping else maxf(0.0, hunger - 4.0 * dh * Traits.mul(p, "hunger"))
	var thirst := float(p.get("thirst", 100.0))
	p["thirst"] = maxf(minf(thirst, 25.0), thirst - 2.5 * dh) if sleeping else maxf(0.0, thirst - 5.0 * dh)
	if float(p.thirst) < THIRSTY and _wells() != null and _wells().village().is_empty() and world.village.founded():
		VillageLog.problem("no-well", "The villagers are thirsty: build a well in the village")
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
	# Mending over time: best asleep (not on a cold night), slower awake once they're out of a fight a while; not
	# while starving or parched, and half as fast hungry or thirsty.
	if float(p.hunger) > 0.0 and float(p.thirst) > 0.0 and hit.hp < hit.max_hp:
		var healing := 0.0
		if sleeping and not cold_night:
			healing = SLEEP_MEND
		elif not sleeping and state != State.FIGHT and state != State.FLEE and Time.get_ticks_msec() / 1000.0 - hit._last_hit > CALM_FOR:
			healing = AWAKE_MEND
		if float(p.hunger) < HUNGRY or float(p.thirst) < THIRSTY:
			healing *= 0.5
		hit.heal(healing * dh)
	if float(p.hunger) <= 0.0:
		# Starving: HP slips away.
		var loss := 2.0 * dh
		if hit.hp - loss <= 0.5:
			hit.hurt(loss)
		else:
			hit.hp -= loss
		VillageLog.problem("starving:" + name, "%s is starving: put food in storage" % person.name, VillageLog.Kind.DANGER)
	p.hp = hit.hp
	if hit.alive() and hit.hp < hit.max_hp * 0.3:
		VillageLog.problem("dying:" + name, "%s is badly hurt (%d HP)" % [person.name, ceili(hit.hp)], VillageLog.Kind.DANGER)


func _food_in_storage() -> int:
	var n := 0
	for f in FOODS:
		n += world.village.spare(f[0])   # (not what's kept for planting)
	return n


# Off to the nearest chest in the village, if there's food in storage.
func _go_eat() -> bool:
	if _food_in_storage() == 0:
		var raw := raw_to_cook(world)
		VillageLog.problem("no-food", ("Nothing cooked in storage: %d raw to cook first (meat, fish, jelly)" % raw) if raw > 0 else "No food in storage: the villagers are hungry")
		return false
	var spot: Variant = UseSpots.nearest_chest_spot(world, position)
	# The food's down the cellar, where there is one.
	_via_cellar = false
	if Cellars.active != null:
		var cellar: Variant = Cellars.active.deposit_spot(position)
		if cellar != null and VillagerRoute.find(world, position, cellar) != null:
			spot = cellar
			_via_cellar = true
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
	if key in ["party.hungry", "party.thirsty"]:
		return SpeechBubble.Kind.SAY
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
	# (with Sera: they don't stop to eat or drink on the road, so they ask her)
	if _in_party() and t >= _next_need_bark:
		_next_need_bark = t + randf_range(40.0, 60.0)
		var needs := {"miko": Playable.name_now()}
		# (from their own bag first, if they've anything: only asking her when they haven't)
		if Party.active != null and Party.active.look_after(person):
			_next_need_bark = t + 5.0
		elif float(person.get("hunger", 100.0)) < Party.NEEDY:
			bark("party.hungry", needs, true)
		elif float(person.get("thirst", 100.0)) < Party.NEEDY:
			bark("party.thirsty", needs, true)
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
		State.TO_FARM, State.FARM: e = {"pests": "pests", "water": "watering", "plant": "planting", "harvest": "harvesting"}.get(farm_task, "")
		State.BUILD: e = "building"
		State.TO_REPAIR, State.REPAIR: e = "repairing"
		State.FLEE: e = "crying"
		State.FISH: e = "fishing_caught" if now() < _caught_until else "fishing"
		State.CRAFT:
			if craft_bench.get("skill", "") == "Cooking": e = "cooking"
			elif str(craft_bench.get("title", "")).contains("Alchemy"): e = "alchemy"
			else: e = "workbench"
		_:
			if state != State.ASLEEP and hit.hp < hit.max_hp * 0.35:
				e = "sick"
	if e == "" or _scene_waiting():
		var told := _rumor_emote()
		if told != "" or e == "":
			e = told
	_emote(e)


## The frame of an emote's animation showing now (160 ms a frame), or -1 if there's no art for it.
func _emote_frame(e: String) -> int:
	var frames: Array = people.d.get("emotes", {}).get(e, [])
	if frames.is_empty():
		return -1
	if e == "fishing_caught":   # (played once, not round and round)
		return int(frames[Fishing.once(frames.size(), now() - (_caught_until - Fishing.CAUGHT_SHOWS))])
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
		var icon_in := Sprite2D.new()
		icon_in.visibility_layer |= LightMap.UNLIT_LAYER   # (as drawn: not lit again by the torches)
		emote.add_child(icon_in)
		emote.visibility_layer |= LightMap.UNLIT_LAYER
		add_child(emote)
	emote.visible = true
	emote.modulate = world.daylight_undo()   # as drawn, whatever the hour (the evening's tint would grey it)
	var info: Dictionary = world.sprites[id]
	var k := EMOTE_WIDTH * world.px / float(info.rect[2])
	world.show_frame(emote, id, Vector2.ONE * k * float(info.ppu) / world.px)
	emote.flip_h = not facing_right and not e in READ_ONE_WAY  # the tail towards their head (not what would read backwards)
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
		var icon_in := Sprite2D.new()
		icon_in.visibility_layer |= LightMap.UNLIT_LAYER   # (as drawn: not lit again by the torches)
		emote.add_child(icon_in)
		emote.visibility_layer |= LightMap.UNLIT_LAYER
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
## Whether [param at] is somewhere others need to get by: a doorway or gate, the way up to a chest, the cellar's
## doors. Nobody stops there to talk.
static func in_the_way(w: World, at: Vector2) -> bool:
	if w.walls != null and not w.walls.nearest_door(at, 1.6 * w.px).is_empty():
		return true
	var chest: Variant = UseSpots.nearest_chest_spot(w, at)
	if chest != null and (chest as Vector2).distance_to(at) < 1.5 * w.px:
		return true
	if Cellars.active != null:
		var cellar: Variant = Cellars.active.deposit_spot(at)
		if cellar != null and (cellar as Vector2).distance_to(at) < 1.6 * w.px:
			return true
	return false


func _go_chat(t: float) -> bool:
	if (s.emojis as Array).is_empty():
		return false
	var best: Villager = null
	var best_d := 9.0 * world.px
	for v in all:
		if v == self or v.partner != null or not v._free() or not v.visible:
			continue
		# (not with someone standing in a doorway or by the storage: the two of them would block it)
		if in_the_way(world, v.position):
			continue
		var dd := v.position.distance_to(position)
		if dd < best_d:
			best_d = dd
			best = v
	if best == null:
		return false
	var away := position - best.position
	var beside := best.position + (away.normalized() if away.length_squared() > 1.0 else Vector2.RIGHT) * 0.75 * world.px
	# (nor would this one stand in the way: the other side of them, or not at all)
	if in_the_way(world, beside):
		beside = best.position - (beside - best.position)
		if in_the_way(world, beside):
			return false
	partner = best
	best.partner = self
	# They wait while this one comes over.
	best.state = State.CHAT_WAIT
	best.chat_until = t + 20.0
	best.velocity = Vector2.ZERO
	state = State.TO_CHAT
	clock = 0.0
	_set_goal(beside)
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
	if _in_party():
		return _party_threat()
	var best: Damageable = null
	var raid := Raids.on()
	# (a raid: the nearest of the horde, wherever it is; else a monster in the village and near them or their home)
	var best_d := INF if raid else float(s.guardRange) * world.px
	for d in Damageable.all:
		if not d.alive():
			continue
		var of_raid := raid and Raids.raider(d.get_parent())
		if not of_raid and not d.get_parent() is Slime:
			continue
		var at := d.global_position
		if not of_raid and not world.village.contains(at):
			continue
		if of_raid and not world.village.contains(at, 10.0):
			continue   # (not chased off into the mist: met as they come in)
		var near := minf(at.distance_to(position), at.distance_to(_home_at()))
		if near < best_d:
			best_d = near
			best = d
	return best


func _fight(threat: Damageable) -> void:
	if partner != null:
		_end_chat(now())
	# After dark, an unlit torch close by: lit first, so there's light to fight by (unless it's on them already).
	if _fight_after == null and _torch_first(threat):
		return
	_fight_after = null
	if job != null:
		claimed.erase(job)
		job = null
	foe = threat
	state = State.FIGHT
	clock = 0.0
	last_frame = -1
	next_chase = 0.0


# The nearest unlit torch within [constant TORCH_FIRST] units, after dark, while [param threat] isn't right on them:
# off to light it, the fight after. Whether they went.
func _torch_first(threat: Damageable) -> bool:
	if not (_night() or _hour(world) >= 17.5) or (threat != null and threat.global_position.distance_to(position) < 1.5 * world.px):
		return false
	var fires := _fires()
	if fires == null:
		return false
	var best := {}
	var best_d := TORCH_FIRST * world.px
	for f in fires.fires:
		if not bool(f.s.get("torch", false)) or fires.lit(f) or lighting.has(f.key) or not fires.tended(f):
			continue
		var dd: float = f.pos.distance_to(position)
		if dd < best_d:
			best_d = dd
			best = f
	if best.is_empty() or not _can_pay(best):
		return false
	if job != null:
		claimed.erase(job)
		job = null
	fire = best
	lighting[fire.key] = true
	_fight_after = threat
	state = State.TO_LIGHT
	clock = 0.0
	_set_goal(_beside(fire.pos, 0.5))
	return true


func _fighting(t: float, delta: float) -> void:
	# Too badly hurt to keep at it: off they run.
	if _low():
		var danger := _danger()
		if danger != null:
			_flee(danger)
			return
	# Gone, or out of the village (they don't follow it out): back to it.
	# (a raid: met wherever they come into the village, not only near home)
	var raid := foe != null and is_instance_valid(foe) and ((Raids.on() and Raids.raider(foe.get_parent())) or _in_party())
	if foe == null or not is_instance_valid(foe) or not foe.alive() or (not _in_party() and not world.village.contains(foe.global_position, 10.0 if raid else 0.5)) \
			or (not raid and foe.global_position.distance_to(_home_at()) > float(s.chaseRange) * world.px) \
			or (_in_party() and world.player != null and foe.global_position.distance_to(world.player.position) > Party.GUARD * 1.8 * world.px):
		foe = null
		_stand(t, randf_range(1.0, 2.0))
		return
	# A companion's tactics: back to the leader when told; kept at a distance when that's their stance.
	if _in_party():
		if t < hold_until:
			foe = null
			_follow_start(t)
			return
		if t >= melee_until and Tactics.keeps_distance(person):
			_keep_distance(t)
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
				SpellEffects.WaterBlanket.struck(self, foe)   # (wrapped with Cold Comfort: the cold bites what they hit)
				# The thrust heard going in: the spear's own stab.
				Sfx.play(world, Sfx.stream("res://assets/Sounds/shiki_spear_stab.mp3"), position, 0.55, 0.1)   # (their spear: its own stab, not a sword's swing)
				people.practise(person, LifeSkills.Skill.STRENGTH)
	last_frame = frame


# A companion fighting from range: still, turned to the monster, casting (their magic does that); a step back when it
# comes too close, nearer when it's too far for their spells; no more than a step every so often, never mid-spell.
func _keep_distance(t: float) -> void:
	velocity = Vector2.ZERO
	var to := foe.global_position - position
	facing_up = to.y < 0.0
	facing_right = to.x > 0.0
	_show_idle()
	if t < _next_reposition:
		return
	var td := Tactics.data()
	var near := float(td.get("keepNear", 4.0)) * world.px
	var far := float(td.get("keepFar", 6.0)) * world.px
	var d := to.length()
	if d < near:
		step_back(foe.global_position, t)
	elif d > far:
		_move_for_distance(foe.global_position - to.normalized() * (near + far) * 0.5, t)


## A step back from [param from] (a monster come close) to where they'd keep their distance, leaning towards the
## leader rather than away from everyone; not while casting, nor again too soon. Whether they went.
func step_back(from: Vector2, t: float) -> bool:
	if t < _next_reposition or t < cast_until or _reposition != Vector2.INF:
		return false
	var td := Tactics.data()
	var mid := (float(td.get("keepNear", 4.0)) + float(td.get("keepFar", 6.0))) * 0.5 * world.px
	var away := position - from
	var dir := away.normalized() if away.length() > 1.0 else Vector2(1.0 if facing_right else -1.0, 0.0)
	var lead := world.player as Node2D
	if lead != null:
		var tl := lead.position - position
		if tl.length() > 0.5 * world.px and tl.normalized().dot(dir) > -0.3:
			dir = (dir * 0.7 + tl.normalized() * 0.3).normalized()
	_move_for_distance(position + dir * maxf(world.px, mid - away.length()), t)
	return true


func _move_for_distance(goal: Vector2, t: float) -> void:
	# (not into a strip a monster has marked)
	if not Telegraph.live.is_empty() and Tactics.strip_at(goal) != null:
		return
	_reposition = goal
	_reposition_until = t + 2.5
	_next_reposition = t + float(Tactics.data().get("moveEvery", 2.0))
	repositions += 1


# Straight towards [param goal] (round whoever's in the way), at [param pace] times their walk. Whether they're there
# (or can't get any nearer).
func _step_to(goal: Vector2, delta: float, pace: float) -> bool:
	var dir := goal - position
	if dir.length() < 0.12 * world.px:
		velocity = Vector2.ZERO
		return true
	facing_up = dir.y < 0.0
	if absf(dir.x) > 0.02 * world.px:
		facing_right = dir.x > 0.0
	clock += delta
	var frames: Array = s.walkUp if facing_up else s.walkDown
	if not frames.is_empty():
		_show(int(frames[int(clock * _walk_fps() * pace) % frames.size()]))
	var speed := float(s.walkSpeed) * world.px * pace * Traits.mul(person, "speed")
	var v := dir.normalized() * minf(speed, dir.length() / maxf(delta, 0.001))
	v = steer.around(v, delta)
	if steer.stuck:
		velocity = Vector2.ZERO
		return true
	velocity = v
	return false



# ---- Running away: under a fifth of their health, with a monster near, they drop everything and run, away from
# it (home, if that's away from it), faster than they walk, till it's well behind them. ----

const FLEE_BELOW := 0.2          ## share of their health under which they run
const DANGER_RANGE := 6.0        ## units: a monster this near sends them running
const SAFE_RANGE := 9.0          ## units: this far from it, they stop

func _low() -> bool:
	return hit != null and hit.hp < hit.max_hp * minf(0.8, FLEE_BELOW * Traits.mul(person, "flee"))


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


## The jobs there are to set, in the order the jobs window shows them.
const JOBS := [Job.LUMBERING, Job.MINING, Job.FARMING, Job.FISHING, Job.COOKING, Job.BUILDING, Job.CRAFTING, Job.HAULING]


## How much of job [param j] the villager [param p] is set to do: 1 (none of it) to 10 (as much as there is), as
## set in the jobs window ("weights"). Older saves: what was ticked, or their one job, counts 10 and the rest 1.
const JOB_KEYS := {Job.LUMBERING: "lumbering", Job.MINING: "mining", Job.FARMING: "farming", Job.FISHING: "fishing", Job.COOKING: "cooking",
	Job.BUILDING: "building", Job.CRAFTING: "crafting", Job.HAULING: "hauling"}


## Whether [param p] can do job [param j] at all (some can't: the elder only cooks, crafts and fishes).
static func able(p: Dictionary, j: int) -> bool:
	var can: Array = p.get("canDo", [])
	return can.is_empty() or can.has(JOB_KEYS.get(j, ""))


static func weight_of(p: Dictionary, j: int) -> int:
	if not able(p, j):
		return 1
	if p.has("weights"):
		return clampi(int(p.weights.get(str(j), 10)), 1, 10)
	if p.has("jobs"):
		return 10 if (p.jobs as Array).has(Job.ANY) or (p.jobs as Array).has(j) else 1
	var one := int(p.get("job", Job.ANY))
	return 10 if one == Job.ANY or one == j else 1


static func set_weight(p: Dictionary, j: int, w: int) -> void:
	if not p.has("weights"):
		var each := {}
		for k in JOBS:
			each[str(k)] = weight_of(p, k)
		p["weights"] = each
	p.weights[str(j)] = clampi(w, 1, 10)


## Sets [param p] to do only [param jobs] (each as much as there is), and none of the rest.
static func only(p: Dictionary, jobs: Array) -> void:
	for k in JOBS:
		set_weight(p, k, 10 if jobs.has(k) or jobs.has(Job.ANY) else 1)


## The jobs [param p] does at all (those set above 1): none, and they rest.
static func jobs_of(p: Dictionary) -> Array:
	return JOBS.filter(func(j): return weight_of(p, j) > 1)


## Whether they do work [param j] (one of Job) at all.
func _does(j: int) -> bool:
	return weight_of(person, j) > 1


## Whether they'll take work [param j] this time: by how much of it they're set to, against the job they're set to
## most (that one always; one set half as high, about half the times it comes up; one set to 1, never).
func _wants(j: int) -> bool:
	var w := weight_of(person, j)
	if w <= 1:
		return false
	var most := 1
	for k in JOBS:
		most = maxi(most, weight_of(person, k))
	return randf() < float(w - 1) / float(most - 1)



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
		State.TO_FISH: _done_fishing(t)
		State.TO_WELL:
			# (up against it, a step short: close enough to draw)
			if _well != Vector2.INF and position.distance_to(_well) < 1.6 * world.px: _at_well(t)
			else: _stand(t, 1.0)
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
	if fish_dock != Vector2.INF: Fishing.taken.erase(fish_dock)
	if not craft_recipe.is_empty(): crafting_now.erase(_recipe_key(craft_recipe))


# Strength lets them carry more: one more for every two levels past the first, and a bag more again.
func _carry_most() -> int:
	@warning_ignore("integer_division")
	return maxi(2, int(s.carryMost) + (Villagers.skill(person, LifeSkills.Skill.STRENGTH) - 1) / 2 + int(person.get("bagSlots", 0)) + int(Traits.add(person, "carry")))


func _has_tools() -> bool:
	return int(person.get("toolsLeft", 0)) > 0


func _tool_pace() -> float:
	return (TOOL_BOOST if _has_tools() else 1.0) * Villagers.heart * (0.8 if bool(person.get("cold", false)) else 1.0) * [1.0, 0.88, 0.72][chill()] * Traits.mul(person, "work") * (0.75 if float(person.get("thirst", 100.0)) <= 0.0 else 1.0)   # (Village Heart: quicker with Miko about; their traits; parched, slower)


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
		VillageLog.event("tools:" + name, "%s's tools wore out: make more at the workbench" % person.name, VillageLog.Kind.WARNING)


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
func _find_work(just := -1, put_on := false) -> bool:
	# ([param just]: only mining, or just felling, as the job board takes them one at a time)
	var can_mine := (_does(Job.MINING) or (put_on and just == Job.MINING)) and just != Job.LUMBERING and able(person, Job.MINING)
	var can_chop := (_does(Job.LUMBERING) or (put_on and just == Job.LUMBERING)) and just != Job.MINING and able(person, Job.LUMBERING)
	if not can_mine and not can_chop:
		return false
	# (by how much of each they're set to: whether at all this time, and which first)
	var keen_chop := weight_of(person, Job.LUMBERING) - 1
	var keen_mine := weight_of(person, Job.MINING) - 1
	var takes := _wants(just) if just >= 0 else (_wants(Job.LUMBERING) if keen_chop >= keen_mine else _wants(Job.MINING))
	if not put_on and not takes:
		return false
	var chop := can_chop and not Kitchen.stocked(world.village, "Wood")
	var mine := can_mine and not Kitchen.stocked(world.village, "Stone")
	var spot: Gatherable = null
	if not can_chop:
		spot = _nearest_work(false) if mine else null
	elif not can_mine:
		spot = _nearest_work(true) if chop else null
	else:
		var first := randf() * float(keen_chop + keen_mine) < float(keen_chop)
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
	# (only those near a sign: the trees and rocks filed by where they stand)
	var near := {}
	for a in areas:
		for g: Gatherable in Gatherable.near(a[0], a[1]):
			near[g] = true
	for g: Gatherable in near:
		if g.axe != axe or not _in_area(areas, g.foot) or claimed.has(g) or not _workable(g):
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
	# (an errand for Sera: what it gives goes straight into her bag)
	if _in_party() and got > 0 and world.player != null:
		world.village.give(world.player.bag, world.player, spot.resource, got, spot.foot)
		people.practise(person, LifeSkills.Skill.LUMBERING if spot.axe else LifeSkills.Skill.MINING)
		return
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
	if _in_party():
		_stand(t, 0.2)   # (back to her side)
		return
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
		if not p.settled() or p.thrown or gathering.has(p) or not _gatherable(p.resource):
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


func _go_pick_up(put_on := false) -> bool:
	if not able(person, Job.HAULING):
		return false
	# (what's lying about is the haulers' to bring in, and the miners' and woodcutters' own)
	if not put_on and not _wants(Job.HAULING) and not _wants(Job.LUMBERING) and not _wants(Job.MINING):
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
	# Food goes down the cellar, where there is one.
	_via_cellar = false
	if Cellars.active != null and Spoilage.PER_DAY.has(carry_kind):
		var cellar: Variant = Cellars.active.deposit_spot(position)
		if cellar != null and VillagerRoute.find(world, position, cellar) != null:
			spot = cellar
			_via_cellar = true
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
				VillageLog.event("bag:" + name, "%s's bag wore through: make more at the workbench" % person.name, VillageLog.Kind.WARNING)
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

func _go_farm(urgent := false) -> bool:
	if not able(person, Job.FARMING) or (not urgent and not _wants(Job.FARMING)):
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
		# (watering takes water: with none in their bucket, a dry plot's left for now, or the well first)
		if pest.is_empty() and not dry.is_empty() and _bucket <= 0:
			return _go_well("fill")
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
		elif farm_task == "water" and farm.dry(plot) and _bucket > 0:
			_bucket -= 1
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
	if farm == null or carrying > 0 or not _does(Job.FARMING):
		return false
	for p in farm.plots:
		if tending.has(p.key) or not world.village.contains(p.pos, 3.0):
			continue
		if farm.pests(p) or farm.dry(p):
			return true
		# (a bare plot with seed for it in storage: planting isn't left to chance, it comes before the cooking)
		if farm.stage(p) == 0 and bool(farm._field_crop(p, func(seed_name: String) -> bool: return world.village.stored(seed_name) > 0)[0]):
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


func _go_cook(urgent := false) -> bool:
	if not able(person, Job.COOKING) or (not urgent and not _wants(Job.COOKING)):
		return false
	# (cooking is for those who can; with the village short of food and nobody here who can, anyone will)
	var can := _cook_skill() > 0 or (urgent and not all.any(func(v): return is_instance_valid(v) and v._cook_skill() > 0))
	if not can or Kitchen.next(world.village).is_empty():
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
	# To storage first, for what's to be cooked (the cellar, where there is one); then to the fire with it.
	var spot: Variant = UseSpots.nearest_chest_spot(world, position)
	_via_cellar = false
	if Cellars.active != null:
		var cellar: Variant = Cellars.active.deposit_spot(position)
		if cellar != null and VillagerRoute.find(world, position, cellar) != null:
			spot = cellar
			_via_cellar = true
	if spot == null:
		return false
	stove = best
	cooking_at[stove.key] = true
	_fetching_raw = true
	_raw_kind = ""
	_raw_left = 0
	state = State.TO_STORE
	clock = 0.0
	_set_goal(spot)
	return true


var _fetching_raw := false       ## off to storage for what they'll cook
var _raw_kind := ""              ## the raw food they hold for cooking, and the dish it makes
var _raw_dish := ""
var _raw_left := 0

# At storage: a batch of the raw food the kitchen wants cooked next, then off to the fire with it.
func _take_raw(t: float) -> void:
	_fetching_raw = false
	var nxt := Kitchen.next(world.village)
	var n := mini(8, world.village.spare(nxt[0])) if not nxt.is_empty() else 0
	if n <= 0 or stove.is_empty() or not world.village.take_from_stash(nxt[0], n):
		_done_cooking(t)
		return
	_raw_kind = nxt[0]
	_raw_dish = nxt[1]
	_raw_left = n
	state = State.TO_COOK
	clock = 0.0
	state_until = t + 40.0
	_set_goal(_beside(stove.pos, 0.7))


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
	if _raw_left <= 0:
		_done_cooking(t)
		return
	dish = _raw_dish
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
	# They leave off at the day's end, and to eat when hungry: but not with the village short of food (there's
	# nothing to go and eat: hungry, a cook who put the pan down went back for it, and never cooked).
	var short := food_short(world)
	if stove.is_empty() or fires == null or _night() or (not short and (not _work_hours() or _hungry())):
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
	# One of what they brought, cooked.
	if _raw_left > 0:
		_raw_left -= 1
		world.village.deposit(_raw_dish, 1, position)
		FloatingText.spawn(world, "+1 " + UiKit.resource_name(_raw_dish), position + Vector2(0, -1.4 * world.px), Color(0.96, 0.68, 0.32))
		people.practise(person, LifeSkills.Skill.COOKING)
		dishes += 1
	if _raw_left <= 0 or Kitchen.stocked(world.village, _raw_dish):
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
	# What they brought and didn't cook goes back.
	_fetching_raw = false
	if _raw_left > 0 and _raw_kind != "":
		world.village.put_in_stash(_raw_kind, _raw_left)
	_raw_left = 0
	if _sizzle != null:
		Sfx.keep_going(_sizzle, false)
	if not stove.is_empty():
		cooking_at.erase(stove.key)
	stove = {}
	_stand(t, randf_range(1.0, 2.0))


# ---- Lighting the fires and torches at dusk, from storage ----

const DUSK_FROM := 17.5            ## the hour they see to the torches and fires (the sun's going down)
const DUSK_TILL := 21.0            ## ...until bed
## What they'll drop to go and light one at dusk: standing about, walking, chatting, on the way to work or at it.
const DUSK_DROPS := [State.STAND, State.WALK, State.TO_CHAT, State.CHAT, State.CHAT_WAIT, State.TO_WORK, State.WORK]
var _next_dusk_look := 0.0
var _next_need_bark := 0.0


# At sundown every torch and fire in the village is lit: an unlit one nobody's on the way to goes to whoever's
# nearest and free (not fighting, eating, asleep or with Sera), who leaves what they're at to see to it.
func _answer_dusk(t: float) -> void:
	var h := _hour(world)
	if h < DUSK_FROM or h >= DUSK_TILL or not _free_at_dusk(self) or not world.village.contains(position, 6.0):
		return
	var fires := _fires()
	if fires == null:
		return
	var mine := []
	for f in fires.fires:
		if fires.lit(f) or lighting.has(f.key) or not fires.tended(f) or not _can_pay(f):
			continue
		mine.append([f.pos.distance_squared_to(position), f])
	if mine.is_empty():
		return
	mine.sort_custom(func(x, y): return x[0] < y[0])
	for pair in mine:
		var f: Dictionary = pair[1]
		var closer := false
		for v in all:
			if v != self and is_instance_valid(v) and _free_at_dusk(v) and v.position.distance_squared_to(f.pos) < pair[0]:
				closer = true
				break
		if closer:
			continue
		# (what they were at, let go of)
		match state:
			State.TO_CHAT, State.CHAT, State.CHAT_WAIT: _end_chat(t)
			State.TO_WORK, State.WORK:
				if job != null: claimed.erase(job)
				job = null
		_light_this(f)
		return


static func _free_at_dusk(v: Villager) -> bool:
	return v.state in DUSK_DROPS and v.fire.is_empty() and not v._in_party() and not v._night() and v.hit.alive()


func _go_light() -> bool:
	var fires := _fires()
	if fires == null:
		return false
	var best := {}
	var best_d := INF
	for f in fires.fires:
		if fires.lit(f) or lighting.has(f.key) or not fires.tended(f):
			continue
		# A house's fireplace: every evening, for the night (not by day).
		if bool(f.s.get("hearth", false)) and _hour(world) < 17.5:
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
	_light_this(best)
	return true


# Off to light [param f].
func _light_this(f: Dictionary) -> void:
	fire = f
	lighting[fire.key] = true
	state = State.TO_LIGHT
	clock = 0.0
	_set_goal(_beside(fire.pos, 0.5))


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
	# (lit as a fight began: into it now, if it's still on)
	var after := _fight_after
	if after != null and is_instance_valid(after) and after.alive():
		_fight(after)
		return
	_fight_after = null
	_stand(t, randf_range(1.0, 2.0))



# ---- Building from blueprints: ready pieces, paid for from storage ----

func _go_build(put_on := false) -> bool:
	if not able(person, Job.BUILDING):
		return false
	if not put_on and not _wants(Job.BUILDING):
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

func _go_repair(put_on := false) -> bool:
	if not able(person, Job.BUILDING):
		return false
	if not put_on and not _wants(Job.BUILDING):
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


func _go_craft(put_on := false, kind := "") -> bool:
	if not able(person, Job.CRAFTING) and not able(person, Job.COOKING):
		return false
	# ([param kind]: "cook" for the cooking bench alone, "craft" for the others, "" for any)
	if not put_on and not _does(Job.CRAFTING) and not _does(Job.COOKING):
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
		if (kind == "cook" and not cooks) or (kind == "craft" and cooks):
			continue
		if not put_on and not _wants(Job.COOKING if cooks else Job.CRAFTING):
			continue
		if cooks and _cook_skill() <= 0:
			continue
		var sk := LifeSkills.NAMES.find(bench.skill)
		for at in world.props_named(prop):
			if not world.village.contains(at):
				continue
			for r in bench.recipes:
				var need := 1
				if cooks and bool(r.makesResource) and r.resource in WorkbenchWindow.FINE_DISHES:
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
		State.TO_STORE: return "Fetching food to cook" if _fetching_raw else ("Fetching food to carry down the cellar" if _fetching_food else ("Taking %d %s to the cellar" if _via_cellar else "Taking %d %s to storage") % [carrying, lower.call(carry_kind)])
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
		State.CELLAR: return "Down in the cellar"
		State.TO_FISH: return "Off to the dock to fish"
		State.TO_WELL: return "Going to the well to drink" if _well_for == "drink" else "Fetching water for the crops"
		State.FOLLOW: return ("Waiting where %s asked" % Playable.name_now()) if Party.active != null and Party.active.waiting.has(str(person.get("unique", ""))) else "With " + Playable.name_now()
		State.FISH: return "Fishing (%d caught)" % carrying
		State.WALK: return "Strolling" if _work_hours() else "Free time: strolling"
	if _night(): return "Getting ready for bed"
	if _hungry() and _food_in_storage() == 0: return "Hungry: no food in storage"
	if not _work_hours(): return "Free time"
	if jobs_of(person).is_empty(): return "Resting (no work set)"
	return "Idle"
