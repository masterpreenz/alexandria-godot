extends Scenario
## In the mist with a mutated villager 4 units off: it comes after her and hits her; back home, it gives up.
## Run with --window=chase.


func run() -> void:
	var md: Dictionary = world._load_json("res://data/monsters.json")
	var home_at := miko.position
	# Somewhere in the mist with dry ground all round (no river between them).
	for k in 400:
		var spot := home_at + Vector2.from_angle(randf() * TAU) * randf_range(14.0, 30.0) * world.px
		if world.mist.tier_at(spot) != Mist.Tier.CLEAR and Wilds.dry(world, spot, 5.0):
			miko.place(spot)
			break
	var mv := MutatedVillager.spawn(world, md.mutatedVillager, miko.position + Vector2(4.0, 0.0) * world.px)
	var hp0: float = miko.stats.hp
	var track := []
	var slam_shot := false
	for i in int(Shots.arg("chaseframes", "720")):
		await get_tree().process_frame
		if not slam_shot and mv.state == MutatedVillager.State.ATTACK and mv._hit_done:
			slam_shot = true
			get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_slam.png")
		if i % 60 == 0:
			track.append([snappedf(mv.position.distance_to(miko.position) / world.px, 0.1), MutatedVillager.State.keys()[mv.state]])
	print("Chase: distance/state each second ", track, ", her HP ", hp0, " -> ", miko.stats.hp)
	miko.place(home_at)
	for i in 30:
		await get_tree().process_frame
	print("Chase: after she's back home: ", MutatedVillager.State.keys()[mv.state])
