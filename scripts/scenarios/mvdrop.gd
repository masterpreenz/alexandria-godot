extends Scenario
## Ten mutated villagers killed: how many dropped a crystal.
## Run with --window=mvdrop.


func run() -> void:
	var md: Dictionary = world._load_json("res://data/monsters.json")
	var drops := 0
	for k in 10:
		var mv := MutatedVillager.spawn(world, md.mutatedVillager, miko.position + Vector2(2.0 + k * 0.3, 1.0) * world.px)
		await get_tree().process_frame
		var had := Pickup.all.size()
		mv.hit.hurt(9999.0, true)
		await get_tree().process_frame
		if Pickup.all.any(func(pk): return pk.resource == "Crystal") and Pickup.all.size() > had: drops += 1
		for pk in Pickup.all.duplicate(): pk.queue_free()
		Pickup.all.clear()
	print("Drops: ", drops, " of 10 dropped a crystal")
