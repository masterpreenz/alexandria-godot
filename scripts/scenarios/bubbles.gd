extends Scenario
## Three villagers by Miko, saying, thinking and shouting; Miko starving.
## Run with --window=bubbles.


func run() -> void:
	while Villager.all.size() < 3:
		await get_tree().process_frame
	var keys := ["bark.pests", "bark.hungry", "bark.raid"]
	for k in 3:
		var v: Villager = Villager.all[k]
		v.position = miko.position + Vector2(-2.6 + k * 2.6, -0.4) * world.px
		v.velocity = Vector2.ZERO
		v.bark(keys[k], {"miko": "Miko", "side": "east"}, true)
	var nd: Needs = miko.get_node("Needs")
	nd.hunger = 0.0
	miko.place(miko.position + Vector2(0, 1.6) * world.px)
	for i in 12:
		await get_tree().process_frame
	for k in 3:
		var v: Villager = Villager.all[k]
		if k == 1:
			camera.position = v.position + Vector2(0, -1.0 * world.px)
			camera.reset_smoothing()
			set_meta("warming", true)
			await get_tree().process_frame
			await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_villagers.png")
			remove_meta("warming")
		print("Bubble ", k, ": ", v._bark != null, " visible ", v._bark.visible if v._bark else false, " text '", v._bark.text if v._bark else "", "' at ", v._bark.global_position if v._bark else Vector2.ZERO, " villager ", v.global_position, " in tree ", v.is_inside_tree(), " vis ", v.is_visible_in_tree())
