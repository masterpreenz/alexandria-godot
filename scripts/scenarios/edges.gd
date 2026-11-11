extends Scenario
## The map's four edges and where the river leaves it, zoomed out: what shows past them.
## Run with --window=edges.


func run() -> void:
	camera.zoom *= float(Shots.arg("zoom", "0.35"))
	var spots := {"sw": Vector2(-138, 0), "se": Vector2(0, -138), "nw": Vector2(0, 138), "south": Vector2(-138, -138), "west": Vector2(-138, 138), "east": Vector2(138, -138)}
	if Shots.arg("at") != "":
		var xy := Shots.arg("at").split(",")
		spots = {"at": Vector2(float(xy[0]), float(xy[1]))}
	for k in spots:
		miko.place(world.floors.corner(spots[k]))
		for i in 40:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_" + k + ".png")
