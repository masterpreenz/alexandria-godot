extends Scenario
## The animation tuner (F4): opened with the key, Miyu's walk shown facing down, her walkCycle slowed to 1.5 and seen
## on a Miyu in the village, her chop stepped to the frame where the axe lands, her walk's frames drawn bigger, Sera's
## run, then Save (the files read back) and Revert + Save (the files as they were). Run with --window=animtuner.


func _key(code: int, alt := false) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = true
	e.alt_pressed = alt
	Input.parse_input_event(e)
	await get_tree().process_frame
	await get_tree().process_frame


func run() -> void:
	for i in 30:
		await get_tree().process_frame
	var files := {}
	for f in [AnimTuner.VILLAGERS, AnimTuner.SPRITES, AnimTuner.PLAYER]:
		files[f] = FileAccess.get_file_as_string(f)
	var tuner: AnimTuner = g.get_node("Hud/AnimTuner")
	await _key(KEY_F4, true)
	print("Animtuner: Alt+F4 leaves it shut: ", not tuner.visible)
	await _key(KEY_F4)
	print("Animtuner: F4 opens it: ", tuner.visible)
	# A Miyu walking about by Sera.
	var miyu: Villager = Villager.all[1]
	miyu.person["unique"] = "miyu"
	miyu.person["name"] = "Miyu"
	miyu.person["look"] = 5
	miyu.look = miyu.people._look_for(miyu.person)
	miyu.s = miyu.look.settings
	miyu.position = miko.position + Vector2(-2.0, 1.0) * world.px
	tuner._pick_look(5)
	tuner._pick_anim("walk")
	tuner._set_facing(false)
	for i in 40:
		await get_tree().process_frame
	shot("miyu_walk")
	var before := miyu._walk_fps()
	tuner.set_value("walkCycle", 1.5)
	print("Animtuner: Miyu's walk fps ", snappedf(before, 0.01), " -> ", snappedf(miyu._walk_fps(), 0.01), " (13 / 1.5 = ", snappedf(13.0 / 1.5, 0.01), "), walkFps now ", miyu.s.walkFps)
	# Her chop, stepped to where the axe lands.
	tuner._pick_anim("chop")
	tuner.set_playing(false)
	var strike := int(tuner.strikes()[0])
	while tuner.frame_index() != strike:
		tuner.step(1)
	await get_tree().process_frame
	await get_tree().process_frame
	print("Animtuner: chop at frame ", tuner.frame_index(), ", strike ", tuner.strikes().has(tuner.frame_index()))
	shot("chop_strike")
	# Her walk's frames a quarter bigger.
	tuner._pick_anim("walk")
	var id := int(tuner.frames_now()[0])
	var ppu := float(world.sprites[id].ppu)
	tuner.set_frame_size(1.25, [0.0, 4.0])
	tuner._build()
	tuner.with_sera = true
	tuner._build()
	print("Animtuner: walk frame ppu ", ppu, " -> ", world.sprites[id].ppu, ", pivot ", world.sprites[id].pivot)
	for i in 10:
		await get_tree().process_frame
	shot("miyu_scaled")
	# Sera's run.
	tuner._pick_look(-1)
	tuner._pick_anim("run")
	for i in 20:
		await get_tree().process_frame
	shot("sera_run")
	# Save, read back; Revert, Save: the files as they were.
	tuner._pick_look(5)
	var ok := tuner.save()
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(AnimTuner.VILLAGERS))
	var sprites: Array = JSON.parse_string(FileAccess.get_file_as_string(AnimTuner.SPRITES))
	print("Animtuner: saved ", ok, ", walkCycle in the file ", saved.looks[5].settings.walkCycle, ", walk frame ppu in the file ", sprites[id].ppu, ", art_tune.json ", FileAccess.file_exists(AnimTuner.ART_TUNE), " (", tuner.said, ")")
	print("Animtuner: other looks unchanged ", JSON.stringify(saved.looks[4]) == JSON.stringify(JSON.parse_string(files[AnimTuner.VILLAGERS]).looks[4]))
	tuner.revert()
	tuner.save()
	for f in files:
		print("Animtuner: ", f, " as it was ", FileAccess.get_file_as_string(f) == files[f])
	print("Animtuner: art_tune.json gone again ", not FileAccess.file_exists(AnimTuner.ART_TUNE), ", Miyu's walk fps back ", snappedf(miyu._walk_fps(), 0.01), ", ppu back ", world.sprites[id].ppu)
	await _key(KEY_ESCAPE)
	print("Animtuner: Esc closes it: ", not tuner.visible)
