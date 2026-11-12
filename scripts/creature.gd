class_name Creature
extends CharacterBody2D
## What the creatures of the wild share (slimes, boars): a round body at their feet that meets walls, trees and rocks
## and each other but not Miko; their art over a shadow, wading at the water's edge and outlined in red behind things;
## something that can be hit (a Damageable), flashing pale when it is; and resting while far from Miko (Unity's
## Dormancy: their thinking and physics paused, and picked up again before she gets near). Each one's settings come
## from data/monsters.json.

const AWAKE_WITHIN := 22.0     ## units from Miko: awake within this
const AWAKE_MARGIN := 4.0      ## and back to sleep only this much further out

static var all: Array[Creature] = []

var world: World
var s: Dictionary               ## its settings (Unity's component's)
var art: Sprite2D
var shadow: Sprite2D
var hit: Damageable
var steer: Steer
var shape: CircleShape2D
var outline: OccludedOutline
var fx: HitFx                   ## blinking red and jolting when hit
var asleep := false
var flash_until := -1.0
var facing_back := false
var flip := false               ## facing east (the art faces west)
var art_scale := 1.0
var raid_to := Vector2.INF       ## raiding (Raids): where in the village it's making for; INF when not
var taunted_by: Damageable       ## a shield shikigami that's drawn it off: it goes for that instead, while it lasts
var taunt_until := 0.0
var _check_at := 0.0


static func now() -> float:
	return Time.get_ticks_msec() / 1000.0


## Sets up the body, art and hit box from [param d] (monsters.json's entry); [param team_hp] HP, hit radius and height
## in units.
func build(w: World, d: Dictionary, hp: float, hit_radius: float, hit_height: float, look: float) -> void:
	world = w
	s = d.settings
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	collision_layer = 2            # creatures
	collision_mask = 1 | 2 | PropMap.FURNITURE_LAYER   # the fixed world, furniture and each other (Miko's on her own layer)
	var c := CollisionShape2D.new()
	shape = CircleShape2D.new()
	shape.radius = float(d.collider.r)
	c.shape = shape
	c.position = Vector2(d.collider.x, d.collider.y)
	add_child(c)
	if d.has("shadow") and int(d.shadow.s) >= 0:
		shadow = Sprite2D.new()
		world.show_frame(shadow, int(d.shadow.s), Vector2(d.shadow.sx, d.shadow.sy))
		shadow.position = Vector2(d.shadow.x, d.shadow.y)
		shadow.modulate.a = d.shadow.a
		add_child(shadow)
	art = Sprite2D.new()
	art.position = Vector2(d.body.x, d.body.y)
	add_child(art)
	hit = Damageable.new()
	hit.name = "Hit"
	add_child(hit)
	hit.setup(world, Damageable.Team.ENEMY, hp, hit_radius * world.px, hit_height * world.px)
	hit.damaged.connect(_hurt)
	hit.died.connect(func(): Story.count_kill(self))
	hit.died.connect(_died)
	steer = Steer.new(self, shape, c.position, look * world.px)
	var wade := Wading.new()
	wade.name = "Wading"
	add_child(wade)
	wade.setup(world, self, art, shadow)
	fx = HitFx.add_to(self, art, wade, world.px)
	hit.damaged.connect(func(_a): fx.play())
	# Seen through whatever stands in front of it, in red.
	outline = OccludedOutline.new()
	outline.name = "OccludedOutline"
	outline.fade_covers = false
	add_child(outline)
	outline.setup(world, art, Color(1.0, 0.35, 0.3, 1.0))


func _enter_tree() -> void:
	all.append(self)


func _exit_tree() -> void:
	all.erase(self)


## Makes it [param k] times the size: its art, shadow and body (a physics body itself can't be scaled).
func grow(k: float) -> void:
	art_scale *= k
	art.position *= k
	shape.radius *= k
	steer.shape_at *= k
	for c in get_children():
		if c is CollisionShape2D:
			c.position *= k
	if shadow != null:
		shadow.scale *= k
		shadow.position *= k


## Shows frame [param id] (drawn facing west), mirrored when facing east; scaled by [member art_scale].
func show_art(id: int, scale_y := 1.0) -> void:
	world.show_frame(art, id, Vector2(-art_scale if flip else art_scale, art_scale * scale_y))


func face(dir: Vector2, back_above := 0.1) -> void:
	if dir.length_squared() < 0.0001:
		return
	facing_back = dir.y < -back_above * world.px
	flip = dir.x > 0.0


var _ignoring := {}               # who it's given up on for now (can't get at them): node -> until when
var _stuck_from := Vector2.INF
var _stuck_check_at := 0.0


## Whether it's given up on [param n] for now (couldn't get at them).
func ignoring(n: Node) -> bool:
	return _ignoring.has(n) and now() < float(_ignoring[n])


## Called while it's closing on [param target]: true when it's got nowhere for a while (shut out: they're in a house,
## the door closed), and then it gives them up for a few seconds (it goes for someone else, or at the house's walls).
func stuck_on(target: Node) -> bool:
	var t := now()
	if _stuck_from == Vector2.INF:
		_stuck_from = position
		_stuck_check_at = t + 1.5
		return false
	if t < _stuck_check_at:
		return false
	var stuck := position.distance_to(_stuck_from) < 0.3 * world.px
	_stuck_from = position
	_stuck_check_at = t + 1.5
	if stuck and target != null:
		_ignoring[target] = t + 8.0
		_route = null
		return true
	return false


## Not closing on anyone now (attacking, standing): the headway check starts afresh next time.
func stuck_reset() -> void:
	_stuck_from = Vector2.INF


var _route: Variant = null        # the way round walls it's following (VillagerRoute points), or null
var _route_goal := Vector2.INF
var _route_at := -10.0
var _route_leg := 0


## Where to head for [param goal]: straight there when nothing fixed stands in the way; with a wall across it (a house
## between), round it by the villagers' ways (the walls and closed doors as they are), worked out again every second or
## when the goal's moved on.
func way_to(goal: Vector2) -> Vector2:
	var __t := Time.get_ticks_usec()
	var r := _way_to(goal)
	Perf.add(&"AI: monsters' way round", __t)
	return r


var _way_at := -10.0
var _way_point := Vector2.INF
var _way_goal := Vector2.INF
var _way_straight := true


# (looked at again four times a second, not every frame: its clearance casts were most of a crowded fight's time)
func _way_to(goal: Vector2) -> Vector2:
	if world.walls == null:
		return goal
	var t := now()
	var moved := _way_goal == Vector2.INF or _way_goal.distance_to(goal) > 0.6 * world.px
	if t - _way_at < 0.25 and not moved:
		return goal if _way_straight else _way_point
	_way_at = t + randf() * 0.05   # (spread out, so they don't all look on the same frame)
	_way_goal = goal
	_way_straight = _clear_to(goal)
	if _way_straight:
		_route = null
		return goal
	# (worked out again every two seconds, or when what it's after has moved off a good way)
	if _route == null or t - _route_at > 2.0 or _route_goal.distance_to(goal) > 3.0 * world.px:
		_route_at = t
		_route_goal = goal
		_route = VillagerRoute.find(world, position, goal)
		_route_leg = 0
	if _route == null:
		_way_straight = true
		return goal
	var pts: Array = _route
	# (a point's passed once it's within a step: a slime's hop is longer than that, and would keep overshooting it)
	while _route_leg < pts.size() - 1 and position.distance_to(pts[_route_leg].at) < 0.8 * world.px:
		_route_leg += 1
	# (on to the furthest of the next two points it can get to straight, its body's width clear all the way: the
	# square middles hugging a wall are too tight for the bigger ones, and it's a smoother way round besides)
	for ahead in range(mini(pts.size() - 1, _route_leg + 2), _route_leg, -1):
		if _clear_to(pts[ahead].at):
			_route_leg = ahead
			break
	_way_point = pts[_route_leg].at
	return _way_point


# Whether it could go straight to [param p], its body's width clear of anything fixed all the way.
func _clear_to(p: Vector2) -> bool:
	var body := PhysicsShapeQueryParameters2D.new()
	var c := CircleShape2D.new()
	c.radius = shape.radius if shape != null else 0.3 * world.px   # (its own body's width)
	body.shape = c
	body.collision_mask = 1
	body.exclude = [get_rid()]
	body.transform = Transform2D(0.0, position)
	body.motion = p - position
	var free := get_world_2d().direct_space_state.cast_motion(body)
	return free.size() > 0 and free[0] >= 1.0


## Going for [param goal]: the barricade standing across the straight way there, [wall key, where the way crosses it],
## or []. A hunting monster breaks that down first.
func barricade_ahead(goal: Vector2) -> Array:
	if world.walls == null or world.walls.hp.is_empty():
		return []
	return world.walls.barricade_in_way(position, goal, 0.0)   # (across the way only: a gap broken in, it goes through)


## Whether it's going for someone now (a shield shikigami draws off only those).
func hostile() -> bool:
	return false


## The shield shikigami it's been drawn off by, while that's still about, near and the taunt lasts; else null.
func taunter() -> Damageable:
	if taunted_by == null or not is_instance_valid(taunted_by) or not taunted_by.alive() or now() >= taunt_until:
		taunted_by = null
		return null
	if taunted_by.global_position.distance_to(position) > 9.0 * world.px:
		taunted_by = null
		return null
	return taunted_by


const SEED_CHANCE := 0.25        ## a felled monster drops a seed this often

## A seed dropped where it fell, now and then: one of the crops' seeds, or a tree's.
func drop_seed() -> void:
	if randf() >= SEED_CHANCE:
		return
	var seeds := ["Seed"]
	for c in Farming.CROPS:
		seeds.append(str(Farming.CROPS[c].seed))
	Pickup.launch_icon(world, seeds.pick_random(), 1, position, 2.2)


func player() -> Miko:
	return world.player as Miko


## Rests while far from Miko; true while resting (the caller skips its thinking).
func resting() -> bool:
	if raid_to != Vector2.INF:
		asleep = false   # a raider keeps coming, however far from Miko
		return false
	var t := now()
	if t >= _check_at:
		_check_at = t + 0.25
		var p := player()
		var d := p.position.distance_to(position) / world.px if p != null else 0.0
		var was := asleep
		asleep = d > AWAKE_WITHIN + AWAKE_MARGIN if not asleep else d > AWAKE_WITHIN
		if asleep != was:
			outline.set_process(not asleep)
			if asleep:
				velocity = Vector2.ZERO
	return asleep


## A hit flashes it pale for a moment.
func paint_flash(c := Color(1, 0.75, 0.75)) -> void:
	if fx != null and fx.active():
		return   # (flinching: its red shows)
	art.self_modulate = c if now() < flash_until else Color.WHITE


## Hits Miko for [param amount] (softened by her defense), showing the number, and shoves her [param knock] px/s for
## [param time] seconds.
func hurt_player(amount: float, knock: Vector2, time: float) -> void:
	var p := player()
	if p == null or p.stats == null:
		return
	p.stats.damage(amount)
	FloatingText.spawn(world, str(roundi(amount)), p.position + Vector2(0, -1.5 * world.px), Color(1, 0.4, 0.35))
	p.knock(knock, time)


func _hurt(_amount: float) -> void:
	pass


func _died() -> void:
	queue_free()
