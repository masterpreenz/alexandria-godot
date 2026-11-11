extends Scenario
## A slime in front of her; the cursor on it and a left click: she swings and it's hit.
## Run with --window=smack.


func run() -> void:
	var md: Dictionary = world._load_json("res://data/monsters.json")
	var spot := miko.position + Vector2(float(Shots.arg("dx", "0.7")), float(Shots.arg("dy", "0.15"))) * world.px
	var sl: Slime = Slime.spawn(world, md.slime, false, spot, 1.0)
	for i in 5:
		await get_tree().process_frame
	var before: float = sl.hit.hp
	var screen := get_viewport().get_canvas_transform() * sl.position
	get_viewport().warp_mouse(screen)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = screen
	click.global_position = screen
	Input.parse_input_event(click)
	var up := click.duplicate() as InputEventMouseButton
	up.pressed = false
	Input.parse_input_event(up)
	var shot_taken := false
	for i in 40:
		await get_tree().process_frame
		if not shot_taken and miko.action_frame() == int(Shots.arg("atframe", "3")):
			shot_taken = true
			get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_swing.png")
	print("Smack: slime hp ", before, " -> ", sl.hit.hp if is_instance_valid(sl) else -1.0, ", Miko facing right ", miko.facing_right, ", locked after ", miko.locked)
