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
## While true she ignores movement input (casting, asleep, ...).
var locked := false
# Where she was at the last two physics ticks: she's drawn between them (physics interpolation).
var _was := Vector2.ZERO
var _now := Vector2.ZERO

var art: Sprite2D
var shadow: Sprite2D


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
	art_scale = Vector2(d.art[2], d.art[3])
	add_child(art)
	_animate(0.0)


func _physics_process(_delta: float) -> void:
	var input := Vector2.ZERO
	if not locked:
		input = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
		if Input.is_key_pressed(KEY_A): input.x -= 1
		if Input.is_key_pressed(KEY_D): input.x += 1
		if Input.is_key_pressed(KEY_W): input.y -= 1
		if Input.is_key_pressed(KEY_S): input.y += 1
		input = input.limit_length(1.0)
	running = not locked and Input.is_key_pressed(KEY_SHIFT)
	var now_moving := input.length_squared() > 0.01
	if now_moving != moving:
		clock = 0.0
	moving = now_moving
	# Straight up/down/left/right keeps the other half of the last diagonal.
	if input.y < -0.1: facing_up = true
	elif input.y > 0.1: facing_up = false
	if input.x > 0.1: facing_right = true
	elif input.x < -0.1: facing_right = false
	velocity = Vector2(input.x, input.y * vertical_scale) * (run_speed if running else walk_speed)
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
	_animate(delta)


func _animate(delta: float) -> void:
	clock += delta
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
