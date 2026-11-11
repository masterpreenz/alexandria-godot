class_name Melee
extends Node
## Miko's staff smack (left click): she turns towards the cursor and swings her staff down in front of her (her
## attack frames, drawn facing left like the rest), and on the downswing every monster within reach there takes a
## knock: 2 damage and half her Attack (a staff's no weapon: well under a Fireball). One swing every
## [constant SWING_EVERY] seconds at most (quicker with Attack Speed); holding the button keeps swinging. Not while a spell is being aimed, in build mode,
## with her character panel open, or while she's busy (cooking, sleeping, casting...).

const DOWNSWING := 3          ## the frame the staff comes down on (counted from 0)
const REACH := 0.8            ## units in front of her the smack lands
const SWEEP := 1.15           ## units round that it reaches: everything close together there is hit
const BASE_DAMAGE := 2.0
const ATTACK_SHARE := 0.5     ## of her Attack added to it
const SWING_EVERY := 0.8      ## seconds from one swing to the next, at the least

var world: World
var miko: Miko
var _swinging := false
var _struck := false
var _slashed := false
var _was_locked := false
var _toward := Vector2.RIGHT
var _hit_sound: AudioStream
var _next_swing := 0.0
var _held := false            ## the button's still down from a swing she started
var _swing_sound: AudioStream


func setup(w: World, who: Miko) -> void:
	world = w
	miko = who
	_hit_sound = Sfx.stream("res://assets/Sounds/blunt_staff_hit.mp3")      # when it lands on something
	_swing_sound = Sfx.stream("res://assets/Sounds/blunt_sonic_sound.mp3")  # every swing, hit or miss


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and _can_swing():
		_swing(event.position)
		get_viewport().set_input_as_handled()


func _can_swing() -> bool:
	if _swinging or miko.locked or BuildMode.is_open() or CharacterPanel.up():
		return false
	if Time.get_ticks_msec() / 1000.0 < _next_swing:
		return false
	var caster := world.get_node_or_null("Caster") as SpellCaster
	return caster == null or (caster.aiming == "" and not caster.casting)


# Towards [param screen] (the click, on screen).
func _swing(screen: Vector2) -> void:
	var frames: Dictionary = miko.data.frames
	if not frames.has("attackDownLeft"):
		return
	_toward = get_viewport().get_canvas_transform().affine_inverse() * screen - miko.position
	if _toward.length() < 1.0:
		_toward = Vector2.RIGHT if miko.facing_right else Vector2.LEFT
	var speed := miko.stats.stat("attackSpeed") if miko.stats != null else 0.0
	_next_swing = Time.get_ticks_msec() / 1000.0 + SWING_EVERY / (1.0 + maxf(0.0, speed) / 100.0)
	_swinging = true
	_held = true
	_struck = false
	_slashed = false
	_was_locked = miko.locked
	miko.locked = true   # planted while she swings
	miko.play_action(frames.attackDownLeft, frames.attackUpLeft, float(miko.data.get("attackFps", 16)), _toward)


func _process(delta: float) -> void:
	var __t := Time.get_ticks_usec()
	_process_timed(delta)
	Perf.add(&"melee.process", __t)


func _process_timed(_delta: float) -> void:
	# Held down (from a swing of hers: not a click on something else): the next swing as soon as it's due.
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_held = false
	if not _swinging:
		if _held and _can_swing():
			_swing(get_viewport().get_mouse_position())
		return
	var f := miko.action_frame()
	# The slash sweeps out a moment before the staff lands.
	if f >= DOWNSWING - 1 and not _slashed:
		_slashed = true
		Slash.play(world, miko.position, _toward, Color(1.0, 0.93, 0.72, 0.9), 1.35)
		if _swing_sound != null:
			Sfx.play(world, _swing_sound, miko.position, 0.6, 0.08)
	if f >= DOWNSWING and not _struck:
		_struck = true
		_strike()
	var length: int = (miko.data.frames.attackDownLeft as Array).size()
	if f >= length:
		_swinging = false
		miko.end_action()
		if miko.stats == null or miko.stats.hp > 0.0:
			miko.locked = _was_locked   # (not if she fell mid-swing: fainting holds her)


# The staff lands in front of her (on the ground, so a step up the screen counts half): every monster there is hit.
func _strike() -> void:
	var dir := Vector2(_toward.x, _toward.y * 2.0).normalized()
	var at := miko.position + Vector2(dir.x, dir.y * 0.5) * REACH * world.px
	var attack := miko.stats.stat("attack") if miko.stats != null else 0.0
	var n := Damageable.hit_around(at, SWEEP * world.px, BASE_DAMAGE + attack * ATTACK_SHARE, Damageable.Team.ENEMY, true)
	if n > 0 and _hit_sound != null:
		Sfx.play(world, _hit_sound, at, 0.55, 0.12)
