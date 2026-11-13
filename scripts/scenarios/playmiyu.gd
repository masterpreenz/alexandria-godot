extends Scenario
## Playing Miyu: in the village, a talk with Miyu offers "Play as Miyu"; picked, the body that's played is hers (her
## name on the card, her art, her stats and spells on the hotbar) and Sera's a companion where she stood, following and
## with her own stats and spells. Then back to Sera by a talk with her, and a save and load (in memory: tests don't
## save) while Miyu's played. Run with --window=playmiyu.


func run() -> void:
	for i in 30:
		await get_tree().process_frame
	# (the bundled save has no Miyu: someone stands in for her, in her look)
	var miyu: Villager = null
	for v in Villager.all:
		if is_instance_valid(v) and str(v.person.get("unique", "")) == "miyu":
			miyu = v
	if miyu == null:
		miyu = Villager.all[1]
		miyu.person["unique"] = "miyu"
		miyu.person["name"] = "Miyu"
		miyu.person["look"] = 2
		var trait_list: Array = miyu.person.get("traits", []).duplicate()
		trait_list.append("unique")
		miyu.person["traits"] = trait_list
		var lk: Dictionary = people._look_for(miyu.person)
		miyu.look = lk
		miyu.s = lk.settings
		miyu.name = "Miyu"
	Party.active.join("miyu")
	miyu._follow_start(Villager.now())
	miyu.person["level"] = 4
	var mst := Companions.stats_for(miyu.person)
	for sp in ["IceSpikes", "IceBlast", "WaterHeal", "IceBarrier"]:
		mst.learned[sp] = "Water Spell Book"
	mst.changed.emit()
	# Both in the village, side by side.
	var centre := world.village.centre()
	miko.place(centre + Vector2(1.5, 1.0) * world.px)
	miyu.position = centre + Vector2(2.4, 1.3) * world.px
	miyu.reset_physics_interpolation()
	for i in 40:
		await get_tree().process_frame
	var pl := Playable.active
	print("Play miyu: Miyu as a companion before: level ", mst.level, ", hp ", miyu.hit.hp, "/", miyu.hit.max_hp, ", mana ", snappedf(mst.mana, 1), "/", mst.stat("maxMana"), ", talent points ", mst.talent_points, ", known ", mst.known_spells())
	var sera_before := _sera_line("as Sera")
	print("Play miyu: before: playing ", pl.who, " (", Playable.name_now(), "), why not Miyu '", pl.why_not(miyu), "', story beat ", Story.active.beat if Story.active != null else -9)
	print(sera_before)
	var nd: Needs = miko.get_node("Needs")
	print("Play miyu: Sera's needs: hunger %.0f thirst %.0f energy %.0f pouch %.0f; Miyu's: hunger %.0f thirst %.0f energy %.0f" % [nd.hunger, nd.thirst, nd.energy, nd.pouch, float(miyu.person.get("hunger", -1)), float(miyu.person.get("thirst", -1)), float(miyu.person.get("energy", -1))])
	var hotbar: Hotbar = g.get_node("Hud/Hotbar")
	print("Play miyu: Sera's hotbar ", hotbar.slots.filter(func(x): return str(x) != ""))
	shot("before")
	# The talk: Play as Miyu.
	miko.place(miyu.position + Vector2(-0.8, 0.3) * world.px)
	for i in 5:
		await get_tree().process_frame
	Talk.active.open(miyu)
	for i in 10:
		await get_tree().process_frame
	print("Play miyu: talk offers ", _offers())
	Talk.active._finish_typing()
	shot("talk")
	var sera_at := miko.position
	var miyu_at := miyu.position
	Talk.active._play_as()
	for i in 30:
		await get_tree().process_frame
	_report("as Miyu")
	print("Play miyu: Miko (now Miyu) at ", miko.position, " (Miyu stood at ", miyu_at, "); Sera's body at ", _sera_body().position if _sera_body() != null else Vector2.INF, " (Sera stood at ", sera_at, ")")
	print("Play miyu: Miyu's hotbar ", hotbar.slots.filter(func(x): return str(x) != ""))
	shot("miyu")
	# Moving the played body: Sera follows.
	var sb := _sera_body()
	miko.place(miko.position + Vector2(5.0, 2.0) * world.px)
	print("Play miyu: moved; Sera ", snappedf(sb.position.distance_to(miko.position) / world.px, 0.01), " units away, state ", Villager.State.keys()[sb.state])
	for i in 240:
		await get_tree().process_frame
	print("Play miyu: after 4 s Sera ", snappedf(sb.position.distance_to(miko.position) / world.px, 0.01), " units away, state ", Villager.State.keys()[sb.state], ", in the party ", Party.active.has_member(sb.person))
	shot("follow")
	# A swing and a cast pose as Miyu (her frames).
	print("Play miyu: Miyu's swing frames ", miko.data.frames.get("attackDownLeft", []), ", cast ", miko.data.frames.get("castDownLeft", []), ", run ", miko.data.frames.get("runDownLeft", []), ", sleep frames ", (miko.anim("sleepDown", []) as Array).size(), ", mine ", (miko.anim("mineDown", []) as Array).size())
	miko.hold_cast(Vector2(-1, 1))
	for i in 3:
		await get_tree().process_frame
	shot("cast")
	miko.end_cast()
	# Save and load, in memory: Sera's stats saved as the player's, Miyu's apart, and put back.
	var saving: SaveGame = g.get_node("SaveGame")
	var sections := saving.capture()
	var lead: Dictionary = JSON.parse_string(sections.get("player.stats", "{}"))
	var playing: Dictionary = JSON.parse_string(sections.get("player.playing", "{}"))
	print("Play miyu: saved player.stats level ", lead.get("level"), " learned ", lead.get("learned", {}).keys(), "; player.playing who ", playing.get("who"), ", played ", playing.get("played", {}).get("name"), ", party ", sections.get("world.party", ""))
	var miyu_json := miko.stats.to_json()
	var miyu_known := miko.stats.known_spells()
	# (as the game loads: the player's stats are Sera's, then who's played is put on)
	pl._put_stats(Companions.combat().get("character", {}).duplicate(true), str(sections["player.stats"]), true)
	print("Play miyu: loaded as Sera first: level ", miko.stats.level, ", known ", miko.stats.known_spells())
	pl.who = Playable.LEAD
	pl.from_json(str(sections["player.playing"]))
	var back: Dictionary = JSON.parse_string(miko.stats.to_json())
	var was: Dictionary = JSON.parse_string(miyu_json)
	print("Play miyu: reloaded: playing ", pl.who, " (", Playable.name_now(), "), level ", back.level, " vs ", was.level, ", hp ", back.hp, " vs ", was.hp, ", known ", miko.stats.known_spells(), " vs ", miyu_known, ", same talents ", str(back.talentIds) == str(was.talentIds))
	for i in 10:
		await get_tree().process_frame
	# Back to Sera: a talk with her.
	sb = _sera_body()
	sb.position = miko.position + Vector2(0.8, 0.3) * world.px
	sb.reset_physics_interpolation()
	sb._stand(Villager.now(), 2.0)
	for i in 5:
		await get_tree().process_frame
	print("Play miyu: why not Sera '", pl.why_not(sb), "'")
	Talk.active.open(sb)
	for i in 10:
		await get_tree().process_frame
	print("Play miyu: talk offers ", _offers())
	Talk.active._play_as()
	for i in 30:
		await get_tree().process_frame
	_report("back as Sera")
	var mb: Villager = null
	for v in Villager.all:
		if is_instance_valid(v) and str(v.person.get("unique", "")) == "miyu":
			mb = v
	print("Play miyu: Miyu's body ", mb != null, ", in the party ", mb != null and Party.active.has_member(mb.person), ", level ", mb.person.get("level") if mb != null else -1, ", hp ", mb.hit.hp if mb != null else -1.0, "/", mb.hit.max_hp if mb != null else -1.0, ", knows ", Companions.stats_for(mb.person).known_spells() if mb != null else [])
	print("Play miyu: Sera's body gone ", _sera_body() == null, ", Sera's hotbar ", hotbar.slots.filter(func(x): return str(x) != ""))
	print(_sera_line("as Sera again"))
	shot("back")


func _offers() -> Array:
	var out := []
	for b in Talk.active._choices.get_children():
		if b is Button:
			out.append((b as Button).text)
	return out


func _sera_body() -> Villager:
	for v in Villager.all:
		if is_instance_valid(v) and str(v.person.get("unique", "")) == "sera":
			return v
	return null


func _sera_line(what: String) -> String:
	var st := miko.stats
	return "Play miyu: %s: level %d, hp %.0f/%.0f, mana %.0f, talent points %d, known %s, worn %s, bag worn %s" % [what, st.level, st.hp, st.stat("maxHp"), st.mana, st.talent_points, str(st.known_spells()), str(st.equipped), str(miko.bag.worn)]


func _report(what: String) -> void:
	var st := miko.stats
	var needs: Needs = miko.get_node_or_null("Needs")
	print("Play miyu: %s: playing %s, card name '%s', level %d, hp %.0f/%.0f, mana %.0f/%.0f, talent points %d, known %s, idle frame %s, hunger %.0f thirst %.0f energy %.0f" % [what, Playable.active.who, Playable.name_now(), st.level, st.hp, st.stat("maxHp"), st.mana, st.stat("maxMana"), st.talent_points, str(st.known_spells()), str(miko.data.frames.idleDownLeft), needs.hunger, needs.thirst, needs.energy])
	var sb := _sera_body()
	if sb != null:
		var sst := Companions.stats_for(sb.person)
		print("Play miyu: Sera as a companion: at ", sb.position, ", state ", Villager.State.keys()[sb.state], ", in the party ", Party.active.has_member(sb.person), ", members ", Party.active.members, ", level ", sst.level, ", hp ", sb.hit.hp, "/", sb.hit.max_hp, ", mana ", snappedf(sst.mana, 1), ", known ", sst.known_spells(), ", magic ", sb.get_node_or_null("Magic") != null, ", art idle ", sb.s.idleDown, ", hunger ", sb.person.get("hunger"))
