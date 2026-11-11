extends Scenario
## A barricade struck: mid-flinch, its tint and shake; then back as it was.
## Run with --window=wallhit.


func run() -> void:
	var c0 := world.floors.cell_at(miko.position) + Vector2i(1, -2)
	var eh := WallMap.Edge.new(c0, false)
	world.walls.place(eh, "Barricade", true)
	camera.zoom *= 1.6
	for i in 10:
		await get_tree().process_frame
	world.walls.damage(eh.key(), 20.0)
	for i in 6:
		await get_tree().process_frame
	var art: Node2D = world.walls.nodes_of(eh)[0].get_child(0)
	print("Wall hit: tint ", art.self_modulate, ", shaken ", snappedf(art.position.x - float(art.get_meta("rest_x")), 0.1))
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_hit.png")
	for i in 80:
		await get_tree().process_frame
	print("Wall hit after: tint ", art.self_modulate, ", shaken ", snappedf(art.position.x - float(art.get_meta("rest_x")), 0.1))
