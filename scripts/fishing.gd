class_name Fishing
extends Node
## Fishing: food all year round, winter too. A Fishing Dock is built by the water (a river, a lake, a pond). With a
## fishing rod in her bag, E at one casts Miko's line: a few seconds' wait, a bait gone, and most times a fish (now
## and then two, now and then nothing). Slower in winter. Villagers set to fish (or to any work) work the docks in and
## near the village the same way, with bait from storage (Villager's fishing). Fish spoils fast raw; grilled at a
## fire it keeps and fills. Bait turns up when harvesting, or is made at the tool workbench.

const RANGE := 1.6               ## units from a dock to fish at it
const CAST := 3.5                ## seconds a cast takes
const WINTER_SLOW := 1.7         ## times longer in winter
const CATCH := 0.85              ## the chance a cast lands something
const TWO := 0.2                 ## ...and that it's two
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
	var l := FishingLine.new()
	l.z_as_relative = false
	l.z_index = 3990
	w.add_child(l)
	return l


## Puts a line and its float where they are [param t] seconds into a cast with [param left] to go: out from the
## frame the rod comes forward, from the rod's [param tip] (px); the float through the air in an arc to
## [param target], a splash, then sitting in the water, bobbing; tugged under as the cast comes to its end.
static func draw_line_from(w: World, line: FishingLine, tip: Vector2, target: Vector2, t: float, left: float, now: float) -> void:
	var out_at := LINE_FROM / CAST_FPS
	line.visible = t >= out_at
	if not line.visible:
		line.landed = false
		return
	line.tip = tip
	var fly := clampf((t - out_at) / FLIES, 0.0, 1.0)
	if fly >= 1.0 and not line.landed:
		Sfx.play(w, Sfx.stream(Farming.WATER_SOUND), target, 0.35, 0.1)
	line.landed = fly >= 1.0
	var at := tip.lerp(target, fly) + Vector2(0, -sin(fly * PI) * 0.9 * w.px)
	line.bite = left < BITES
	if fly >= 1.0:
		at.y += sin(now * 2.6) * 0.02 * w.px + (absf(sin(now * 14.0)) * 0.07 * w.px if line.bite else 0.0)
	line.float_at = at
	line.water_at = target
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
	var pressed := _pressed
	_pressed = false
	var now := Time.get_ticks_msec() / 1000.0
	_show_emote("fishing" if casting else ("fishing_caught" if now < _caught_until else ""), now)
	_animate(now)
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
	var bait := world.village.have(miko.bag, miko, "Bait")
	prompt.visible = true
	WorldPrompts.at(prompt, (near as Vector2) + Vector2(0, -0.8 * world.px))
	if not _has_rod():
		prompt.text = "Fishing dock  ·  needs a fishing rod (tool workbench)"
		return
	if bait <= 0:
		prompt.text = "Fishing dock  ·  no bait (from harvests, or the tool workbench)"
		return
	prompt.text = "E  Fish  ·  %d bait" % bait
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


# The line comes in: the bait's gone either way.
func _land() -> void:
	casting = false
	miko.locked = false
	_reel_until = Time.get_ticks_msec() / 1000.0 + REEL
	if not world.village.take(miko.bag, miko, "Bait", 1):
		return
	var n := catch_now(LifeSkills.get_level(LifeSkills.Skill.FISHING))
	LifeSkills.practise(LifeSkills.Skill.FISHING, miko)
	var over := miko.position + Vector2(0, -2.0 * world.px)
	if n <= 0:
		FloatingText.spawn(world, "It got away", over, Color(0.75, 0.8, 0.9))
		return
	world.village.give(miko.bag, miko, "Fish", n, miko.position)
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
