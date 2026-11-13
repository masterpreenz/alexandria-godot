extends Scenario
## The windows' keys: C the character panel, K talents, P the party, L the jobs (not while the map's open: there L
## shows its sections), J the rumors. Each pressed to open, then again to close. Run with --window=keys.


func _press(k: Key) -> void:
	for down in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = k
		ev.physical_keycode = k
		ev.pressed = down
		Input.parse_input_event(ev)
		await get_tree().process_frame
	for i in 4:
		await get_tree().process_frame


func _up() -> Dictionary:
	var hud := get_tree().current_scene.get_node("Hud")
	var cp: CharacterPanel = CharacterPanel._active
	return {"character": cp.window.visible, "talents": cp.talents.visible, "party": (hud.get_node("PartyWindow") as Control).visible,
		"jobs": (hud.get_node("JobsWindow") as Control).visible, "rumors": (hud.get_node("RumorsWindow") as Control).visible,
		"map": (hud.get_node("WorldMap") as Control).visible}


func run() -> void:
	for i in 30:
		await get_tree().process_frame
	if Chronicle.active != null and not Chronicle.active.happened("village_given"):
		Chronicle.active.record("village_given")
	for pair in [[KEY_C, "character"], [KEY_K, "talents"], [KEY_P, "party"], [KEY_L, "jobs"], [KEY_J, "rumors"]]:
		await _press(pair[0])
		var on := _up()
		var opened: Array = on.keys().filter(func(k): return on[k])
		print("Keys: ", OS.get_keycode_string(pair[0]), " opens ", opened)
		await _press(pair[0])
		var off := _up()
		print("Keys: ", OS.get_keycode_string(pair[0]), " again, still open ", off.keys().filter(func(k): return off[k]))
	await _press(KEY_M)
	await _press(KEY_L)
	var m := _up()
	print("Keys: L with the map open: jobs ", m.jobs, ", map ", m.map)
