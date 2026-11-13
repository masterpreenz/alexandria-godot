extends Scenario
## A companion's tactics: Miyu (or a villager standing in for her) with her ice spells joins; the party window and her
## Tactics window (pictures: the window, a rule being dragged, the stance changed); then fights with slimes and a
## mutated wolf under each preset, what she did printed (casts by spell, how far she kept from the monsters, steps
## taken, potions, dodges); out of a marked strip with Dodge on (the spell dropped) and staying in it casting with it
## off; a rule moved to the top changing what she does; her tactics saved and loaded, and the defaults an old save
## gets. Run with --window=tactics. (TAC_DEBUG=1 prints her state each second of the preset fights and stops there;
## TAC_COST=1 only measures what her thinking costs.)

var md: Dictionary
var miyu: Villager
var magic: CompanionMagic
var st: CharacterStats
var foes: Array = []


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func run() -> void:
	await _frames(30)
	md = world._load_json("res://data/monsters.json")
	clock.forced = GameClock.Weather.CLEAR
	clock.hours = float(clock.day() - 1) * 24.0 + 11.0
	var ch := Chronicle.active

	for v in Villager.all:
		if is_instance_valid(v) and str(v.person.get("unique", "")) == "miyu":
			miyu = v
	if miyu == null:
		miyu = Villager.all[1]
		miyu.person["unique"] = "miyu"
		miyu.person["name"] = "Miyu"
		var trait_list: Array = miyu.person.get("traits", []).duplicate()
		trait_list.append("unique")
		miyu.person["traits"] = trait_list
	ch.events = ch.events.filter(func(e): return not str(e.what) in ["book_given:miyu", "miyu_water", "scene:miyu_water_book"])
	miyu.person.erase("tactics")
	var b := world.village.banner_cell()
	var spot := world.floors.cell_centre(b + Vector2i(26, 26))
	miko.place(spot)
	miyu.position = spot + Vector2(-1.0, 0.4) * world.px
	miyu.reset_physics_interpolation()
	Party.active.join("miyu")
	miyu._follow_start(Villager.now())
	miyu.person["level"] = 20
	if not miko.bag.items.has("WaterTome"):
		miko.bag.items[miko.bag.free_slot()] = "WaterTome"
		miko.bag.changed.emit()
	await _frames(20)
	st = Companions.stats_for(miyu.person)
	Companions.give_book(miyu.person, Companions.book_for(miyu.person, miko.bag), miko.bag)
	st.talent_points = 60
	for id in ["ihc", "ifa", "iib"]:
		st.learn_path(id)
	st.changed.emit()
	magic = CompanionMagic.give(miyu)
	print("Tactics: Miyu knows ", st.known_spells(), ", kinds ", st.known_spells().map(func(k): return Tactics.kind_of(str(k))))
	print("Tactics: her default preset ", Tactics.of(miyu.person).preset, "; a villager's ", Tactics.default_preset({"unique": ""}), "; Sera's ", Tactics.default_preset({"unique": "sera"}))
	if OS.get_environment("TAC_COST") != "":
		await _cost_only()
		return
	await _window()
	await _presets()
	if OS.get_environment("TAC_DEBUG") != "":
		return
	await _dodge_test(true)
	await _dodge_test(false)
	await _custom_order()
	_save_round_trip()
	var tot: Array = Perf._total.get(&"companion_magic.think", [0, 0])
	var rl: Array = Perf._total.get(&"companion_magic.rules", [0, 0])
	print("Tactics: thinking cost ", snappedf(float(tot[0]) / maxf(1.0, float(tot[1])), 0.1), " usec a frame over ", tot[1], " frames; the rules ", snappedf(float(rl[0]) / maxf(1.0, float(rl[1])), 0.1), " usec a look over ", rl[1], " looks")


# The party window, her Tactics window: presets, a rule dragged, the stance changed.
func _window() -> void:
	var pw: PartyWindow = g.get_node("Hud/PartyWindow")
	pw.open()
	await _frames(15)
	var tb: Button = _find_button(pw, "Tactics")
	print("Tactics: party window has a Tactics button ", tb != null)
	shot("party")
	tb.pressed.emit()
	await _frames(10)
	var tw: TacticsWindow = g.get_node("Hud/TacticsWindow")
	print("Tactics: window open ", tw.visible, ", party window closed ", not pw.visible, ", at ", tw.position, " size ", tw.size, " (screen ", get_viewport().get_visible_rect().size, ")")
	_print_rules("support preset")
	shot("window")
	# Ice Shard (the last rule) dragged up to second.
	var rows := tw._rows
	var from: TacticsWindow.RuleRow = rows[rows.size() - 1]
	var drag_data: Variant = {"tactic_rule": from.index}
	var pv := PanelContainer.new()
	pv.add_theme_stylebox_override("panel", HudStyle.piece("tileOn"))
	pv.add_child(HudStyle.label(Tactics.rule_text(from.rule), 12, "bold"))
	from.force_drag(drag_data, pv)
	tw.dragging = from.index
	var mm := InputEventMouseMotion.new()
	mm.position = onto_pos(rows[1])
	mm.global_position = mm.position
	mm.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(mm)
	var onto: TacticsWindow.RuleRow = rows[1]
	onto._can_drop_data(Vector2(5, 2), drag_data)
	await _frames(5)
	print("Tactics: dragging rule ", tw.dragging + 1, ", drop mark on rule ", onto.index + 1, " (", onto.mark, ")")
	shot("drag")
	onto._drop_data(Vector2(5, 2), drag_data)
	get_viewport().gui_cancel_drag()
	await _frames(5)
	_print_rules("after the drag")
	print("Tactics: preset now ", Tactics.of(miyu.person).preset)
	shot("reordered")
	# The up arrow on rule 3, then the stance: Keep distance to Close, Skill use Eager, Dodge off.
	tw.move_rule(2, 1)
	tw.set_stance("range", "close", true)
	tw.set_stance("frequency", "eager", true)
	tw.set_stance("dodge", false, true)
	await _frames(5)
	print("Tactics: stance now ", Tactics.stance(miyu.person))
	shot("stance")
	tw.add_rule()
	await _frames(5)
	tw.set_rule(tw._rows.size() - 1, "spell", "Blizzard")
	await _frames(5)
	print("Tactics: a Blizzard rule (unknown) greyed ", tw._rows[tw._rows.size() - 1].modulate.a < 0.5, ", usable ", Tactics.usable(st, Tactics.of(miyu.person).rules[-1]))
	shot("unknown")
	tw.use_preset("support")
	await _frames(5)
	print("Tactics: back to Support: ", Tactics.of(miyu.person).preset, ", rules ", (Tactics.of(miyu.person).rules as Array).size())
	var ev := InputEventKey.new()
	ev.keycode = KEY_ESCAPE
	ev.pressed = true
	Input.parse_input_event(ev)
	await _frames(5)
	print("Tactics: after Esc: tactics window ", tw.visible, ", party window ", pw.visible)
	pw.close()
	await _frames(3)


func onto_pos(c: Control) -> Vector2:
	return c.get_global_rect().position + Vector2(c.size.x * 0.4, 4.0)


func _print_rules(when: String) -> void:
	var out := []
	var i := 1
	for r in Tactics.of(miyu.person).rules:
		out.append("%d. %s" % [i, Tactics.rule_text(r)])
		i += 1
	print("Tactics: rules ", when, ":\n  ", "\n  ".join(PackedStringArray(out)))


func _find_button(n: Node, text: String) -> Button:
	for c in n.get_children():
		if c is Button and (c as Button).text == text:
			return c
		var f := _find_button(c, text)
		if f != null:
			return f
	return null


# A fight under each preset: what she did.
func _presets() -> void:
	for id in ["melee", "ranged", "defender", "support"]:
		Tactics.use_preset(miyu.person, id)
		await _fight(id, 20.0, true)
	# Skill use: the same Ranged rules, sparing and eager.
	for fr in ["sparing", "eager"]:
		Tactics.use_preset(miyu.person, "ranged")
		Tactics.stance(miyu.person)["frequency"] = fr
		await _fight("ranged, " + fr, 15.0, false)


func _reset_fight() -> void:
	for f in foes:
		if is_instance_valid(f):
			(f as Node).queue_free()
	foes.clear()
	await _frames(3)
	var b := world.village.banner_cell()
	var spot := world.floors.cell_centre(b + Vector2i(26, 26))
	miko.place(spot)
	miyu.position = spot + Vector2(-1.0, 0.4) * world.px
	miyu.reset_physics_interpolation()
	miyu.foe = null
	miyu.dodge_until = 0.0
	miyu.cast_until = 0.0
	miyu._follow_start(Villager.now())
	miyu.hit.hp = miyu.hit.max_hp
	miko.stats.hp = miko.stats.stat("maxHp")
	st.mana = st.stat("maxMana")
	magic.done.clear()
	magic.potions.clear()
	magic.dodges = 0
	magic.cancelled = 0
	magic.cast_in_strip = 0
	magic.casts.clear()
	miyu.repositions = 0
	if miko.bag.count("HpPotion") < 3:
		miko.bag.add("HpPotion", 3)
	if miko.bag.count("ManaPotion") < 3:
		miko.bag.add("ManaPotion", 3)


func _fight(label: String, seconds: float, with_wolf: bool) -> void:
	await _reset_fight()
	for k in 3:
		var sl := Slime.spawn(world, md.slime, false, miko.position + Vector2(4.5 + k * 0.8, 1.0 - k) * world.px, 1.0)
		sl.angry_until = Creature.now() + 60.0   # (coming for Sera, as if she'd struck first)
		sl.hit.max_hp = 120.0   # (lasting the fight out, so it shows how often she casts)
		sl.hit.hp = 120.0
		foes.append(sl)
	var potions_before := miko.bag.count("HpPotion") + miko.bag.count("ManaPotion")
	var dists := []
	var near_min := INF
	var moves_at := []
	var last_rep := 0
	var wolf: MutatedWolf = null
	var steps := int(seconds * 4.0)
	for i in steps:
		for f in 15:
			await get_tree().physics_frame
		var t := float(i + 1) / 4.0
		# (Sera kept on her feet: she doesn't fight back here)
		if miko.stats.hp < miko.stats.stat("maxHp") * 0.35:
			miko.stats.hp = miko.stats.stat("maxHp") * 0.6
		if is_equal_approx(t, 5.0) and with_wolf:
			wolf = MutatedWolf.spawn(world, md.mutatedWolf, miko.position + Vector2(-3.0, 1.2) * world.px)
			foes.append(wolf)
		if is_equal_approx(t, 9.0):
			# (badly hurt and low on mana: potions)
			miyu.hit.hp = miyu.hit.max_hp * 0.22
			st.mana = st.stat("maxMana") * 0.1
		if is_equal_approx(t, 7.0):
			shot("fight_" + label)
		var d := _nearest_foe_units()
		if d < INF:
			dists.append(d)
			near_min = minf(near_min, d)
		if miyu.repositions != last_rep:
			moves_at.append(snappedf(t, 0.25))
			last_rep = miyu.repositions
		if OS.get_environment("TAC_DEBUG") != "" and i % 4 == 3:
			print("  dbg t=", t, " state ", Villager.State.keys()[miyu.state], " foe ", miyu.foe != null, " threat ", miyu._party_threat() != null, " mfoe ", magic._foe() != null, " mana ", snappedf(st.mana, 1), "/", st.stat("maxMana"), " hp ", snappedf(miyu.hit.hp, 1), " gap ", Villager.now() < magic._gap_until, " dist ", snappedf(d, 0.1), " stab ", (miyu.s.stabDown as Array).size(), " slimes hostile ", foes.filter(func(f): return is_instance_valid(f) and (f as Creature).hostile()).size())
		if miyu.hit.hp < miyu.hit.max_hp * 0.15:
			miyu.hit.hp = miyu.hit.max_hp * 0.5   # (not let to fall: the fight goes on)
	var by := {}
	for c in magic.casts:
		by[c[0]] = int(by.get(c[0], 0)) + 1
	var avg := 0.0
	for d in dists:
		avg += d
	avg = avg / maxf(1.0, dists.size())
	print("Tactics: [", label, "] casts ", by, ", actions ", magic.done, ", distance to nearest monster avg ", snappedf(avg, 0.1), " min ", snappedf(near_min, 0.1),
		" units, steps to keep distance ", miyu.repositions, " (", snappedf(miyu.repositions * 10.0 / seconds, 0.1), " per 10 s) at ", moves_at,
		", potions ", magic.potions, " (bag ", potions_before, " -> ", miko.bag.count("HpPotion") + miko.bag.count("ManaPotion"), "), dodges ", magic.dodges,
		", spells dropped ", magic.cancelled, ", wolf leaps seen ", wolf != null)


func _nearest_foe_units() -> float:
	var best := INF
	for f in foes:
		if is_instance_valid(f) and (f as Creature).hit != null and (f as Creature).hit.alive():
			best = minf(best, (f as Creature).hit.global_position.distance_to(miyu.position) / world.px)
	return best


# A strip laid under her while she's casting: with Dodge on she drops the spell and steps out; off, she casts on.
func _dodge_test(dodge: bool) -> void:
	Tactics.use_preset(miyu.person, "ranged")
	Tactics.stance(miyu.person)["dodge"] = dodge
	await _reset_fight()
	var slime := Slime.spawn(world, md.slime, false, miko.position + Vector2(5.0, 0.0) * world.px, 1.0)
	slime.angry_until = Creature.now() + 60.0
	foes.append(slime)
	# (till she starts a spell)
	var waited := 0
	while Villager.now() >= miyu.cast_until and waited < 600:
		await get_tree().physics_frame
		waited += 1
	var strip := Telegraph.make(world, 1.2)
	strip.point(miyu.position + Vector2(-3.0, -0.4) * world.px, miyu.position + Vector2(3.0, 0.4) * world.px, 8.0 * world.px)
	var was_casting := Villager.now() < miyu.cast_until
	var in_at_start := strip.covers(miyu.position)
	var inside := []
	for i in 90:
		strip.set_fill(float(i) / 90.0)
		await get_tree().physics_frame
		if i % 15 == 14:
			inside.append(strip.covers(miyu.position))
		if i == 30:
			shot("dodge_" + ("on" if dodge else "off"))
	var still_in := strip.covers(miyu.position)
	print("Tactics: dodge ", "on" if dodge else "off", ": in the strip every quarter second ", inside, ", her state ", Villager.State.keys()[miyu.state])
	strip.queue_free()
	print("Tactics: dodge ", "on" if dodge else "off", ": casting when the strip came ", was_casting, ", in it ", in_at_start, " -> in it when it filled ", still_in,
		", dodges ", magic.dodges, ", spells dropped ", magic.cancelled, ", spells finished in the strip ", magic.cast_in_strip, ", casts ", magic.casts.map(func(c): return c[0]))
	# And a real wolf leaping at Sera with Miyu by her: does she get out of its strip?
	await _reset_fight()
	var wolf := MutatedWolf.spawn(world, md.mutatedWolf, miko.position + Vector2(-3.5, 0.0) * world.px)
	foes.append(wolf)
	miyu.position = miko.position + Vector2(-1.2, 0.05) * world.px
	miyu.reset_physics_interpolation()
	var in_strip_frames := 0
	for i in 600:
		await get_tree().physics_frame
		miko.stats.hp = miko.stats.stat("maxHp")
		var s := Tactics.strip_at(miyu.position)
		if s != null:
			in_strip_frames += 1
	print("Tactics: wolf, dodge ", "on" if dodge else "off", ": frames she stood in its strip ", in_strip_frames, " of 600, dodges ", magic.dodges, ", spells dropped ", magic.cancelled, ", finished in a strip ", magic.cast_in_strip)


# Her own order: Ice Shard (Always) moved to the top of Support; she leads with it instead of waiting on heals.
func _custom_order() -> void:
	Tactics.use_preset(miyu.person, "support")
	await _fight("support as given", 12.0, false)
	var rules: Array = Tactics.of(miyu.person).rules
	var shard: Dictionary = rules.pop_back()
	shard["weight"] = 5
	shard["spell"] = "IceShard"
	rules.insert(0, shard)
	Tactics.edited(miyu.person)
	_print_rules("custom")
	await _fight("custom: Ice Shard first", 12.0, false)


func _save_round_trip() -> void:
	var tac := Tactics.of(miyu.person)
	var saved: String = people.to_json()
	var again: Dictionary = (JSON.parse_string(saved).people as Array).filter(func(p): return str(p.get("unique", "")) == "miyu")[0]
	var back: Dictionary = again.get("tactics", {})
	print("Tactics: saved: preset ", back.get("preset", "-"), ", stance ", back.get("stance", {}), ", rules ", (back.get("rules", []) as Array).size(),
		", first rule '", Tactics.rule_text(back.rules[0]) if not (back.get("rules", []) as Array).is_empty() else "", "', same as before ", str(back) == str(JSON.parse_string(JSON.stringify(tac))))
	var old := {"unique": "miyu", "name": "Miyu"}
	var old_v := {"unique": "", "name": "Someone"}
	print("Tactics: an old save without tactics: Miyu gets ", Tactics.of(old).preset, ", a villager ", Tactics.of(old_v).preset, ", Sera ", Tactics.of({"unique": "sera"}).preset)


# Only what thinking costs: a short fight under Support.
func _cost_only() -> void:
	Tactics.use_preset(miyu.person, "support")
	await _fight("cost (first)", 10.0, true)
	Perf._total.erase(&"companion_magic.rules")
	await _fight("cost", 20.0, true)
	var bench := {}
	var u := Time.get_ticks_usec()
	for i in 100: st.known_spells()
	bench["known_spells"] = (Time.get_ticks_usec() - u) / 100.0
	u = Time.get_ticks_usec()
	for i in 100: Companions.stats_for(miyu.person)
	bench["stats_for"] = (Time.get_ticks_usec() - u) / 100.0
	u = Time.get_ticks_usec()
	for i in 100: SpellEffects.party_near(world, miyu.position, INF)
	bench["party_near"] = (Time.get_ticks_usec() - u) / 100.0
	u = Time.get_ticks_usec()
	for i in 100: Tactics.of(miyu.person)
	bench["tactics_of"] = (Time.get_ticks_usec() - u) / 100.0
	u = Time.get_ticks_usec()
	for i in 100: miyu._party_threat()
	bench["party_threat"] = (Time.get_ticks_usec() - u) / 100.0
	u = Time.get_ticks_usec()
	var rr: Array = Tactics.of(miyu.person).rules
	for i in 100: Tactics.usable(st, rr[0])
	bench["usable"] = (Time.get_ticks_usec() - u) / 100.0
	u = Time.get_ticks_usec()
	for i in 100: magic._holds(rr[0], Villager.now(), st, null)
	bench["holds_allyHp"] = (Time.get_ticks_usec() - u) / 100.0
	u = Time.get_ticks_usec()
	for i in 100: st.stat("maxMana")
	bench["stat"] = (Time.get_ticks_usec() - u) / 100.0
	print("Tactics: bench usec ", bench)
	var rt: Array = Perf._total.get(&"companion_magic.rules", [0, 0])
	print("Tactics: cost: the rules ", snappedf(float(rt[0]) / maxf(1.0, float(rt[1])), 0.1), " usec a look over ", rt[1], " looks (worst ", Perf._worst.get(&"companion_magic.rules", 0), ", a first cast), hittable ", Damageable.all.size())
