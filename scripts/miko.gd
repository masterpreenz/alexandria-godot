class_name Miko
extends CharacterBody2D
## Miko (from PlayerController2D and CharacterSpriteDiagonal): walks in 8 directions on the iso map (the vertical
## squashed, so the ground reads as seen at an angle), runs with Shift. Her art is drawn in the two left-facing
## diagonals (down-left, up-left) and mirrored for the right unless right-facing frames exist: idle standing still,
## the run cycle moving (slower when walking).

var world: World
var data: Dictionary

var walk_speed := 492.8
var run_speed := 896.0
var vertical_scale := 0.5
var facing_up := false
var facing_right := false
var moving := false
var running := false
var clock := 0.0
var art_scale := Vector2.ONE
## Whether Shift runs (not while exhausted).
var can_run := true
## While true she ignores movement input (casting, asleep, ...).
var locked := false
## Slows her down (or speeds her up) on top of everything else: wading sets it below 1.
var speed_scale := 1.0
## What she carries.
var bag := Bag.new()
## Her stats: HP, mana, level, gear, talents.
var stats: CharacterStats
# An action looping instead of walking (mining, chopping): its frames facing down and up, and how fast.
var _action_down: Array = []
var _action_up: Array = []
var _action_fps := 0.0
var _action_clock := -1.0
# Where she was at the last two physics ticks: she's drawn between them (physics interpolation).
var _was := Vector2.ZERO
var _now := Vector2.ZERO

var art: Sprite2D
var shadow: Sprite2D
var wading: Wading
## A frame held instead of walking (fainting), or -1; and whether it's mirrored.
var pose := -1
var pose_mirror := false
# Shoved (a slime's bite, a boar's charge): the shove, and how long it has left of how long.
var _knock := Vector2.ZERO
var _knock_left := 0.0
var _knock_time := 1.0
const JUMP_HEIGHT := 0.7       ## units (Unity's CharacterJump)
const JUMP_TIME := 0.5          ## seconds
# Off her feet, jumping (Space) or thrown (Unity's CharacterJump.Toss): how high (units), how long, and how far through
# (-1: on the ground). Only her body rises; where she stands (sorting, collisions, the shadow) stays put.
var _toss_height := 0.0
var _toss_time := 0.5
var _toss_clock := -1.0
# Flinching from a hit (Unity's HitReaction): two red blinks and a jolt, this long ago (-1: not).
var _hit_since := -1.0
const HIT_FOR := 0.4
const HIT_COLOR := Color(1.0, 0.42, 0.38)
const HIT_JOLT := 0.08


func setup(w: World, d: Dictionary) -> void:
	world = w
	data = d
	walk_speed = d.walkSpeed
	run_speed = d.runSpeed
	vertical_scale = d.verticalScale
	place(Vector2(d.x, d.y))
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	# Her body: a small capsule at her feet.
	var body := CollisionShape2D.new()
	var capsule := CapsuleShape2D.new()
	var b: Dictionary = d.body
	capsule.radius = min(b.w, b.h) / 2.0
	capsule.height = max(b.w, b.h)
	body.shape = capsule
	body.position = Vector2(b.x, b.y)
	if not b.vertical:
		body.rotation_degrees = 90
	add_child(body)
	if d.has("shadow"):
		shadow = Sprite2D.new()
		world.show_frame(shadow, int(d.shadow.s), Vector2(d.shadow.sx, d.shadow.sy))
		shadow.position = Vector2(d.shadow.x, d.shadow.y)
		shadow.modulate.a = d.shadow.a
		add_child(shadow)
	art = Sprite2D.new()
	art.position = Vector2(d.art[0], d.art[1])
	art_scale = Vector2.ONE * World.BODY_SCALE   # (player.json's art scale no longer counts: one scale for everyone)
	add_child(art)
	_animate(0.0)
	# Findable behind things (and fading what hides her), her steps, and dust at her feet.
	var outline := OccludedOutline.new()
	outline.name = "OccludedOutline"
	add_child(outline)
	outline.setup(world, art)
	var steps := Footsteps.new()
	steps.name = "Footsteps"
	add_child(steps)
	steps.setup(world, self)
	wading = Wading.new()
	wading.name = "Wading"
	add_child(wading)
	wading.setup(world, self, art, shadow)
	var dust := DustTrail.new()
	dust.name = "Dust"
	dust.target = self
	dust.unit = world.px
	world.things.add_child.call_deferred(dust)


func _physics_process(delta: float) -> void:
	var __t := Time.get_ticks_usec()
	_physics_process_timed(delta)
	Perf.add(&"miko.physics", __t)


func _physics_process_timed(delta: float) -> void:
	var input := Vector2.ZERO
	var typing := HudStyle.typing(get_viewport())   # (in a search box: the keys are the text's, she stays put)
	if not locked and not typing:
		input = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
		if Input.is_key_pressed(KEY_A): input.x -= 1
		if Input.is_key_pressed(KEY_D): input.x += 1
		if Input.is_key_pressed(KEY_W): input.y -= 1
		if Input.is_key_pressed(KEY_S): input.y += 1
		input = input.limit_length(1.0)
	running = not locked and not typing and can_run and Input.is_key_pressed(KEY_SHIFT)
	var now_moving := input.length_squared() > 0.01
	if now_moving != moving:
		clock = 0.0
	moving = now_moving
	# Straight up/down/left/right keeps the other half of the last diagonal.
	if input.y < -0.1: facing_up = true
	elif input.y > 0.1: facing_up = false
	if input.x > 0.1: facing_right = true
	elif input.x < -0.1: facing_right = false
	var stat_speed := CharacterStats.percent(stats.stat("moveSpeed")) if stats != null else 1.0
	velocity = Vector2(input.x, input.y * vertical_scale) * (run_speed if running else walk_speed) * speed_scale * maxf(0.2, stat_speed)
	# Shoved: carried along, easing off, whatever's pressed.
	if _knock_left > 0.0:
		velocity = _knock * (_knock_left / _knock_time)
		_knock_left -= delta
	_was = position
	move_and_slide()
	_now = position


## Where she's drawn this frame: between her last two physics positions (what the camera follows).
func drawn_position() -> Vector2:
	if _now == Vector2.ZERO and _was == Vector2.ZERO:
		return position
	return _was.lerp(_now, Engine.get_physics_interpolation_fraction())


## Puts her somewhere at once (no smoothing from where she was).
func place(at: Vector2) -> void:
	position = at
	_was = at
	_now = at
	reset_physics_interpolation()


func _process(delta: float) -> void:
	var __t := Time.get_ticks_usec()
	_process_timed(delta)
	Perf.add(&"miko.process", __t)


func _process_timed(delta: float) -> void:
	_animate(delta)
	var extra := Vector2.ZERO
	# Off her feet: up and down in an arc, her shadow shrinking and fading under her as she rises.
	if _toss_clock >= 0.0:
		_toss_clock += delta
		var t := clampf(_toss_clock / _toss_time, 0.0, 1.0)
		var lift := 4.0 * _toss_height * t * (1.0 - t)
		extra.y = -lift * world.px
		_shadow_lift(lift)
		if t >= 1.0:
			_toss_clock = -1.0
			_shadow_lift(0.0)
			Puffs.burst(world, position, 0.6, 6)
	# Hit: two red blinks, fading, and a jolt side to side, settling.
	if _hit_since >= 0.0:
		_hit_since += delta
		var t := _hit_since / HIT_FOR
		if t >= 1.0:
			_hit_since = -1.0
			art.self_modulate = Color.WHITE
		else:
			var blink := absf(sin(t * PI * 2.0)) * (1.0 - t * 0.5)
			art.self_modulate = Color.WHITE.lerp(HIT_COLOR, blink)
			extra.x = sin(t * PI * 6.0) * HIT_JOLT * (1.0 - t) * world.px
	wading.extra = extra


## Shoves her at [param v] px/s, easing off over [param time] seconds.
func knock(v: Vector2, time: float) -> void:
	# Firm Footing: shoved less far.
	_knock = v * clampf(1.0 - (stats.stat("knockResist") if stats != null else 0.0) / 100.0, 0.0, 1.0)
	_knock_left = maxf(0.05, time)
	_knock_time = _knock_left


## Throws her up off her feet, [param height] units high, landing after [param time] seconds.
## Whether she's off her feet (jumping or thrown).
func airborne() -> bool:
	return _toss_clock >= 0.0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		jump()


## A hop (Space), unless she's already off her feet or can't move (casting, in a window, asleep...).
func jump() -> void:
	if airborne() or locked:
		return
	toss(JUMP_HEIGHT, JUMP_TIME)


# The shadow under her as she's [param lift] units up: smaller and fainter (Unity's 45% at a jump's top).
func _shadow_lift(lift: float) -> void:
	if shadow == null:
		return
	var ground := 1.0 - 0.45 * clampf(lift / JUMP_HEIGHT, 0.0, 1.0)
	shadow.scale = Vector2(data.shadow.sx, data.shadow.sy) * (world.px / float(world.sprites[int(data.shadow.s)].ppu)) * ground
	shadow.modulate.a = float(data.shadow.a) * ground


func toss(height: float, time: float) -> void:
	_toss_height = maxf(0.05, height)
	_toss_time = maxf(0.1, time)
	_toss_clock = 0.0


## Flinches from a hit (her stats' hurt signal).
func flinch(_amount := 0.0) -> void:
	_hit_since = 0.0


var _casting := false

## Turns towards [param direction] and holds the cast pose, until [method end_cast].
func hold_cast(direction: Vector2) -> void:
	_casting = true
	facing_up = direction.y < 0.0
	facing_right = direction.x > 0.0


func end_cast() -> void:
	_casting = false
	clock = 0.0


## Turns towards [param direction] and loops the given frames (drawn facing left) until [method end_action].
func play_action(down: Array, up: Array, fps: float, direction: Vector2) -> void:
	_action_down = down
	_action_up = up
	_action_fps = fps
	facing_up = direction.y < 0.0
	facing_right = direction.x > 0.0
	_action_clock = 0.0


func end_action() -> void:
	_action_down = []
	_action_clock = -1.0
	clock = 0.0


## Frames played since the action started (counts up); -1 when none.
func action_frame() -> int:
	return int(_action_clock * _action_fps) if _action_clock >= 0.0 else -1


func _animate(delta: float) -> void:
	clock += delta
	if pose >= 0:
		world.show_frame(art, pose, Vector2(-art_scale.x if pose_mirror else art_scale.x, art_scale.y))
		return
	if _casting:
		var pose_now: Array = data.frames.castUpLeft if facing_up else data.frames.castDownLeft
		if not pose_now.is_empty():
			world.show_frame(art, int(pose_now[0]), Vector2(-art_scale.x if facing_right else art_scale.x, art_scale.y))
			return
	if not _action_down.is_empty():
		_action_clock += delta
		var seen: Array = _action_up if facing_up and not _action_up.is_empty() else _action_down
		var frame := int(seen[action_frame() % seen.size()])
		world.show_frame(art, frame, Vector2(-art_scale.x if facing_right else art_scale.x, art_scale.y))
		return
	var frames: Array
	var right_frames: Array = []
	var fps: float
	var f: Dictionary = data.frames
	if moving:
		frames = f.runUpLeft if facing_up else f.runDownLeft
		right_frames = f.runUpRight if facing_up else f.runDownRight
		fps = data.runFps if running else data.walkFps
	else:
		frames = f.idleUpLeft if facing_up else f.idleDownLeft
		fps = data.idleFps
	var has_right := right_frames.size() > 0
	if facing_right and has_right:
		frames = right_frames
	if frames.is_empty():
		return
	var mirror := facing_right and not has_right
	var id := int(frames[int(clock * fps) % frames.size()])
	world.show_frame(art, id, Vector2(-art_scale.x if mirror else art_scale.x, art_scale.y))
