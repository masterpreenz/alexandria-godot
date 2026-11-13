class_name Sfx
## Sound effects in the world (from Unity's Sfx): louder the nearer the camera, pitched a little at random so repeats
## differ.


## Sounds kept once loaded: Godot forgets a sound when the last thing playing it ends, and loading it again (reading and
## decoding it on the main thread) stalled the frame each time one played.
static var _streams := {}

## Sounds that come in kinds, a few takes of each (assets/Sounds/Combat): one picked at random each time, never the
## same take twice running, so a fight doesn't sound like one clip on repeat.
const GROUPS := {
	"blunt": "res://assets/Sounds/Combat/atk_blunt_%d.mp3",              # a staff or club landing; a wall struck
	"scratch": "res://assets/Sounds/Combat/atk_scratch_%d.mp3",          # a monster's claws or bite on someone
	"flesh": "res://assets/Sounds/Combat/atk_sword_flesh_%d.mp3",        # a blade or spear going in
}
const TAKES := 4
static var _last_take := {}       ## group -> the take played last


## One take of the kind [param group] (GROUPS), not the one played last.
static func one_of(group: String) -> AudioStream:
	var last := int(_last_take.get(group, -1))
	var i := randi() % TAKES + 1
	if i == last:
		i = i % TAKES + 1
	_last_take[group] = i
	return stream(GROUPS[group] % i)


static func stream(path: String) -> AudioStream:
	if not _streams.has(path):
		_streams[path] = load(path) if ResourceLoader.exists(path) else null
	return _streams[path]


## Loads every sound in the game ahead of time (the loading screen does).
static func preload_all() -> int:
	for dir in ["res://assets/Sounds", "res://assets/Sounds/Wolf", "res://assets/Sounds/Combat", "res://assets/Sounds/skills", "res://assets/Sounds/Dialog", "res://assets/Resources/Sounds"]:
		for f in DirAccess.get_files_at(dir):
			var path: String = dir.path_join(f.trim_suffix(".import"))
			if path.get_extension() in ["mp3", "wav", "ogg"]:
				stream(path)
	return _streams.size()


## Keeps a looping sound player ([param p], 2D or not) going while [param on], and paused (not stopped) while not,
## so coming back to it never seeks. (Starting an MP3 part-way in decodes it from the start up to there, about a
## millisecond per second in: a long river loop started at a random point stalled the game for up to 150 ms.)
static func keep_going(p: Variant, on: bool) -> void:
	if on:
		if not p.playing:
			p.play()
		p.stream_paused = false
	elif p.playing:
		p.stream_paused = true


static func play(owner: Node, clip: AudioStream, at: Vector2, volume := 1.0, jitter := 0.0) -> void:
	if clip == null or owner == null or not owner.is_inside_tree():
		return
	var p := AudioStreamPlayer2D.new()
	p.stream = clip
	p.volume_db = linear_to_db(maxf(volume, 0.0001))
	p.pitch_scale = 1.0 + randf_range(-jitter, jitter)
	p.max_distance = 3000.0
	p.attenuation = 1.5
	p.position = at
	owner.get_tree().current_scene.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


## Sounds that come thick and fast (ice shards landing), kept from piling up: key -> those of it playing now, and when
## the last one started.
static var _capped := {}
static var _capped_at := {}


## Plays [param clip] as [method play] does, unless [param most] of [param key] are playing already or the last
## started under [param gap] seconds ago (then it's skipped); each already playing makes this one a little quieter.
## Whether it played.
static func play_capped(owner: Node, clip: AudioStream, at: Vector2, volume := 1.0, jitter := 0.06, key := "", most := 3, gap := 0.08) -> bool:
	if clip == null or owner == null or not owner.is_inside_tree():
		return false
	var k := key if key != "" else clip.resource_path
	var now := Time.get_ticks_msec() / 1000.0
	var on: Array = (_capped.get(k, []) as Array).filter(func(q): return is_instance_valid(q) and (q as AudioStreamPlayer2D).playing)
	_capped[k] = on
	if on.size() >= most or now - float(_capped_at.get(k, -99.0)) < gap:
		return false
	var p := AudioStreamPlayer2D.new()
	p.stream = clip
	p.volume_db = linear_to_db(maxf(volume * pow(0.8, on.size()), 0.0001))
	p.pitch_scale = 1.0 + randf_range(-jitter, jitter)
	p.max_distance = 3000.0
	p.attenuation = 1.5
	p.position = at
	owner.get_tree().current_scene.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
	on.append(p)
	_capped_at[k] = now
	return true
