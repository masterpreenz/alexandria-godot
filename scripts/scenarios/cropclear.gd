extends Scenario
## Clearing a sown farm plot in the place editor (F7): the plots beside it should stay as they are, not jump in size
## for a moment. Watches each plot's drawn size frame by frame after one is cleared. Run with --window=cropclear.


func _sizes(fm: Farming) -> Array:
	var out := []
	for p in fm.plots:
		if not is_instance_valid(p.node) or p.node.get_child_count() == 0:
			out.append("-")
			continue
		var sp: Sprite2D = p.node.get_child(0)
		var fl: Sprite2D = p.flat.get_child(0) if is_instance_valid(p.flat) else null
		out.append("%s/%s" % [str(snappedf(sp.global_scale.x * (sp.region_rect.size.x if sp.region_enabled else 1.0), 0.1)) if sp.visible else "x",
			str(snappedf(fl.global_scale.x * (fl.region_rect.size.x if fl.region_enabled else 1.0), 0.1)) if fl != null and fl.visible else "x"])
	return out


func run() -> void:
	for i in 20:
		await get_tree().process_frame
	var fm: Farming = miko.get_node("Farming")
	var build: BuildMode = BuildMode.active
	# (the save's own farm: a sown plot in the middle of it)
	var sown := fm.plots.filter(func(p): return fm.stage(p) >= 1)
	var target: Dictionary = sown[floori(sown.size() / 2.0)] if not sown.is_empty() else fm.plots[0]
	var c0 := world.floors.cell_at(target.pos)
	miko.place(target.pos + Vector2(2.0, 1.5) * world.px)
	print("Crop clear: plots ", fm.plots.size(), ", sown ", sown.size(), ", clearing ", c0)
	for i in 20:
		await get_tree().process_frame
	build.toggle_dev()
	build.set_tool("Demolish")
	for i in 10:
		await get_tree().process_frame
	# The mouse over the plot, as a player would: hovered a while, then clicked.
	var vp := get_viewport()
	var screen: Vector2 = vp.get_canvas_transform() * (target.pos as Vector2)
	vp.warp_mouse(screen)
	var mv := InputEventMouseMotion.new()
	mv.position = screen
	mv.global_position = screen
	Input.parse_input_event(mv)
	var before := _sizes(fm)
	print("Crop clear: before ", before)
	var seen0 := {}
	for i in 20:
		await get_tree().process_frame
		var hv := str(_sizes(fm))
		if not seen0.has(hv):
			seen0[hv] = true
			print("Crop clear: hovering, frame ", i, " ", _sizes(fm))
	shot("before")
	for down in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = down
		ev.position = screen
		ev.global_position = screen
		Input.parse_input_event(ev)
		await get_tree().process_frame
	print("Crop clear: after the click, the plot there ", world.props.get_prop(c0, 0), "/", world.props.get_prop(c0, 1))
	var seen := {}
	for i in 30:
		await get_tree().process_frame
		var now := _sizes(fm)
		var key := str(now)
		if not seen.has(key):
			seen[key] = true
			print("Crop clear: frame ", i, " ", now)
		if i < 8 and i % 2 == 0:
			shot("after%d" % i)
