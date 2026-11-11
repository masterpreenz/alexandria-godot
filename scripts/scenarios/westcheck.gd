extends Scenario
## The next village as a game already going gets it: there, its fire out, and noted as built (not built twice).
## Run with --window=westcheck.


func run() -> void:
	var area := Wildlands.WEST_VILLAGE
	var fires: Fires = miko.get_node("Fires")
	for i in 30:
		await get_tree().process_frame
	var lit := 0
	var there := 0
	for f in fires.fires:
		if area.has_point(world.floors.cell_at(f.pos)):
			there += 1
			lit += 1 if fires.lit(f) else 0
	print("West check: stamped ", world.stamped_villages, "; walls in it ", world.walls.walls.keys().filter(func(k): return area.has_point(Vector2i(k.x, k.y))).size(), "; fires there ", there, ", lit ", lit, "; trees standing on its floors ", Gatherable.all.filter(func(tree): return area.has_point(world.floors.cell_at(tree.foot)) and world.floors.laid.has(world.floors.cell_at(tree.foot))).size())
