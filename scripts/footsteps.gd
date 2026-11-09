class_name Footsteps
extends Node
## Footsteps (from Unity's Footsteps): a looping step sound on grass or on anything laid over it (paths, stone,
## boards), crossfaded as she moves between them; quieter and lower walking than running, fading in and out as she
## starts and stops.

var world: World
var walker: Node2D
var volume := 0.6
var walk_pitch := 0.8
var walk_volume := 0.6
var fade := 0.08

var on_grass: AudioStreamPlayer
var on_solid: AudioStreamPlayer
var grass_mix := 1.0  # 1 all grass, 0 all solid
var level := 0.0      # 0 still, 1 moving


func setup(w: World, who: Node2D) -> void:
	world = w
	walker = who
	on_grass = _player(preload("res://assets/Sounds/running_grass.wav"))
	on_solid = _player(preload("res://assets/Sounds/running_solid.wav"))


func _player(stream: AudioStream) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = -80.0
	add_child(p)
	return p


func _process(delta: float) -> void:
	var __t := Time.get_ticks_usec()
	_process_timed(delta)
	Perf.add(&"footsteps.process", __t)


func _process_timed(delta: float) -> void:
	var moving: bool = walker.get("moving")
	var running: bool = walker.get("running")
	var step := delta / maxf(0.01, fade)
	level = move_toward(level, 1.0 if moving else 0.0, step)
	grass_mix = move_toward(grass_mix, 0.0 if world.on_floor(walker.position) else 1.0, step)
	var pitch := 1.0 if running else walk_pitch
	var loud := volume * level * (1.0 if running else walk_volume)
	_drive(on_grass, loud * grass_mix, pitch)
	_drive(on_solid, loud * (1.0 - grass_mix), pitch)


static func _drive(p: AudioStreamPlayer, vol: float, pitch: float) -> void:
	p.volume_db = linear_to_db(maxf(vol, 0.0001))
	p.pitch_scale = pitch
	# Starts from a random point so it doesn't always open on the same step.
	if vol > 0.001 and not p.playing:
		p.play(randf() * p.stream.get_length() * 0.9)
	elif vol <= 0.001 and p.playing:
		p.stop()
