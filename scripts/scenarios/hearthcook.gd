extends Scenario
## Cooks keep to the fires outside: a fireplace lit in a house beside the bonfire, raw food in storage; which fires
## the cooks go to over a minute (never the fireplace behind its wall). Run with --window=hearthcook.


func run() -> void:
	var fr: Fires = miko.get_node("Fires")
	var room: Dictionary = world.roofs.roofs[0].cells
	var spot := Vector2i.ZERO
	for c in room:
		if world.props.peek_where(c, func(_n): return true) == "" and not BuildMode.active._use_cells().has(c):
			spot = c
	world.props.place(spot, "Fireplace")
	world.village.put_in_stash("Wood", 30)
	world.village.put_in_stash("Meat", 30)
	world.village.put_in_stash("Potato", 30)
	for i in 10:
		await get_tree().process_frame
	var hearth: Dictionary = fr.fires.filter(func(f): return bool(f.s.get("hearth", false)))[0]
	fr.light(hearth)
	var others := fr.fires.filter(func(f): return not bool(f.s.get("hearth", false)) and not bool(f.s.torch)).size()
	print("Hearth cook: fireplace lit ", fr.lit(hearth), ", other cooking fires ", others)
	var at_hearth := 0
	var picks := {}
	var until := Time.get_ticks_msec() + 60000
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame
		for v in Villager.all:
			if not is_instance_valid(v) or v.stove.is_empty():
				continue
			var name := str(v.stove.type)
			picks[name] = int(picks.get(name, 0)) + 1
			if v.stove.key == hearth.key:
				at_hearth += 1
	print("Hearth cook: frames a cook had the fireplace ", at_hearth, ", fires cooked at (frames) ", picks)
	print("Hearth cook: Sera beside the fireplace finds a fire to cook at: ", not fr.nearest(hearth.pos, 2.0 * world.px, true, true).is_empty())
	shot("end")
