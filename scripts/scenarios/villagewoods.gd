extends Scenario
## Woods round the home village (wood near at hand), and clear skies while the story's on.
## Run with --window=villagewoods --slot=new.


func run() -> void:
	for i in 30:
		await get_tree().process_frame
	var c := world.village.centre()
	var near := Gatherable.all.filter(func(gt): return is_instance_valid(gt) and gt.position.distance_to(c) < 45.0 * world.px)
	print("Village woods: trees ", near.filter(func(gt): return gt.axe).size(), ", rocks ", near.filter(func(gt): return not gt.axe).size(), " within 45 of the village; weather ", GameClock.Weather.keys()[clock.weather()])
	miko.place(c + Vector2(-26, 8) * world.px)
	for i in 30:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_woods.png")
