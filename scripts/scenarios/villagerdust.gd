extends Scenario
## A villager sent walking: the dust at their feet, beside Miko's as she walks.
## Run with --window=villagerdust.


func run() -> void:
	clock.hours = float(clock.day() - 1) * 24.0 + 10.0
	while Villager.all.is_empty():
		await get_tree().process_frame
	var v: Villager = Villager.all[0]
	v.position = miko.position + Vector2(1.5, 0.8) * world.px
	var most := 0
	var dust: DustTrail = null
	for d in world.things.get_children():
		if d is DustTrail and d.target == v:
			dust = d
	v.state = Villager.State.WALK
	v._set_goal(v.position + Vector2(5.0, 1.0) * world.px)
	camera.zoom *= 1.6
	for i in 150:
		await get_tree().process_frame
		if dust != null:
			most = maxi(most, dust.puffs.size())
		if i == 60:
			get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_walk.png")
	print("Villager dust: has a trail ", dust != null, ", most puffs at once ", most, ", walked ", snappedf(v.position.distance_to(miko.position) / world.px, 0.1), " units off")
