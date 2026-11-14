extends Scenario
## A small field by Sera taken through its looks: bare, sown, pests in, pests cleared, dried out, ripe, harvested.
## Each is a picture, and the plot's soil and crop pictures are printed, to see each change shows on time (the plots
## are only drawn again when something changes). Run with --window=plotlooks.


func _say(fm: Farming, what: String) -> void:
	for i in 3:
		await get_tree().process_frame
	var p: Dictionary = fm.plots.filter(func(q): return q.pos.distance_to(miko.position) < 4.0 * world.px)[0]
	var flat: Sprite2D = p.flat.get_child(0)
	var top: Sprite2D = (p.node as Node2D).get_child(0)
	var m: Variant = p.get("mark")
	print("Plotlooks: %s  stage %d dry %s pests %s  drawn %s  soil shown %s  crop shown %s  bubble %s" % [what, fm.stage(p),
		fm.dry(p), fm.pests(p), p.get("drawn"), flat.visible, top.visible, is_instance_valid(m) and (m as Sprite2D).visible])
	shot(what)


func run() -> void:
	var fm: Farming = miko.get_node("Farming")
	clock.hours = float(clock.day() - 1) * 24.0 + 9.0
	var c0 := world.floors.cell_at(world.village.centre()) + Vector2i(3, 3)
	for k in 4:
		world.props.place(c0 + Vector2i(k % 2, floori(k / 2.0)), "FarmPlot")
	for i in 5:
		await get_tree().process_frame
	miko.place(world.floors.cell_centre(c0) + Vector2(0, 1.2) * world.px)
	var field: Array = fm.plots.filter(func(q): return q.pos.distance_to(miko.position) < 4.0 * world.px)
	await _say(fm, "bare")
	for p in field:
		fm.sow(p, "Carrot")
	await _say(fm, "sown")
	for p in field:
		fm._settle(p)
		fm._state(p).pest = true
		if fm.has_method("_changed"):
			fm.call("_changed", p)
	await _say(fm, "pests")
	fm.clear_pests(field[0])
	await _say(fm, "cleared")
	clock.hours += 25.0   # (a day without water: dry by itself, not by the hourly tending)
	fm._tended_at = clock.hours
	await _say(fm, "dried")
	clock.hours += 80.0   # (ripe by itself)
	fm._tended_at = clock.hours
	await _say(fm, "ripe")
	fm.harvest(field[0])
	await _say(fm, "harvested")
