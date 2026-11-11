extends Scenario
## One cellar only; expanded (U at its doors) for a bigger room that keeps more.
## Run with --window=cellargrow.


func run() -> void:
	var cl: Cellars = Cellars.active
	var bm := BuildMode.active
	var c0 := world.floors.cell_at(world.village.centre())
	var cellar_item := bm.item_for("Prop", "Cellar")
	var spot := c0
	for r in range(2, 12):
		for dx in range(-r, r + 1):
			var cc := c0 + Vector2i(dx, r)
			if spot == c0 and not bm.no_build(cc) and bm.why_not(cellar_item, world.floors.cell_centre(cc)) == "":
				spot = cc
	if cl.all().is_empty():
		world.props.place(spot, "Cellar")
	await get_tree().process_frame
	print("Cellar grow: cellars ", cl.all().size(), ", a second one: '", bm.why_not(cellar_item, world.floors.cell_centre(spot + Vector2i(4, 0))), "'")
	world.props.place(Cellars.AT + Vector2i(4, 4), "Chest")
	miko.bag.counts["Wood"] = 60
	miko.bag.counts["Stone"] = 130
	miko.place(cl.all()[0] + Vector2(0.9, 0.5) * world.px)
	for i in 10:
		await get_tree().process_frame
	print("Cellar grow: level ", cl.level, ", side ", Cellars.side, ", holds ", cl.holds(), ", prompt '", cl.prompt.text.replace("\n", " / "), "'")
	for n in 4:
		var key := InputEventKey.new()
		key.keycode = KEY_U
		key.pressed = true
		Input.parse_input_event(key)
		for i in 6:
			await get_tree().process_frame
		print("Cellar grow: U: level ", cl.level, ", side ", Cellars.side, ", holds ", cl.holds(), ", wood ", miko.bag.count("Wood"), ", stone ", miko.bag.count("Stone"),
			", far corner in the room ", Cellars.room_has(Cellars.AT + Vector2i(Cellars.side - 1, Cellars.side - 1)), ", the chest still there ", world.props.cells.has(Vector3i(Cellars.AT.x + 4, Cellars.AT.y + 4, 1)) or world.props_named("Chest").has(world.floors.cell_centre(Cellars.AT + Vector2i(4, 4))))
	var cellar_save := cl.to_json()
	cl.from_json(JSON.stringify({"cold": 0, "level": 1}))
	cl.from_json(cellar_save)
	print("Cellar grow: saved and loaded: level ", cl.level, ", side ", Cellars.side, "; a chest may go at the far corner: '", bm.why_not(bm.item_for("Prop", "Chest"), world.floors.cell_centre(Cellars.AT + Vector2i(Cellars.side - 1, Cellars.side - 1))), "'")
	miko.place(world.floors.cell_centre(Cellars.AT + Vector2i(3, 3)))
	for i in 30:
		await get_tree().process_frame
