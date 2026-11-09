class_name Sfx
## Sound effects in the world (from Unity's Sfx): louder the nearer the camera, pitched a little at random so repeats
## differ.


static func play(owner: Node, stream: AudioStream, at: Vector2, volume := 1.0, jitter := 0.0) -> void:
	if stream == null or owner == null or not owner.is_inside_tree():
		return
	var p := AudioStreamPlayer2D.new()
	p.stream = stream
	p.volume_db = linear_to_db(maxf(volume, 0.0001))
	p.pitch_scale = 1.0 + randf_range(-jitter, jitter)
	p.max_distance = 3000.0
	p.attenuation = 1.5
	p.position = at
	owner.get_tree().current_scene.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
