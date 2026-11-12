extends Scenario
## The way to Miyu: Sera walks from where she is up the road west to the next village at running pace, and the slow
## frames on the way are printed (with --perf=1, each with what took the time). Run with --window=westwalk --perf=1.


func run() -> void:
	for i in 60:
		await get_tree().process_frame
	# (the forest's hour: rot creeping in, done at once; what it costs)
	var t0 := Time.get_ticks_usec()
	Corruption.active._tick()
	var ms_tick := (Time.get_ticks_usec() - t0) / 1000.0
	var worst := 0.0
	var slices := 0
	while not Corruption.active._hour_left.is_empty():
		t0 = Time.get_ticks_usec()
		Corruption.active._tick_some()
		worst = maxf(worst, (Time.get_ticks_usec() - t0) / 1000.0)
		slices += 1
	print("West walk: the forest's hour: begun in %.1f ms, then %d frames' share, the most %.1f ms (%d rotten of %d trees)" % [ms_tick, slices, worst, Corruption.active.corrupted.size(), Corruption.active._trees().size()])
	var to := world.floors.cell_centre(Vector2i(int(Shots.arg("tox", "-250")), int(Shots.arg("toy", "110"))))
	var step := float(Shots.arg("pace", "0.1")) * world.px
	var p: Perf = Perf.active
	p._all_frames.clear()
	Perf._total.clear()
	Perf._worst.clear()
	var from := miko.position
	var frames := 0
	var slow := []
	var last := Time.get_ticks_usec()
	while miko.position.distance_to(to) > step and frames < 6000:
		miko.place(miko.position.move_toward(to, step))
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var ms := (now - last) / 1000.0
		last = now
		frames += 1
		if ms > 40.0:
			slow.append("%.0f ms at %d units (physics: active %d, pairs %d, islands %d; solids' shapes %d; trees and rocks %d)" % [ms, roundi(miko.position.distance_to(from) / world.px),
				Performance.get_monitor(Performance.PHYSICS_2D_ACTIVE_OBJECTS), Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS), Performance.get_monitor(Performance.PHYSICS_2D_ISLAND_COUNT),
				world.solids.get_child_count(), Gatherable.all.size()])
	print("West walk: physics now: active %d, pairs %d, islands %d" % [Performance.get_monitor(Performance.PHYSICS_2D_ACTIVE_OBJECTS), Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS), Performance.get_monitor(Performance.PHYSICS_2D_ISLAND_COUNT)])
	print("West walk: ", frames, " frames, ", roundi(miko.position.distance_to(from) / world.px), " units; frames over 40 ms: ", slow.size(), " ", slow.slice(0, 40))
	print("West walk: ", p.summary())
