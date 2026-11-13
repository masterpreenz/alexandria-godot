extends Scenario
## Party bags: Miyu (someone standing in for her) with a bag of her own. Things handed between Sera's bag and hers on
## her page (the panel's own calls, a pick and Give, a drag), gear worn from her bag and from Sera's and taken off into
## hers, a potion in a fight and food when hungry from her bag first, her water pouch, her bag saved and put back.
## Something thrown away from a bag lies where it fell (not drawn back to Sera, nor hauled off). Then her kit at home:
## loot into storage and topped up from it (storage short of health potions), once a visit; Restock now for Sera.
## Last, playing Miyu: the bag that's played is hers, Sera's goes with Sera, the purse moves across, and back again.
## Run with --window=partybags.


func run() -> void:
	for i in 30:
		await get_tree().process_frame
	var miyu := _miyu()
	Party.active.join("miyu")
	miyu._follow_start(Villager.now())
	var centre := world.village.centre()
	miko.place(centre + Vector2(1.5, 1.0) * world.px)
	miyu.position = centre + Vector2(2.4, 1.3) * world.px
	miyu.reset_physics_interpolation()
	var p: Dictionary = miyu.person
	# (no restocking on her own till that part of the test)
	Kit.of(p)["auto"] = false
	for i in 20:
		await get_tree().process_frame
	var sb := miko.bag
	var mb := Companions.pack_of(p)
	print("Party bags: Miyu's bag made: ", mb != null, ", bag_of is it ", is_same(Companions.bag_of(p), mb), ", capacity ", mb.capacity(), ", empty ", mb.counts.values().all(func(n): return int(n) == 0) and mb.items.all(func(x): return x == ""))
	# Sera's bag stocked for the test.
	sb.add("HpPotion", 4)
	sb.add("Bread", 6)
	sb.add("Wood", 12)
	for it in ["ClothGloves", "Sachet", "WaterPouch"]:
		var at := sb.free_slot()
		if at >= 0:
			sb.items[at] = it
	sb.changed.emit()
	var cp: CharacterPanel = g.get_node("Hud/CharacterPanel")
	cp.open_for(p)
	for i in 5:
		await get_tree().process_frame
	print("Party bags: page for ", cp.shown.get("name"), ", their bag shown ", cp._their_col.visible, ", titles '", cp._labels.bag_title.text, "' / '", cp._labels.their_title.text, "'")
	# The panel's calls: one potion, then the rest; the bread; the gloves.
	var n1 := cp.give_to_them(int(sb.stack_slot.HpPotion), true)
	var n2 := cp.give_to_them(int(sb.stack_slot.HpPotion))
	var n3 := cp.give_to_them(int(sb.stack_slot.Bread))
	var n4 := cp.give_to_them(sb.items.find("ClothGloves"))
	print("Party bags: given potions ", n1, " then ", n2, ", bread ", n3, ", gloves ", n4, "; Sera now HpPotion ", sb.count("HpPotion"), " Bread ", sb.count("Bread"), " gloves ", sb.items.has("ClothGloves"), "; Miyu HpPotion ", mb.count("HpPotion"), " Bread ", mb.count("Bread"), " gloves ", mb.items.has("ClothGloves"))
	# The UI's path: a pick and Give (Wood); then dragged back from her bag onto Sera's grid.
	cp._dirty = true
	await get_tree().process_frame
	var wood_cell := cp._shows.find(["stack", "Wood"])
	cp.clicked(wood_cell, false)
	await get_tree().process_frame
	print("Party bags: picked Wood in Sera's bag: give button '", cp._give.text, "' visible ", cp._give.visible)
	cp.give_picked()
	await get_tree().process_frame
	print("Party bags: after Give: Sera Wood ", sb.count("Wood"), ", Miyu Wood ", mb.count("Wood"))
	var free_cell := -1
	for i in sb.capacity():
		if sb.items[i] == "" and sb.stack_in(i) == "":
			free_cell = i
			break
	cp.dropped(int(mb.stack_slot.Wood), free_cell, true, false)
	await get_tree().process_frame
	print("Party bags: Wood dragged back into Sera's cell ", free_cell, ": Sera Wood ", sb.count("Wood"), " in slot ", sb.stack_slot.get("Wood"), ", Miyu Wood ", mb.count("Wood"))
	# A pick in her bag: Take.
	cp.clicked(int(mb.stack_slot.Bread), false, true)
	await get_tree().process_frame
	print("Party bags: picked Bread in Miyu's bag: give button '", cp._give.text, "', action '", cp._action.text, "' visible ", cp._action.visible)
	cp.selected = -1
	cp.in_theirs = false
	# Wearing from her bag, taking off into it; a bag worn from Sera's.
	var mst := Companions.stats_for(p)
	cp.clicked(mb.items.find("ClothGloves"), true, true)
	await get_tree().process_frame
	print("Party bags: gloves worn from her bag: worn ", mst.worn_in("Gloves"), ", still in her bag ", mb.items.has("ClothGloves"))
	cp.pick_slot("Gloves")
	cp._do_action()
	await get_tree().process_frame
	print("Party bags: gloves taken off: worn '", mst.worn_in("Gloves"), "', in her bag ", mb.items.has("ClothGloves"), ", in Sera's ", sb.items.has("ClothGloves"))
	cp._dirty = true
	await get_tree().process_frame
	var cap_before := mb.capacity()
	cp.clicked(cp._shows.find(["item", sb.items.find("Sachet")]), true)
	await get_tree().process_frame
	print("Party bags: Sachet worn from Sera's bag: worn ", mst.worn_in("Bag"), ", Miyu's capacity ", cap_before, " -> ", Companions.pack_of(p).capacity(), ", Sachet left in Sera's ", sb.items.has("Sachet"), " / in Miyu's ", mb.items.has("Sachet"))
	cp._dirty = true
	await get_tree().process_frame
	shot("page")
	# A potion in a fight: from her bag first.
	miyu.hit.hp = miyu.hit.max_hp * 0.3
	mst.hp = miyu.hit.hp
	var h_m := mb.count("HpPotion")
	var h_s := sb.count("HpPotion")
	var drank := Tactics.drink(miyu, mst, "HpPotion")
	print("Party bags: tactics potion drunk ", drank, ": Miyu's ", h_m, " -> ", mb.count("HpPotion"), ", Sera's ", h_s, " -> ", sb.count("HpPotion"))
	# Hungry: her own bread first; then with none of her own, Sera's.
	p["hunger"] = 20.0
	var b_m := mb.count("Bread")
	var b_s := sb.count("Bread")
	var ate := Party.active.feed(p)
	print("Party bags: fed ", ate, ": Miyu's bread ", b_m, " -> ", mb.count("Bread"), ", Sera's ", b_s, " -> ", sb.count("Bread"))
	mb.spend("Bread", mb.count("Bread"))
	p["hunger"] = 20.0
	print("Party bags: on her own with nothing to eat: looked after ", Party.active.look_after(p), "; fed by Sera ", Party.active.feed(p), ", Sera's bread ", sb.count("Bread"))
	# Water: her own pouch (handed over as full as Sera's was).
	var nd: Needs = miko.get_node("Needs")
	nd.pouch = 60.0
	cp.give_to_them(sb.items.find("WaterPouch"))
	p["thirst"] = 20.0
	print("Party bags: pouch given: hers ", Party.active.has_pouch(p), " at ", Party.active.pouch_of(p), "%, Sera has one ", Party.active.has_pouch({}))
	var drunk := Party.active.look_after(p)
	print("Party bags: thirsty, drank from her own ", drunk, ": her pouch ", Party.active.pouch_of(p), "%, thirst ", p.thirst, ", Sera's pouch ", nd.pouch)
	# Her bag saved with her and put back.
	mb.add("Crystal", 2)
	var before := mb.to_json()
	people.to_json()
	var saved_pack := str(p.get("pack", ""))
	Companions._packs.erase("miyu")
	var again := Companions.pack_of(p)
	print("Party bags: saved with her ", saved_pack != "", ", put back a new bag ", not is_same(again, mb), ", same ", again.to_json() == before, ", capacity ", again.capacity(), ", Crystal ", again.count("Crystal"))
	mb = again
	cp.show_for(p)
	# Thrown away: a Drop from Sera's bag lies there.
	cp._dirty = true
	await get_tree().process_frame
	cp.clicked(cp._shows.find(["stack", "Wood"]), false)
	cp._do_drop()
	var thrown: Array = Pickup.all.filter(func(pk): return pk.resource == "Wood" and pk.thrown)
	await get_tree().create_timer(2.5).timeout
	thrown = thrown.filter(func(pk): return is_instance_valid(pk))
	var near := miyu._nearest_loose(40.0 * world.px)
	print("Party bags: Wood thrown: pieces ", thrown.size(), " still lying after 2.5 s at her feet ", thrown.all(func(pk): return pk.position.distance_to(miko.position) < 1.5 * world.px), ", Sera's Wood ", sb.count("Wood"), ", hauled by a villager ", near != null and thrown.has(near), ", saved thrown ", Pickup.to_json(world).contains("\"thrown\":true"))
	cp.window.visible = false
	# Her kit at home: loot in, topped up from storage (short of health potions).
	var v := world.village
	mb.add("Hide", 5)
	mb.add("Bread", 14)
	mb.add("Stone", 7)
	var gear_at := mb.free_slot()
	mb.items[gear_at] = "JadeRing"
	v.stash["HpPotion"] = 1
	v.stash["ManaPotion"] = 9
	v.items.append("WaterPouch")
	var k := Kit.of(p)
	k["auto"] = true
	p.erase("kitHome")
	var stash_before := {"Hide": v.stored("Hide"), "Bread": v.stored("Bread"), "Stone": v.stored("Stone"), "HpPotion": v.stored("HpPotion"), "ManaPotion": v.stored("ManaPotion"), "rings": v.items.count("JadeRing"), "pouches": v.items.count("WaterPouch")}
	print("Party bags: kit ", k.preset, " ", k.rows, "; Miyu carries Hide ", mb.count("Hide"), " Bread ", mb.count("Bread"), " Stone ", mb.count("Stone"), " HpPotion ", mb.count("HpPotion"), " ManaPotion ", mb.count("ManaPotion"), " pouches ", mb.items.count("WaterPouch"), " ring ", mb.items.has("JadeRing"), "; storage ", stash_before)
	Party.active._restock_at_home()
	await get_tree().process_frame
	var stash_after := {"Hide": v.stored("Hide"), "Bread": v.stored("Bread"), "Stone": v.stored("Stone"), "HpPotion": v.stored("HpPotion"), "ManaPotion": v.stored("ManaPotion"), "rings": v.items.count("JadeRing"), "pouches": v.items.count("WaterPouch")}
	print("Party bags: restocked at home: Miyu carries Hide ", mb.count("Hide"), " Bread ", mb.count("Bread"), " food ", Kit.carried(mb, Kit.FOOD), " Stone ", mb.count("Stone"), " HpPotion ", mb.count("HpPotion"), " ManaPotion ", mb.count("ManaPotion"), " pouches ", mb.items.count("WaterPouch"), " ring ", mb.items.has("JadeRing"), ", pouch ", Party.active.pouch_of(p), "%; storage ", stash_after)
	print("Party bags: village log short line ", VillageLog._entries.keys().filter(func(x): return str(x).begins_with("kit_short")))
	shot("restocked")
	var hp_now := mb.count("HpPotion")
	v.stash["HpPotion"] = 10
	Party.active._restock_at_home()
	print("Party bags: again on the same visit: HpPotion ", hp_now, " -> ", mb.count("HpPotion"), " (once a visit)")
	# Restock now, for Sera, from the Kit window.
	var kw: KitWindow = g.get_node("Hud/KitWindow")
	sb.add("Hide", 3)
	kw.open_for({}, false)
	await get_tree().process_frame
	await get_tree().process_frame
	var sk := Kit.of({})
	print("Party bags: Sera's kit ", sk.preset, " auto ", sk.auto, ", at home ", kw.at_home(), "; before: HpPotion ", sb.count("HpPotion"), " ManaPotion ", sb.count("ManaPotion"), " food ", Kit.carried(sb, Kit.FOOD), " Hide ", sb.count("Hide"), " pouches ", sb.items.count("WaterPouch"))
	shot("kit")
	var r := Kit.restock_now({})
	kw._fill()
	await get_tree().process_frame
	print("Party bags: Sera restocked now: ", Kit.said(r), "; HpPotion ", sb.count("HpPotion"), " ManaPotion ", sb.count("ManaPotion"), " food ", Kit.carried(sb, Kit.FOOD), " Hide ", sb.count("Hide"), " pouches ", sb.items.count("WaterPouch"), ", short ", r.short, "; village log ", VillageLog._entries.keys().filter(func(x): return str(x).begins_with("kit_short")))
	shot("kit_after")
	kw.close()
	k["auto"] = false
	# Playing Miyu: her bag is the one played, Sera's goes with Sera, the purse moves across.
	sb.add("Gold", 0)
	var gold := sb.count("Gold")
	var sera_bag := sb.to_json()
	var miyu_bag := mb.to_json()
	miko.place(miyu.position + Vector2(-0.8, 0.3) * world.px)
	miyu._stand(Villager.now(), 2.0)
	for i in 5:
		await get_tree().process_frame
	# (her page left open through the switch: it goes back to the one played)
	cp.open_for(p)
	Talk.active.open(miyu)
	for i in 10:
		await get_tree().process_frame
	Talk.active._finish_typing()
	Talk.active._play_as()
	for i in 30:
		await get_tree().process_frame
	print("Party bags: the page left open through the switch is now ", "the one played's" if cp.shown.is_empty() else str(cp.shown.get("name")), ", stats valid ", is_instance_valid(cp.stats), ", their bag ", cp.theirs != null)
	cp.window.visible = false
	var sera := _sera_body()
	var sera_pack := Companions.pack_of(sera.person) if sera != null else null
	print("Party bags: playing ", Playable.active.who, ": bag played is Miyu's ", _same_bag(sb, miyu_bag), ", HpPotion ", sb.count("HpPotion"), " Crystal ", sb.count("Crystal"), ", gold ", sb.count("Gold"), " (was ", gold, "), worn ", sb.worn, ", capacity ", sb.capacity())
	print("Party bags: Sera's bag with Sera ", sera_pack != null and _same_bag(sera_pack, sera_bag), ", her gold ", sera_pack.count("Gold") if sera_pack != null else -1, ", her pouch ", sera.person.get("pouch") if sera != null else -1, "; no second copy of Miyu's bag in her person ", not Playable.active.played.has("pack"))
	var sections: Dictionary = (g.get_node("SaveGame") as SaveGame).capture()
	var vs: Dictionary = JSON.parse_string(str(sections.get("village.people", "{}")))
	var saved_sera: Array = (vs.get("people", []) as Array).filter(func(q): return str(q.get("unique", "")) == "sera")
	print("Party bags: saved while playing Miyu: player.bag is hers ", _same_bag(sb, str(sections.get("player.bag", ""))), ", Sera's pack saved with her ", not saved_sera.is_empty() and sera_pack != null and _same_bag(sera_pack, str(saved_sera[0].get("pack", ""))))
	var hotbar: Hotbar = g.get_node("Hud/Hotbar")
	print("Party bags: hotbar ", hotbar.slots.filter(func(x): return str(x) != ""))
	cp.open_for(sera.person)
	for i in 5:
		await get_tree().process_frame
	shot("sera_page")
	cp.window.visible = false
	# And back.
	sera.position = miko.position + Vector2(0.8, 0.3) * world.px
	sera.reset_physics_interpolation()
	sera._stand(Villager.now(), 2.0)
	for i in 5:
		await get_tree().process_frame
	Talk.active.open(sera)
	for i in 10:
		await get_tree().process_frame
	Talk.active._finish_typing()
	Talk.active._play_as()
	for i in 30:
		await get_tree().process_frame
	var mbody: Villager = null
	for vv in Villager.all:
		if is_instance_valid(vv) and str(vv.person.get("unique", "")) == "miyu":
			mbody = vv
	var back_pack := Companions.pack_of(mbody.person) if mbody != null else null
	print("Party bags: back as ", Playable.active.who, ": Sera's bag back ", _same_bag(sb, sera_bag), ", gold ", sb.count("Gold"), ", worn ", sb.worn, "; Miyu's bag with her ", back_pack != null and _same_bag(back_pack, miyu_bag))


# Whether [param b] holds what [param json] did (gold aside: the purse).
func _same_bag(b: Bag, json: String) -> bool:
	var other := Bag.new()
	other.from_json(json)
	other.counts["Gold"] = 0
	var mine := Bag.new()
	mine.from_json(b.to_json())
	mine.counts["Gold"] = 0
	return mine.to_json() == other.to_json()


func _miyu() -> Villager:
	for v in Villager.all:
		if is_instance_valid(v) and str(v.person.get("unique", "")) == "miyu":
			return v
	# (the bundled save has no Miyu: someone stands in for her, in her look)
	var miyu: Villager = Villager.all[1]
	miyu.person["unique"] = "miyu"
	miyu.person["name"] = "Miyu"
	miyu.person["look"] = 5
	var trait_list: Array = miyu.person.get("traits", []).duplicate()
	trait_list.append("unique")
	miyu.person["traits"] = trait_list
	var lk: Dictionary = people._look_for(miyu.person)
	miyu.look = lk
	miyu.s = lk.settings
	miyu.name = "Miyu"
	return miyu


func _sera_body() -> Villager:
	for v in Villager.all:
		if is_instance_valid(v) and str(v.person.get("unique", "")) == "sera":
			return v
	return null
