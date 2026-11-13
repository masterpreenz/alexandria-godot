class_name Fishing
extends Node
## Fishing: food all year round, winter too. A Fishing Dock is built by the water (a river, a lake, a pond). With a
## fishing rod in her bag, E at one casts Miko's line: a few seconds' wait, and most times a fish (now
## and then two, now and then nothing). Slower in winter. Villagers set to fish (or to any work) work the docks in and
## near the village the same way (Villager's fishing). Fish spoils fast raw; grilled at a
## fire it keeps and fills. It takes a rod and nothing else (there was bait once: it only got in the way).

const RANGE := 1.6               ## units from a dock to fish at it
const CAST := 6.0                ## seconds a cast takes (the wait for a bite)
const WINTER_SLOW := 1.7         ## times longer in winter
const CATCH := 0.75              ## the chance a cast lands something
const TWO := 0.1                 ## ...and that it's two
const CAST_FPS := 10.0           ## the cast's frames a second
const CAST_FRAMES := 12          ## how many of the sheet's frames are the cast (the rest: waiting, looped)
const WAIT_FPS := 3.0
const LINE_FROM := 8.0           ## the frame the line goes out on
const FLIES := 0.35              ## seconds the float's in the air
const BITES := 0.7               ## seconds before the cast's end the float's tugged under
const REEL := 0.45               ## seconds the rod's held up after
const CAUGHT_SHOWS := 1.7         ## seconds the caught-one emote shows: played through once, then held on its last frame
const SKILL_FASTER := 0.05       ## quicker casts per level of the fishing skill
const SKILL_LUCK := 0.04         ## and likelier a second fish

static var active: Fishing
static var taken := {}           ## dock (where, px) -> the villager fishing it

var world: World
var miko: Miko
var prompt: Label
var _pressed := false
var casting := false
var _cast_until := 0.0
var _dock := Vector2.ZERO
var _emote: Sprite2D             ## over Miko: the line out, then what she caught
var _caught_until := 0.0
var _anim: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/player.json")).get("fishing", {})
var _cast_at := 0.0               ## when the cast began (seconds)
var _float_at := Vector2.ZERO     ## where the float sits in the water (px)
var _reel_until := 0.0            ## the rod's held up till then, the line come in
var _line: FishingLine
var _emotes: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/villagers.json")).get("emotes", {})


func setup(w: World, who: Miko, hud: Node) -> void:
	world = w
	miko = who
	active = self
	prompt = HudStyle.label("", 14, "bold")
	prompt.visible = false
	hud.add_child(prompt)
	WorldPrompts.register(prompt)


# ---- The dock's deck: a strip of open planks along one edge to walk and fish from; the rest (barrels, crate, rack)
# solid. Which edge, by the way the dock's turned. ----

const OPEN := 0.32               ## the share of the deck, from its open edge, that's planks to walk on
const DECK := [Vector2(-1, 0), Vector2(0, -0.5), Vector2(1, 0), Vector2(0, 0.5)]   ## its corners, units: left, top, right, bottom

var _solid_for := -1             ## the props' version the docks' colliders were made for
var _shapes: Array = []
var _raised := {}                ## those standing on a deck, drawn over it (CanvasItem -> true)


## The part of a deck that's solid, for a dock turned [param turn] (units from its middle).
static func deck_solid(turn: int) -> PackedVector2Array:
	var l: Vector2 = DECK[0]
	var t: Vector2 = DECK[1]
	var r: Vector2 = DECK[2]
	var b: Vector2 = DECK[3]
	if turn % 2 == 0:   # (open along its upper-left edge)
		return PackedVector2Array([l.lerp(b, OPEN), t.lerp(r, OPEN), r, b])
	return PackedVector2Array([l.lerp(t, OPEN), t, r, b.lerp(r, OPEN)])   # (open along its lower-left edge)


## Where to stand on a deck to fish: the middle of its open planks (units from the dock's middle).
static func deck_stand(turn: int) -> Vector2:
	var l: Vector2 = DECK[0]
	if turn % 2 == 0:
		return (l + DECK[1]) / 2.0 + (DECK[3] - l) * OPEN * 0.5
	return (l + DECK[3]) / 2.0 + (DECK[1] - l) * OPEN * 0.5


func _turn_of(at: Vector2) -> int:
	for e in world.props.entries_named("FishingDock"):
		if (e.pos as Vector2).distance_to(at) < 4.0:
			return int(e.e.get("turn", 0))
	return 0


## Where a villager stands to fish at the dock at [param at] (px).
func stand_at(at: Vector2) -> Vector2:
	return at + deck_stand(_turn_of(at)) * world.px


## Whether [param p] (px) is on a dock's open planks.
func on_planks(p: Vector2) -> bool:
	for e in world.props.entries_named("FishingDock"):
		var d: Vector2 = (p - (e.pos as Vector2)) / world.px
		if absf(d.x) + absf(d.y) * 2.0 <= 1.0 and not Geometry2D.is_point_in_polygon(d, deck_solid(int(e.e.get("turn", 0)))):
			return true
	return false


# The docks' colliders, made again when the props change; and whoever's on a deck drawn over it (the dock's one
# picture, sorted by its middle: someone on its far planks would be drawn behind it).
func _decks() -> void:
	if world.props.version != _solid_for:
		_solid_for = world.props.version
		for s in _shapes:
			if is_instance_valid(s):
				s.queue_free()
		_shapes = []
		for e in world.props.entries_named("FishingDock"):
			var poly := ConvexPolygonShape2D.new()
			var pts := PackedVector2Array()
			for q in deck_solid(int(e.e.get("turn", 0))):
				pts.append(q * world.px)
			poly.points = pts
			var shape := CollisionShape2D.new()
			shape.shape = poly
			shape.position = e.pos
			world.solids.add_child(shape)
			_shapes.append(shape)
	var on := {}
	var folk: Array = [miko]
	folk.append_array(Villager.all)
	for who in folk:
		if is_instance_valid(who) and on_planks(who.position):
			on[who] = true
			if not _raised.has(who):
				who.z_index += 1
	for who in _raised:
		if is_instance_valid(who) and not on.has(who):
			who.z_index -= 1
	_raised = on


## The docks standing: where each is (px).
func docks() -> Array:
	return world.props_named("FishingDock")


## The docks the villagers work: those on cleared ground (the village's, or a cleansing crystal's by the water). They
## don't go into the mist for one.
func village_docks() -> Array:
	return docks().filter(func(at): return Villager.safe_ground(world, at))


## How long a cast takes now (longer in winter, quicker with the fishing skill at [param skill]).
func cast_time(skill := 1) -> float:
	var winter := world.clock != null and world.clock.season() == GameClock.Season.WINTER
	return CAST * (WINTER_SLOW if winter else 1.0) / (1.0 + SKILL_FASTER * (maxi(1, skill) - 1))


## What a cast brings up: 0, 1 or 2 fish (two likelier, and none rarer, with the fishing skill at [param skill]).
static func catch_now(skill := 1) -> int:
	var more := maxi(1, skill) - 1
	if randf() >= minf(0.98, CATCH + 0.012 * more):
		return 0
	return 2 if randf() < TWO + SKILL_LUCK * more else 1


## The frame of an emote played once (160 ms a frame), [param since] seconds in: it stops on its last.
static func once(frames: int, since: float) -> int:
	return clampi(int(since / 0.16), 0, frames - 1)


## Where a line cast from [param from] at the dock at [param dock] comes down (px): the water nearest the dock, a
## little way out from its bank.
static func water_spot(w: World, dock: Vector2, from: Vector2) -> Vector2:
	var best := dock + (dock - from).normalized() * 1.5 * w.px
	var best_d := INF
	for ring in [1.0, 1.4, 1.8, 2.2, 2.6, 3.0]:
		for i in 24:
			var a := i * TAU / 24.0
			var p := dock + Vector2(cos(a), sin(a) * 0.5) * float(ring) * w.px
			if w.water_depth(p) < 0.25:
				continue
			# (nearer the dock is better, and the far side of it from her better still)
			var d := p.distance_to(dock) + 0.35 * p.distance_to(dock + (dock - from))
			if d < best_d:
				best_d = d
				best = p
	return best


# Miko's fishing, a frame at a time: the cast (the rod back, then out), then waiting on it; the rod up as the line
# comes in. The line and its float are drawn from the rod's tip once it's out.
func _animate(now: float) -> void:
	var frames: Array = _anim.get("up" if miko.facing_up else "down", [])
	if frames.is_empty():
		return
	if not casting:
		if _line != null:
			_line.visible = false
		if _reel_until > 0.0:
			if now < _reel_until:
				miko.pose = int(frames[3])   # (the rod up)
				miko.pose_mirror = miko.facing_right
			else:
				_reel_until = 0.0
				miko.pose = -1
		return
	var t := now - _cast_at
	var i := cast_frame(t, frames.size())
	miko.pose = int(frames[i])
	miko.pose_mirror = miko.facing_right
	if _line == null:
		_line = new_line(world)
	var tip: Array = _anim.get("tipsUp" if miko.facing_up else "tipsDown", [])[i]
	var k: float = world.px / float(_anim.get("ppu", 153)) * miko.art_scale.x
	draw_line_from(world, _line, miko.position + Vector2(-float(tip[0]) if miko.facing_right else float(tip[0]), float(tip[1])) * k, _float_at, t, _cast_until - now, now)


## The frame of a fishing sheet [param t] seconds into a cast: the cast's frames once, then the waiting ones, looped.
static func cast_frame(t: float, frames: int) -> int:
	var i := int(t * CAST_FPS)
	if i >= CAST_FRAMES:
		i = CAST_FRAMES + int((t - CAST_FRAMES / CAST_FPS) * WAIT_FPS) % maxi(1, frames - CAST_FRAMES)
	return clampi(i, 0, frames - 1)


static func new_line(w: World) -> FishingLine:
	# (among the things standing, sorted where its float sits: a tree nearer than that is drawn over it)
	var l := FishingLine.new()
	w.things.add_child(l)
	return l


## Puts a line and its float where they are [param t] seconds into a cast with [param left] to go: out from the
## frame the rod comes forward, from the rod's [param tip] (px); the float through the air in an arc to
## [param target], then sitting in the water, bobbing; tugged under as the cast comes to its end.
static func draw_line_from(w: World, line: FishingLine, tip: Vector2, target: Vector2, t: float, left: float, now: float) -> void:
	var out_at := LINE_FROM / CAST_FPS
	line.visible = t >= out_at
	if not line.visible:
		line.landed = false
		return
	line.tip = tip
	var fly := clampf((t - out_at) / FLIES, 0.0, 1.0)
	line.landed = fly >= 1.0
	var at := tip.lerp(target, fly) + Vector2(0, -sin(fly * PI) * 0.9 * w.px)
	line.bite = left < BITES
	if fly >= 1.0:
		at.y += sin(now * 2.6) * 0.02 * w.px + (absf(sin(now * 14.0)) * 0.07 * w.px if line.bite else 0.0)
	line.float_at = at
	line.water_at = target
	line.position = target
	line.unit = w.px
	line.queue_redraw()


## Whether there's water within [param reach] units of [param at] (px): where a dock may be built.
static func water_near(w: World, at: Vector2, reach := 2.2) -> bool:
	for ring in [0.6, 1.0]:
		for i in 12:
			var a := i * TAU / 12.0
			if w.water_depth(at + Vector2(cos(a), sin(a) * 0.5) * reach * float(ring) * w.px) > 0.0:
				return true
	return false


func _has_rod() -> bool:
	return miko.bag.items.has("FishingRod") or miko.bag.worn.has("FishingRod")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E and prompt.visible and not casting:
		_pressed = true


func _process(_delta: float) -> void:
	var pressed := _pressed or WorldPrompts.take(prompt)
	_pressed = false
	var now := Time.get_ticks_msec() / 1000.0
	_show_emote("fishing" if casting else ("fishing_caught" if now < _caught_until else ""), now)
	_animate(now)
	_decks()
	if casting:
		prompt.visible = true
		prompt.text = "Fishing…"
		WorldPrompts.at(prompt, _dock + Vector2(0, -0.8 * world.px))
		if now >= _cast_until:
			_land()
		return
	prompt.visible = false
	if miko.locked or BuildMode.is_open() or CharacterPanel.up():
		return
	var near: Variant = null
	var best := RANGE * world.px
	for at in docks():
		if at.distance_to(miko.position) < best:
			best = at.distance_to(miko.position)
			near = at
	if near == null:
		return
	prompt.visible = true
	WorldPrompts.at(prompt, (near as Vector2) + Vector2(0, -0.8 * world.px))
	if not _has_rod():
		prompt.text = "Fishing dock  ·  needs a fishing rod (tool workbench)"
		return
	prompt.text = "E  Fish"
	if not Villager.safe_ground(world, near):
		prompt.text += "
In the mist: villagers won't fish here (a cleansing crystal clears it)"
	if pressed:
		_dock = near
		casting = true
		_cast_until = now + cast_time(LifeSkills.get_level(LifeSkills.Skill.FISHING))
		miko.locked = true
		_cast_at = now
		_float_at = water_spot(world, _dock, miko.position)
		var to: Vector2 = _float_at - miko.position
		miko.facing_right = to.x > 0.0
		miko.facing_up = to.y < 0.0


# The line comes in.
func _land() -> void:
	casting = false
	miko.locked = false
	_reel_until = Time.get_ticks_msec() / 1000.0 + REEL
	var n := catch_now(LifeSkills.get_level(LifeSkills.Skill.FISHING))
	LifeSkills.practise(LifeSkills.Skill.FISHING, miko)
	var over := miko.position + Vector2(0, -2.0 * world.px)
	if n <= 0:
		FloatingText.spawn(world, "It got away", over, Color(0.75, 0.8, 0.9))
		return
	world.village.give(miko.bag, miko, "Fish", n, miko.position)
	if Chronicle.active != null and not Chronicle.active.happened("fish_caught"):
		Chronicle.active.record("fish_caught")   # (the river rumor)
	FloatingText.spawn(world, "+%d Fish" % n, over, Color(0.6, 0.85, 1.0))
	_caught_until = Time.get_ticks_msec() / 1000.0 + CAUGHT_SHOWS


# The emote over Miko's head (the villagers' own art), 160 ms a frame.
func _show_emote(e: String, now: float) -> void:
	var frames: Array = _emotes.get(e, [])
	if frames.is_empty():
		if _emote != null:
			_emote.visible = false
		return
	if _emote == null:
		_emote = Sprite2D.new()
		_emote.z_as_relative = false
		_emote.z_index = 3998
		world.add_child(_emote)
	var id := int(frames[once(frames.size(), now - (_caught_until - CAUGHT_SHOWS))]) if e == "fishing_caught" else int(frames[int(now / 0.16) % frames.size()])
	var info: Dictionary = world.sprites[id]
	var k := Villager.EMOTE_WIDTH * world.px / float(info.rect[2])
	world.show_frame(_emote, id, Vector2.ONE * k * float(info.ppu) / world.px)
	_emote.visible = true
	_emote.modulate = world.daylight_undo()
	_emote.flip_h = not miko.facing_right
	_emote.position = miko.position + Vector2((0.24 if miko.facing_right else -0.24) * world.px, -1.02 * world.px)
