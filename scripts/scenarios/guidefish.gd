extends Scenario
## The starter guide's later steps: build a Tool Workbench, make a Fishing Rod there, then a Fishing Dock on the river
## and a fish caught (against hunger). An older game that had finished the guide picks them up once Miyu's home.
## Run with --window=guidefish.


func run() -> void:
	for i in 30:
		await get_tree().process_frame
	var st: Story = Story.active
	var ch := Chronicle.active
	var ids: Array = st._beats().map(func(b): return str(b.get("id", "")))
	print("Guide fish: beats ", ids.slice(ids.find("crystal")), ", on now ", st.beat)
	# An older game: the guide done, the intro over, Miyu home.
	ch.events = ch.events.filter(func(e): return not str(e.what) in ["guide_fishing", "fish_caught"])
	for e in ["intro_done", "miyu_home"]:
		if not ch.happened(e):
			ch.record(e)
	st._finish()
	st._caught_up = false
	st._catch_up_at = 0.0
	for i in 30:
		await get_tree().process_frame
	print("Guide fish: caught up to ", ids[st.beat] if st.beat >= 0 else "-", " (workbenches here ", world.props_named("ToolWorkbench").size(), ")")
	# Each step from the start, nothing of it about.
	var bench := ids.find("workbench")
	st._begin(bench, false)
	for i in 10:
		await get_tree().process_frame
	print("Guide fish: '", st._title.text, "' / '", st._hint.text.replace("\n", " | "), "'")
	shot("workbench")
	for i in 40:
		await get_tree().process_frame
	print("Guide fish: after the workbench step, on ", ids[st.beat] if st.beat >= 0 else "-")
	if ids[st.beat] == "rod":
		var fiber0 := miko.bag.count("Fiber")
		print("Guide fish: rod step '", st._hint.text.replace("\n", " | "), "', fiber ", fiber0)
		shot("rod")
		var free := miko.bag.free_slot()
		miko.bag.items[free] = "FishingRod"
		for i in 40:
			await get_tree().process_frame
	print("Guide fish: after the rod, on ", ids[st.beat] if st.beat >= 0 else "-")
	if st.beat >= 0 and ids[st.beat] == "fish":
		miko.place(world.floors.cell_centre(Vector2i(-32, -32)))
		for i in 20:
			await get_tree().process_frame
		shot("fish")
		var spot := Vector2i(-33, -32)
		for x in range(-36, -30):
			for y in range(-36, -28):
				var at := world.floors.cell_centre(Vector2i(x, y))
				if Fishing.water_near(world, at) and world.water_depth(at) <= 0.0:
					spot = Vector2i(x, y)
		world.props.place(spot, "FishingDock")
		for i in 30:
			await get_tree().process_frame
		print("Guide fish: dock at ", spot, ", parts done ", st._did.keys())
		ch.record("fish_caught")
		for i in 40:
			await get_tree().process_frame
	print("Guide fish: at the end, beat ", st.beat, ", guide_fishing ", ch.happened("guide_fishing"))
