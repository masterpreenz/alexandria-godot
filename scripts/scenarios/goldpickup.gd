extends Scenario
## Gold lying in the village is brought in: coins dropped by a slime, Sera far off; a hauler carries them to storage.
## And gold has no limit: more than a chest used to hold goes in. Run with --window=goldpickup.


func _secs(s: float) -> void:
	var until := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame


func run() -> void:
	await _secs(1.0)
	clock.hours = floorf(clock.hours / 24.0) * 24.0 + 10.0
	var v := world.village
	var at := v.centre() + Vector2(2.0, 1.0) * world.px
	miko.place(v.centre() + Vector2(40.0, 40.0) * world.px)
	var gold0 := v.stored("Gold")
	Pickup.drop(world, "Gold", 7, at)
	print("Gold: dropped 7 in the village; stored ", gold0, ", gold cap of the chests ", v.stash_cap("Gold"))
	var taken_by := ""
	var until := Time.get_ticks_msec() + 60000
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame
		if taken_by == "":
			for vv in Villager.all:
				if is_instance_valid(vv) and vv.carrying > 0 and vv.carry_kind == "Gold":
					taken_by = str(vv.person.name)
		if v.stored("Gold") >= gold0 + 7:
			break
	print("Gold: carried by ", taken_by if taken_by != "" else "nobody", "; stored ", gold0, " -> ", v.stored("Gold"))
	v.stash["Gold"] = 999
	print("Gold: room in storage for 5000 more ", v.stash_cap("Gold") - v.stored("Gold") > 5000)
	var purse0 := miko.bag.count("Gold")
	miko.bag.add("Gold", 5000)
	print("Gold: Sera's purse ", purse0, " -> ", miko.bag.count("Gold"))
