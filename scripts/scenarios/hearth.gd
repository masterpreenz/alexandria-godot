extends Scenario
## In a house: where a fireplace may go (each cell's turn), one put against each back wall, lit; the
## chimney over it, smoking; a house with none: no smoke.
## Run with --window=hearth.


func run() -> void:
	var bm := BuildMode.active
	var room: Dictionary = world.roofs.roofs[0].cells
	var by_turn := {}
	for c in room:
		var t := bm.hearth_turn(c)
		by_turn[t] = int(by_turn.get(t, 0)) + 1
	print("Hearth: cells by turn (-1 none, 0 back up-right, 1 back up-left) ", by_turn)
	var placed := []
	for want in [0, 1]:
		for c in room:
			if bm.hearth_turn(c) == want and world.props.peek_where(c, func(_n): return true) == "" and not bm._use_cells().has(c) and not placed.has(c):
				world.props.place(c, "Fireplace", 1.0, want)
				placed.append(c)
				break
	for c in room:
		if bm.hearth_turn(c) >= 0 or bm.hearth_turn(c) == -2:
			var why := bm.why_not(bm.item_for("Prop", "Fireplace"), world.floors.cell_centre(c))
			if why != ("Not in a corner" if bm.hearth_turn(c) == -2 else "") and not why.begins_with("Keep clear"):
				print("Hearth: cell ", c, " turn ", bm.hearth_turn(c), " refused '", why, "'")
	print("Hearth: a middle cell refused '", bm.why_not(bm.item_for("Prop", "Fireplace"), world.floors.cell_centre(room.keys().filter(func(c): return bm.hearth_turn(c) < 0)[0])), "'")
	var fr: Fires = miko.get_node("Fires")
	for i in 60:
		await get_tree().process_frame
	var smoking := func() -> Array: return world.roofs.roofs.map(func(r): return r.smoke != null and (r.smoke.get_child(0) as CPUParticles2D).emitting)
	print("Hearth: chimney of the house at ", world.roofs.roofs[0].chimney, ", fireplaces at ", placed, "; smoking ", smoking.call())
	for f in fr.fires:
		fr.lit_until.erase(f.key)
	for i in 60:
		await get_tree().process_frame
	print("Hearth: all fires out, smoking ", smoking.call())
	for f in fr.fires:
		if bool(f.s.get("hearth", false)):
			fr.light(f)
	miko.place(world.floors.cell_centre(room.keys()[12]))
	camera.zoom *= 1.4
	for i in 90:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_in.png")
	miko.place(world.floors.cell_centre(placed[0]) + Vector2(-5.0, 4.0) * world.px)
	for i in 150:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_out.png")
