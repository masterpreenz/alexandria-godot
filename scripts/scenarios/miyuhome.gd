extends Scenario
## Miyu at home in the village (not in the party) when a slime comes in: she fights it as she would with the party,
## by her tactics, casting her spells (Ice Shard) and keeping her stance. Run with --window=miyuhome.


func _secs(s: float) -> void:
	var until := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame


func run() -> void:
	await _secs(1.0)
	var miyu: Villager = Villager.all[1]
	miyu.person["unique"] = "miyu"
	miyu.person["name"] = "Miyu"
	miyu.person["look"] = 5
	var tl: Array = miyu.person.get("traits", []).duplicate()
	tl.append("unique")
	miyu.person["traits"] = tl
	var lk: Dictionary = people._look_for(miyu.person)
	miyu.look = lk
	miyu.s = lk.settings
	miyu.person["level"] = 8
	miyu.person["hunger"] = 100.0
	miyu.person["thirst"] = 100.0
	miyu.person["lastMeal"] = 999999
	var st := Companions.stats_for(miyu.person)
	Companions.teach(st, Companions.data().books[0])
	st.mana = st.stat("maxMana")
	var c := world.village.centre()
	miyu.position = c + Vector2(1.5, 1.0) * world.px
	miyu.reset_physics_interpolation()
	miyu._stand(Villager.now(), 0.2)
	miko.place(c + Vector2(-4.0, 3.0) * world.px)
	await _secs(1.0)
	var magic: CompanionMagic = miyu.get_node_or_null("Magic")
	print("Miyu at home: in the party ", miyu._in_party(), ", fights as a companion ", magic != null, ", knows ", st.known_spells(), ", mana ", roundi(st.mana))
	var sl := Slime.spawn(world, world._load_json("res://data/monsters.json").slime, false, miyu.position + Vector2(3.0, -1.0) * world.px, 1.0)
	var states := {}
	for i in 20:
		await _secs(0.5)
		var k: String = Villager.State.keys()[miyu.state]
		states[k] = int(states.get(k, 0)) + 1
		if i == 6:
			shot("fight")
		if not is_instance_valid(sl) or not sl.hit.alive():
			break
	print("Miyu at home: states ", states, ", casts ", magic.casts.map(func(x): return x[0]) if magic != null else [], ", done ", magic.done if magic != null else {}, ", slime down ", not is_instance_valid(sl) or not sl.hit.alive())
