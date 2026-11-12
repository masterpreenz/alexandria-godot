extends Scenario
## Every part timed, all of them (not just the top few): what each costs a frame and how often it runs, in the
## village by day and in the night fight. Run with --window=allcosts --slot=new.


func _list(label: String) -> void:
	var p: Perf = Perf.active
	p._all_frames.clear()
	Perf._total.clear()
	Perf._worst.clear()
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 6000:
		miko.stats.hp = miko.stats.stat("maxHp")
		await get_tree().process_frame
	var n := float(p._all_frames.size())
	var rows := p._sorted(Perf._total, n)
	print("All costs (", label, "): ", p.summary().split("\n")[0])
	for r in rows:
		if r[1] >= 0.02:
			print("  %6.3f ms  %6.1f calls  %s" % [r[1], r[2], r[0]])


func run() -> void:
	var st: Story = g.get_node("Story")
	for i in 30:
		await get_tree().process_frame
	miko.place(world.village.centre() + Vector2(1, 1) * world.px)
	for i in 60:
		await get_tree().process_frame
	await _list("the village by day")
	Chronicle.active.record("scene:messenger")
	while str(st._beats()[st.beat].id) != "rush":
		st._begin(st.beat + 1, false)
		await get_tree().process_frame
	miko.place(world.village.centre() + Vector2(1, 1) * world.px)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 8000:
		miko.stats.hp = miko.stats.stat("maxHp")
		await get_tree().process_frame
	await _list("the night fight")
