extends Scenario
## A 3x3 field, then one more plot placed beside it through build mode: what changes on the old plots
## over the next frames (scales, places, what shows).
## Run with --window=plotjitter.


func run() -> void:
	var fm: Farming = miko.get_node("Farming")
	if Shots.arg("winter") != "":
		clock.forced = -1
		clock.hours = float(clock.days_per_season * ((GameClock.Season.WINTER - clock.start_season + 4) % 4) + 2) * 24.0 + 12.0
		snow._last_hours = -1.0
	var bm := BuildMode.active
	var c0 := world.floors.cell_at(world.village.centre()) + Vector2i(5, 4)
	for x in 3:
		for y in 3:
			world.props.place(c0 + Vector2i(x, y), "FarmPlot")
	for i in 30:
		await get_tree().process_frame
	var snap := func() -> Array:
		var out := []
		for pl in fm.plots:
			if world.floors.cell_at(pl.pos) == c0 + Vector2i(3, 1):
				continue
			var holder: Node2D = pl.node
			var sp: Sprite2D = holder.get_child(0)
			var fl: Sprite2D = pl.flat.get_child(0)
			out.append([holder.scale, holder.position.round(), sp.scale, sp.visible, sp.get_meta("sprite", -1), fl.scale, fl.visible, fl.get_meta("sprite", -1), holder.modulate.a])
		return out
	var before: Array = snap.call()
	bm.set_open(true)
	bm.select(bm.item_for("Prop", "FarmPlot"))
	bm._place_prop(c0 + Vector2i(3, 1), 1.0)
	var seen := {}
	miko.place(world.floors.cell_centre(c0) + Vector2(-2.0, 0.5) * world.px)
	bm.set_open(false)
	for i in 40:
		await get_tree().process_frame
	var fr: Fires = miko.get_node("Fires")
	var lights_before := fr.fires.map(func(f): return f.light)
	world.props.place(c0 + Vector2i(3, 2), "FarmPlot")
	await get_tree().process_frame
	await get_tree().process_frame
	print("Plot jitter: fires' lights kept through a plot placed ", fr.fires.map(func(f): return f.light) == lights_before, " (", fr.fires.size(), " fires)")
	for i in 60:
		await get_tree().process_frame
		if i < 24 or i == 59:
			get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_f%02d.png" % i)
		var now_is: Array = snap.call()
		if now_is.size() != before.size():
			seen["count %d -> %d" % [before.size(), now_is.size()]] = i
			continue
		for j in now_is.size():
			for k in 9:
				if now_is[j][k] != before[j][k]:
					var what: String = ["holder scale", "holder place", "crop scale", "crop shown", "crop art", "soil scale", "soil shown", "soil art", "alpha"][k]
					if not seen.has(what):
						seen[what] = "frame %d: %s -> %s" % [i, before[j][k], now_is[j][k]]
	print("Plot jitter: plots ", fm.plots.size(), "; changed on the old plots: ", seen)
