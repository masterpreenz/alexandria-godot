extends Scenario
## How the game runs once the village is attacked (the "Get to the village" beat: the mist in, the horde from four
## sides): frame times and what takes them, on the road and at the village. Run with --window=rushperf --slot=new.


func _measure(label: String) -> void:
	var p: Perf = Perf.active
	p._all_frames.clear()
	Perf._total.clear()
	Perf._worst.clear()
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 5000:
		await get_tree().process_frame
	print(label, ": ", p.summary())


func run() -> void:
	var st: Story = g.get_node("Story")
	for i in 30:
		await get_tree().process_frame
	while str(st._beats()[st.beat].id) != "rush":
		st._begin(st.beat + 1, false)
		await get_tree().process_frame
	await _measure("rush, on the road")
	miko.place(world.village.centre() + Vector2(-10, 3) * world.px)
	await _measure("rush, at the village")
