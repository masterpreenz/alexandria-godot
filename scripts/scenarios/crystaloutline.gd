extends Scenario
## A cleansing crystal set just behind a big tree: outlined over the tree once it's mostly hidden, as Sera is.
## Run with --window=crystaloutline.


func run() -> void:
	for i in 20:
		await get_tree().process_frame
	var c := world.village.centre()
	var tree: Gatherable = null
	var best := INF
	for g in Gatherable.all:
		if g.axe and not g.depleted() and g.foot.distance_to(c) > 12.0 * world.px and g.foot.distance_to(c) < best:
			best = g.foot.distance_to(c)
			tree = g
	var tc := world.floors.cell_at(tree.foot)
	var spot := tc + Vector2i(-1, -1)
	for o in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(-2, -1), Vector2i(-1, -2)]:
		if world.props.get_prop(tc + o, 1) == "":
			spot = tc + o
			break
	world.props.place(spot, "CleansingCrystal")
	miko.place(tree.foot + Vector2(1.5, 2.5) * world.px)
	for i in 60:
		await get_tree().process_frame
	var holder: Node2D = world.props.node_at(spot, 1)
	var o: OccludedOutline = holder.get_node_or_null("OccludedOutline") if holder != null else null
	print("Crystal outline: tree at ", tc, ", crystal at ", spot, ", outline ", o != null, ", hidden ", o.covered if o != null else false, ", showing ", o.outline.visible if o != null else false)
	shot("behind")
