extends Scenario
## Space: she hops; the picture at the top of the arc.
## Run with --window=jump.


func run() -> void:
	var ev := InputEventKey.new()
	ev.keycode = KEY_SPACE
	ev.pressed = true
	Input.parse_input_event(ev)
	await get_tree().process_frame
	await get_tree().process_frame
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(Shots.arg("jumpms", "250")):
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_air.png")
	print("Jump: airborne ", miko.airborne(), " body lift ", miko.wading.extra.y, " shadow ", miko.shadow.scale, " a ", snappedf(miko.shadow.modulate.a, 0.01))
