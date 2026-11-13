extends Scenario
## A mutated wolf running by day: dust kicked up at its feet. Run with --window=wolfdust.


func run() -> void:
	for i in 30:
		await get_tree().process_frame
	var md: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	clock.hours = float(clock.day() - 1) * 24.0 + 12.0
	var b := world.village.banner_cell()
	var spot := world.floors.cell_centre(b + Vector2i(26, 26))
	miko.place(spot)
	for i in 10:
		await get_tree().process_frame
	var wolf := MutatedWolf.spawn(world, md.mutatedWolf, spot + Vector2(-9.0, 3.0) * world.px)
	await get_tree().process_frame
	wolf.state = MutatedWolf.State.WALK
	wolf.target = spot + Vector2(3.0, -1.0) * world.px
	wolf.state_until = MutatedWolf.now() + 10.0
	var dust: DustTrail = null
	for n in world.things.get_children():
		if n is DustTrail and n.target == wolf:
			dust = n
	var most := 0
	var shot_taken := false
	for i in 400:
		await get_tree().process_frame
		if dust != null:
			most = maxi(most, dust.puffs.size())
			if dust.puffs.size() >= 8 and not shot_taken and wolf.state == MutatedWolf.State.CHASE:
				shot_taken = true
				shot("run")
	print("Wolf dust: trail ", dust != null, ", most puffs at once ", most)
