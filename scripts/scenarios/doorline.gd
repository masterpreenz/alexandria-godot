extends Scenario
## Door outlines: how many show with Miko away from them, then beside each back-wall door in turn.
## Run with --window=doorline.


func run() -> void:
	for i in 10:
		await get_tree().process_frame
	var outlines := func() -> Array:
		var found := []
		for k in world.walls.walls:
			for n in world.walls.nodes_of(WallMap.Edge.of(k)):
				if is_instance_valid(n):
					for o in n.find_children("DoorOutline", "", true, false):
						found.append([k, o])
		return found
	var all_lines: Array = outlines.call()
	miko.place(world.village.centre() + Vector2(0, 14.0) * world.px)
	for i in 40:
		await get_tree().process_frame
	print("Door outlines: ", all_lines.size(), ", showing with Miko away ", outlines.call().filter(func(x): return (x[1] as OccludedOutline).outline.visible).size())
	for x0 in all_lines:
		var key: Vector3i = x0[0]
		miko.place(world.walls.wall_middle(key) + Vector2(0, -0.6) * world.px)
		for i in 40:
			await get_tree().process_frame
		var now_lines: Array = outlines.call().filter(func(y): return y[0] == key)
		if now_lines.is_empty():
			continue
		var x: Array = now_lines[0]
		if (x[1] as OccludedOutline).covered:
			print("Door outline beside ", x[0], ": showing ", (x[1] as OccludedOutline).outline.visible)
			get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_near.png")
			break
