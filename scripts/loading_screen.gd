class_name LoadingScreen
extends CanvasLayer
## The loading screen: covers the game while it sets up, then warms up its shaders behind the cover. Godot compiles a
## shader (and its pipeline) the first time something drawn with it comes on screen, which stalls that frame: walking
## into a new part of the world hitched. So, before play starts, the camera looks over the whole world from far out
## and then sweeps across it, the world map draws once, and the common effects (puffs, floating text, the level-up
## sparkles) play once, all unseen and with the sound off. Then the cover fades away.

var _bar: ProgressBar
var _runner: RunningMiko
var _shown := 0.0             ## where she's run to (eases towards the progress)
var _target := 0.0
var _step: Label
var _cover: ColorRect


func _init() -> void:
	layer = 126
	_cover = ColorRect.new()
	_cover.color = Color(0.06, 0.05, 0.05)
	_cover.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cover.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_cover)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BOTH
	box.custom_minimum_size = Vector2(420, 0)
	box.add_theme_constant_override("separation", 14)
	_cover.add_child(box)
	var title := Label.new()
	title.text = "Alexandria"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color(1, 0.86, 0.6))
	box.add_child(title)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(420, 10)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(1, 1, 1, 0.08)
	back.set_corner_radius_all(5)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.95, 0.71, 0.27)
	fill.set_corner_radius_all(5)
	_bar.add_theme_stylebox_override("background", back)
	_bar.add_theme_stylebox_override("fill", fill)
	# Miko runs along the track as it fills, from its start to its end.
	_runner = RunningMiko.new()
	_runner.height = 72
	_runner.custom_minimum_size = Vector2(72, 76)
	_runner.size = _runner.custom_minimum_size
	var track := Control.new()
	track.custom_minimum_size = Vector2(420, 76)
	track.add_child(_runner)
	box.add_child(track)
	box.add_child(_bar)
	_step = Label.new()
	_step.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_step.add_theme_color_override("font_color", Color(0.8, 0.72, 0.6))
	_step.add_theme_font_size_override("font_size", 14)
	box.add_child(_step)
	step("Setting up the world", 0.1)


## Gives her the world's sprites to run with.
func set_world(w: World) -> void:
	_runner.setup(w)


func step(text: String, share: float) -> void:
	_step.text = text + "…"
	_target = share


func _process(delta: float) -> void:
	_shown = move_toward(_shown, _target, delta * 1.5)
	_bar.value = _shown * 100.0
	var track := _runner.get_parent() as Control
	_runner.position = Vector2(_shown * track.size.x - _runner.size.x / 2.0, 0)   # her feet at the fill's end


## Warms the shaders up behind the cover, then fades it away. [param area] is the world (px).
func warm_up(game: Node, world: World, miko: Miko, camera: Camera2D, area: Rect2) -> void:
	var tree := game.get_tree()
	var master := AudioServer.get_bus_index("Master")
	var was_muted := AudioServer.is_bus_mute(master)
	AudioServer.set_bus_mute(master, true)
	var was_locked := miko.locked
	miko.locked = true
	var was_zoom := camera.zoom
	var was_smoothing := camera.position_smoothing_enabled
	camera.position_smoothing_enabled = false
	var view := game.get_viewport().get_visible_rect().size
	step("Loading sounds", 0.15)
	Sfx.preload_all()
	await tree.process_frame
	# The whole world at once: everything in it drawn in a frame or two.
	step("Preparing the world's look", 0.25)
	camera.zoom = Vector2.ONE * minf(view.x / area.size.x, view.y / area.size.y)
	camera.position = area.get_center()
	game.set_meta("warming", true)
	for i in 4:
		await tree.process_frame
	# Then across it, nearer, so what only shows up close (and small things) is drawn too.
	var steps := 4
	camera.zoom = was_zoom * 0.5
	var n := 0
	for gy in steps:
		for gx in steps:
			camera.position = area.position + Vector2((gx + 0.5) / steps * area.size.x, (gy + 0.5) / steps * area.size.y)
			n += 1
			step("Preparing the world's look", 0.25 + 0.5 * n / float(steps * steps))
			await tree.process_frame
			await tree.process_frame
	# The effects, once each, beside Miko.
	step("Preparing effects", 0.8)
	if Shots.arg("loadshot") != "":
		# Test runs: a picture of the cover mid-way, Miko part way along the bar.
		for i in 3:
			await tree.process_frame
		game.get_viewport().get_texture().get_image().save_png(Shots.arg("loadshot"))
	# (Played out at the world's far corner, where no one will see them once the cover lifts.)
	camera.zoom = was_zoom
	var spot := Node2D.new()
	spot.position = area.position + Vector2(200, 200)
	world.things.add_child(spot)
	camera.position = spot.position
	Puffs.burst(world, spot.position + Vector2(64, 0), 1.0, 6)
	FloatingText.spawn(world, "·", spot.position, Color.WHITE)
	LevelUp.play(world, spot, 1)
	var wm: Node = game.get_node_or_null("Hud/WorldMap")
	if wm != null:
		wm.open()
	for i in 4:
		await tree.process_frame
	if wm != null:
		wm.close()
	spot.queue_free()
	# Back to how it was, and the cover fades away.
	step("Ready", 1.0)
	while _shown < 1.0:
		await tree.process_frame
	game.remove_meta("warming")
	camera.position = miko.drawn_position()
	camera.position_smoothing_enabled = was_smoothing
	camera.reset_smoothing()
	miko.locked = was_locked
	await tree.process_frame
	AudioServer.set_bus_mute(master, was_muted)
	var tw := create_tween()
	tw.tween_property(_cover, "modulate:a", 0.0, 0.35)
	await tw.finished
	queue_free()
