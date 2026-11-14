extends Scenario
## A companion keeps up: Sera walks, then runs, a long way; how far behind Miyu falls, against before (she walked at
## her own pace and fell further and further back). Run with --window=keepup.


func _secs(s: float) -> void:
	var until := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame


func _shift(down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = KEY_SHIFT
	e.physical_keycode = KEY_SHIFT
	e.pressed = down
	Input.parse_input_event(e)


func run() -> void:
	await _secs(0.5)
	var miyu: Villager = Villager.all[1]
	miyu.person["unique"] = "miyu"
	miyu.person["name"] = "Miyu"
	var tl: Array = miyu.person.get("traits", []).duplicate()
	tl.append("unique")
	miyu.person["traits"] = tl
	miyu.person["hunger"] = 100.0
	miyu.person["thirst"] = 100.0
	miyu.person["lastMeal"] = 999999   # (not off to a meal mid-test)
	Party.active.join("miyu")
	miyu.position = miko.position + Vector2(-1.0, 0.5) * world.px
	miyu._follow_start(Villager.now())
	await _secs(1.0)
	print("Keep up: Miyu in the party ", miyu._in_party(), ", ", Villager.State.keys()[miyu.state])
	for run_too in [false, true]:
		_shift(run_too)
		Input.action_press("ui_right")
		var most := 0.0
		var sum := 0.0
		var n := 0
		var sp := 0.0
		var others := {}
		var until := Time.get_ticks_msec() + 6000
		while Time.get_ticks_msec() < until:
			await get_tree().process_frame
			var d := miyu.position.distance_to(miko.position) / world.px
			most = maxf(most, d)
			sum += d
			sp += miyu.velocity.length() / world.px
			if miyu.state != Villager.State.FOLLOW:
				others[Villager.State.keys()[miyu.state]] = int(others.get(Villager.State.keys()[miyu.state], 0)) + 1
			n += 1
		print("Keep up (", "running" if run_too else "walking", "): Sera at ", roundi(miko.velocity.length() / world.px * 10.0) / 10.0, " units/s; Miyu behind on average ", snappedf(sum / n, 0.1), " units, at most ", snappedf(most, 0.1), ", her pace ", snappedf(sp / n, 0.1), " units/s, now ", Villager.State.keys()[miyu.state], ", frames not following ", others)
		if run_too:
			shot("running")
		Input.action_release("ui_right")
		_shift(false)
		await _secs(1.0)
	# Meat lying near her: picked up into her own bag as she follows.
	var bag := Companions.bag_of(miyu.person)
	var had := bag.count("Food")
	Pickup.launch_icon(world, "Food", 2, miyu.position + Vector2(1.5, 0.5) * world.px, 1.0)
	await _secs(4.0)
	print("Keep up: meat in Miyu's bag ", had, " -> ", bag.count("Food"))
	# No mist crystal on her: she asks for one, and wears it once given.
	var req := Requests.active
	var key := req.offered_by(miyu)
	print("Mist crystal: she asks ", key != "", " (", miyu._rumor_emote(), "); wearing ", Companions.stats_for(miyu.person).worn_in("Necklace"))
	if key != "":
		print("Mist crystal: she says \"", req.said(key), "\"")
		req.accept(key)
		miko.bag.items[miko.bag.free_slot()] = "CrystalNecklace"
		print("Mist crystal: given: \"", req.give(req.open_for(miyu), miyu), "\"; now wearing ", Companions.stats_for(miyu.person).worn_in("Necklace"), ", state ", req.asks[key].state)

