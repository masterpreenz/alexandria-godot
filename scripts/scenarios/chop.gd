extends Scenario
## The nearest tree struck until it falls: it shakes, topples and lands (its processing woken for it).
## Run with --window=chop.


func run() -> void:
	var tree: Gatherable = null
	var best := INF
	for c in Gatherable.all:
		if c.axe and not c.depleted() and c.foot.distance_to(miko.position) < best:
			best = c.foot.distance_to(miko.position)
			tree = c
	for i in 5:
		await get_tree().process_frame
	print("Chop: idle trees processing ", Gatherable.all.filter(func(c): return c.is_processing()).size(), " of ", Gatherable.all.size())
	var tilt := 0.0
	while tree.left > 0:
		tree.strike()
		print("  struck: left ", tree.left, " processing ", tree.is_processing(), " shaking ", tree._shake > 0.0)
		for i in 12:
			await get_tree().process_frame
	for i in 90:
		await get_tree().process_frame
		tilt = maxf(tilt, absf(tree.art.rotation))
	print("Chop: fell (most tilt ", snappedf(tilt, 0.01), "), regrow at ", tree._regrow_at > 0.0, ", processing ", tree.is_processing())
