extends Scenario
## Sera by the farm field at night: how long frames take there, which parts cost the most, and whether the count of
## nodes keeps climbing while she stands there. Run with --window=farmnight (add --slot=auto for a save of your own;
## a test never saves). --stay=1 keeps her where the save left her instead of walking her to the middle of the plots;
## either way it's made night.


func _list(label: String, seconds: float) -> void:
	var p: Perf = Perf.active
	var worst := Perf._worst.keys()
	worst.sort_custom(func(a, b): return Perf._worst[a] > Perf._worst[b])
	print("Farmnight: worst frames so far (loading): ", ", ".join(worst.slice(0, 8).map(func(k): return "%s %.1f" % [k, Perf._worst[k] / 1000.0])))
	p._all_frames.clear()
	Perf._total.clear()
	Perf._worst.clear()
	var t0 := Time.get_ticks_msec()
	var n0 := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	var next := 0
	var mm: Minimap = Minimap.active
	var _renders := 0
	var drawn_at: float = mm._drawn_at
	while Time.get_ticks_msec() - t0 < seconds * 1000.0:
		if Time.get_ticks_msec() - t0 >= next:
			next += 2000
			print("Farmnight: %s  t %.0fs  nodes %d  objects %d  fps %d" % [label, (Time.get_ticks_msec() - t0) / 1000.0,
				Performance.get_monitor(Performance.OBJECT_NODE_COUNT), Performance.get_monitor(Performance.OBJECT_COUNT),
				Engine.get_frames_per_second()])
		await get_tree().process_frame
		if mm._drawn_at != drawn_at:
			drawn_at = mm._drawn_at
			_renders += 1
	var cr: Corruption = Corruption.active
	print("Farmnight: rotten trees ", cr.corrupted.size(), ", near her ", cr.armed.size(), ", curing ", cr.curing.size(),
		", cleansing crystals ", world.props_named("CleansingCrystal").size(), ", trees ", Gatherable.all.size())
	var frames: PackedFloat32Array = p._all_frames.duplicate()
	frames.sort()
	var n := frames.size()
	print("Farmnight: %s  frames %d  median %.1f ms  95%% %.1f  worst %.1f  nodes %d -> %d" % [label, n,
		frames[int(n / 2.0)], frames[int(n * 0.95)], frames[n - 1], n0, Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
	var rows := p._sorted(Perf._total, float(n))
	for r in rows.slice(0, 30):
		print("  %6.3f ms  %6.1f calls  worst %6.2f  %s" % [r[1], r[2], float(Perf._worst.get(r[0], 0)) / 1000.0, r[0]])


## What kinds of node there are most of, and under what.
func _census() -> void:
	var by := {}
	var under := {}
	var stack: Array = [get_tree().root]
	while not stack.is_empty():
		var nd: Node = stack.pop_back()
		var k := nd.get_class()
		by[k] = int(by.get(k, 0)) + 1
		var par := nd.get_parent()
		if par != null:
			var pk := "%s(%s)" % [par.name, par.get_class()]
			under[pk] = int(under.get(pk, 0)) + 1
		stack.append_array(nd.get_children())
	var ks := by.keys()
	ks.sort_custom(func(a, b): return by[a] > by[b])
	print("Farmnight: nodes by kind: ", ", ".join(ks.slice(0, 14).map(func(k): return "%s %d" % [k, by[k]])))
	var us := under.keys()
	us.sort_custom(func(a, b): return under[a] > under[b])
	print("Farmnight: most children under: ", ", ".join(us.slice(0, 14).map(func(k): return "%s %d" % [k, under[k]])))


func run() -> void:
	for i in 60:
		await get_tree().process_frame
	var fm: Farming = miko.get_node("Farming")
	print("Farmnight: at ", clock.time_text(), ", Sera at ", miko.position / world.px, ", plots ", fm.plots.size(),
		", on screen ", fm.plots.filter(func(p): return world.on_screen(p.pos, 2.0)).size())
	_census()
	if Shots.arg("stay") == "":
		# The middle of the plots.
		var mid := Vector2.ZERO
		for p in fm.plots:
			mid += p.pos
		if not fm.plots.is_empty():
			miko.place(mid / fm.plots.size() + Vector2(0, 1.5) * world.px)
	if clock.hours - float(clock.day() - 1) * 24.0 < 21.0:
		clock.hours = float(clock.day() - 1) * 24.0 + 22.5
	for i in 60:
		await get_tree().process_frame
	print("Farmnight: now ", clock.time_text(), ", Sera at ", miko.position / world.px, ", plots on screen ",
		fm.plots.filter(func(p): return world.on_screen(p.pos, 2.0)).size())
	shot("field")
	await _list("by the field at night", 20.0)
	_census()
	shot("after")
