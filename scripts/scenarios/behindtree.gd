extends Scenario
## Things that hide a character are trees too: a slime just behind a tree (by the road where the story starts) gets
## its outline over the tree; Sera behind one, the tree fades. Run with --window=behindtree --slot=new --nostory.


func run() -> void:
	clock.hours = float(clock.day()) * 24.0 + 12.0
	# The nearest standing tree to where the story starts.
	var start := world.floors.cell_centre(Vector2i(8, -112))
	var tree: Gatherable = null
	for gt in Gatherable.all:
		if gt.axe and (tree == null or gt.position.distance_to(start) < tree.position.distance_to(start)):
			tree = gt
	miko.place(tree.position + Vector2(2.5, 1.0) * world.px)
	var sl := Slime.spawn(world, world._load_json("res://data/monsters.json").slime, false, tree.position + Vector2(0, -0.6) * world.px, 1.0)
	sl.home = sl.position
	for i in 40:
		sl.position = tree.position + Vector2(0, -0.6) * world.px
		await get_tree().process_frame
	print("Behind a tree: slime hidden ", sl.outline.covered, ", its outline showing ", snappedf(sl.outline.shown, 0.01))
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_slime.png")
	sl.queue_free()
	miko.place(tree.position + Vector2(0, -0.5) * world.px)
	for i in 40:
		await get_tree().process_frame
	var mo: OccludedOutline = miko.get_node_or_null("OccludedOutline")
	print("Sera behind it: hidden ", mo.covered if mo != null else "?", ", the tree faded to ", snappedf(tree.art.modulate.a, 0.01))
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_sera.png")
