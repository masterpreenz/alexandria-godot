extends Scenario
## Out of a fight, HP and mana come back quickly (Sera and her companion); with a monster after them, they don't. And
## the minimap shows the faces of those who can be played. Run with --window=restregen.


func _secs(s: float) -> void:
	var until := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame


func run() -> void:
	await _secs(0.5)
	var miyu: Villager = Villager.all[1]
	miyu.person["unique"] = "miyu"
	miyu.person["name"] = "Miyu"
	var trait_list: Array = miyu.person.get("traits", []).duplicate()
	trait_list.append("unique")
	miyu.person["traits"] = trait_list
	Party.active.join("miyu")
	miyu._follow_start(Villager.now())
	await _secs(1.0)
	var st := miko.stats
	var t := st.total()
	var md: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	var sl := Slime.spawn(world, md.slime, false, miko.position + Vector2(3.0, 1.0) * world.px)
	sl.hit.max_hp = 9999.0
	sl.hit.hp = 9999.0
	st.hp = float(t.maxHp) * 0.3
	st.mana = 0.0
	miyu.hit.hp = miyu.hit.max_hp * 0.3
	var until := Time.get_ticks_msec() + 6000
	while Time.get_ticks_msec() < until:
		sl.chasing = true
		await get_tree().process_frame
	print("Rest regen: 6 s with a monster after them: Sera HP ", roundi(st.hp), "/", roundi(float(t.maxHp)), " mana ", roundi(st.mana), ", Miyu HP ", roundi(miyu.hit.hp), "/", roundi(miyu.hit.max_hp), ", resting ", CharacterStats.resting())
	sl.queue_free()
	var h0 := st.hp
	var m0 := st.mana
	var y0 := miyu.hit.hp
	for s in [4, 6, 10]:
		await _secs(2.0 if s == 6 else float(s if s == 4 else 4))
		print("Rest regen: ", s, " s after: Sera HP ", roundi(h0), " -> ", roundi(st.hp), ", mana ", roundi(m0), " -> ", roundi(st.mana), ", Miyu HP ", roundi(y0), " -> ", roundi(miyu.hit.hp), ", resting ", CharacterStats.resting())
	shot("minimap")
