class_name Sfx
## Sound effects in the world (from Unity's Sfx): louder the nearer the camera, pitched a little at random so repeats
## differ.


## Sounds kept once loaded: Godot forgets a sound when the last thing playing it ends, and loading it again (reading and
## decoding it on the main thread) stalled the frame each time one played.
static var _streams := {}


static func stream(path: String) -> AudioStream:
	if not _streams.has(path):
		_streams[path] = load(path) if ResourceLoader.exists(path) else null
	return _streams[path]


## Loads every sound in the game ahead of time (the loading screen does).
static func preload_all() -> int:
	for dir in ["res://assets/Sounds", "res://assets/Sounds/skills", "res://assets/Resources/Sounds"]:
		for f in DirAccess.get_files_at(dir):
			var path: String = dir.path_join(f.trim_suffix(".import"))
			if path.get_extension() in ["mp3", "wav", "ogg"]:
				stream(path)
	return _streams.size()


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
