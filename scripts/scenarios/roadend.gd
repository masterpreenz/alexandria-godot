extends Scenario
## The road where the story starts, at the map's south-east edge. Run with --window=roadend --slot=new --nostory.


func run() -> void:
	clock.hours = float(clock.day()) * 24.0 + 12.0
	miko.place(world.floors.cell_centre(Vector2i(0, -138)))
	for i in 30:
		await get_tree().process_frame
	var spot := world.floors.cell_centre(Vector2i(0, -141))
	for n in world.things.find_children("*", "Sprite2D", true, false):
		var sp := n as Sprite2D
		if sp.is_visible_in_tree() and sp.global_position.distance_to(spot) < 4.0 * world.px:
			print("near the road end: ", sp.get_path(), " cell ", world.floors.cell_at(sp.global_position), " frame ", sp.get_meta("frame", "?"))
	print("Road end: Sera at ", world.floors.cell_at(miko.position))
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_end.png")
