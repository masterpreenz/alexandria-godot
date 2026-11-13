extends Scenario
## A mutated wolf between leaps: it never backs away facing Sera; it runs round her, facing the way it runs, and comes
## at her again from another side. Logs each frame whether it's moving away from her while facing her (backwards).
## Run with --window=wolfflank.


func run() -> void:
	for i in 30:
		await get_tree().process_frame
	var md: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	clock.hours = float(clock.day() - 1) * 24.0 + 22.0
	var b := world.village.banner_cell()
	var spot := world.floors.cell_centre(b + Vector2i(26, 26))
	miko.place(spot)
	miko.stats.hp = 9999.0
	for i in 10:
		await get_tree().process_frame
	var wolf := MutatedWolf.spawn(world, md.mutatedWolf, spot + Vector2(-1.5, 0.6) * world.px)
	var backwards := 0
	var moving := 0
	var leaps := 0
	var angles := []
	var last_state := -1
	for i in 900:
		await get_tree().process_frame
		miko.stats.hp = 9999.0
		if wolf.state == MutatedWolf.State.LEAP and last_state != MutatedWolf.State.LEAP:
			leaps += 1
			var a := (wolf.position - miko.position)
			angles.append(roundi(rad_to_deg(atan2(a.y * 2.0, a.x))))
		last_state = wolf.state
		if wolf.state == MutatedWolf.State.CHASE and wolf.velocity.length() > 0.3 * world.px:
			moving += 1
			# (facing: left/right by flip; moving the other way along x is walking backwards)
			var faces_right := wolf.flip
			if absf(wolf.velocity.x) > 0.2 * world.px and (wolf.velocity.x > 0.0) != faces_right:
				backwards += 1
		if i == 300:
			shot("flank")
	print("Wolf flank: leaps ", leaps, " from angles ", angles, ", frames moving ", moving, ", of them backwards ", backwards)
