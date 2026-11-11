extends Scenario
## The "build" scenario.
## Run with --window=build.


func run() -> void:
	var bm := BuildMode.active
	bm.set_open(true)
	if Shots.arg("pick") != "":
		for it in bm.items:
			if it.name == Shots.arg("pick"):
				bm.select(it)
				(g.get_node("Hud/BuildBar") as BuildBar).category = it.category
	if Shots.arg("tool") != "": bm.set_tool(Shots.arg("tool"))
	if Shots.arg("tool") == "Inspect" and world.roofs != null and not world.roofs.rooms().is_empty():
		bm.picked_room = world.roofs.rooms()[0]
	if Shots.arg("hide") != "": bm.toggle_hide_buildings()
	if Shots.arg("blueprint") != "": bm.blueprint = true
	get_viewport().warp_mouse(get_viewport().get_visible_rect().size * Vector2(float(Shots.arg("mx", "0.55")), float(Shots.arg("my", "0.45"))))
