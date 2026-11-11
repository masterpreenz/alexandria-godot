extends Scenario
## The "eat" scenario.
## Run with --window=eat.


func run() -> void:
	if Shots.arg("hour") != "": clock.hours = float(Shots.arg("hour"))
	if Shots.arg("say") != "":
		miko.stats.xp = floori(miko.stats.xp_to_next() * 0.6)
		FloatingText.spawn(world, Shots.arg("say"), miko.position + Vector2(0, -1.6 * world.px), Color(1, 0.6, 0.5))
	while Villager.all.is_empty():
		await get_tree().process_frame
	var v: Villager = Villager.all[0]
	v.meal = "Meal"
	v.state = Villager.State.EATING
	v.state_until = Villager.now() + 60.0
	miko.place(v.position + Vector2(1.5, 0.5) * world.px)
	for i in 20:
		v.state = Villager.State.EATING
		await get_tree().process_frame
