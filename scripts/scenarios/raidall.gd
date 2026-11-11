extends Scenario
## A raid by night with the village asleep, and one by day with everyone at work: who's up and fighting; and the seed
## kept for planting, left alone by the hungry, the cooks and the rot.
## Run with --window=raidall.


func run() -> void:
	var raids: Raids = g.get_node("Raids")
	while Villager.all.size() < 3:
		await get_tree().process_frame
	for when in [["night, all asleep", 1.0], ["evening, at the day's end", 20.5]]:
		clock.hours = float(clock.day()) * 24.0 + float(when[1])
		for vl in Villager.all:
			vl.person.hunger = 90.0
			vl.person.energy = 90.0
			vl.hit.hp = vl.hit.max_hp
		for i in 240:
			await get_tree().process_frame
		miko.place(world.village.centre() + Vector2(1.0, 1.0) * world.px)
		var before := Villager.all.map(func(x): return Villager.State.keys()[x.state])
		var came := raids.start(4)
		var most := 0
		var up_at := -1
		for i in 1500:
			await get_tree().process_frame
			most = maxi(most, Villager.all.filter(func(x): return x.state == Villager.State.FIGHT).size())
			if up_at < 0 and Villager.all.all(func(x): return x.state != Villager.State.ASLEEP):
				up_at = i
			if most >= Villager.all.size():
				break
		var bars := Villager.all.filter(func(x): return (x.get_node("HeadBars") as HeadBars).visible).size()
		var mb: HeadBars = miko.get_node("HeadBars")
		print("Raid bars: villagers with their HP showing ", bars, " of ", Villager.all.size(), ", their mana shown ", Villager.all.any(func(x): return float((x.get_node("HeadBars") as HeadBars).values()[2]) >= 0.0), "; Miko's (full HP ", miko.stats.hp >= miko.stats.total().get("maxHp", 0.0) - 0.5, ") showing ", mb.visible, ", in a fight ", mb.fighting())
		get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_" + str(when[0]).get_slice(",", 0) + ".png")
		print("Raid (", when[0], "): before ", before, "; ", came, " came; all up after ", up_at, " frames; fighting at most ", most, " of ", Villager.all.size(), " (", Villager.all.filter(func(x): return not (x.s.stabDown as Array).is_empty()).size(), " can fight); now ", Villager.all.map(func(x): return Villager.State.keys()[x.state]))
		print("  raid on ", Raids.on(), "; raiders ", raids.raiders.filter(func(r): return is_instance_valid(r)).map(func(r): return [r.get_class(), snappedf(r.position.distance_to(world.village.centre()) / world.px, 0.1), world.village.contains(r.position, 10.0)]), "; damageables of the raid ", Damageable.all.filter(func(d): return Raids.raider(d.get_parent())).size(), "; a villager's threat ", Villager.all[0]._threat(), ", low ", Villager.all[0]._low())
		for r in raids.raiders:
			if is_instance_valid(r):
				r.queue_free()
		raids.raiders = []
		for i in 30:
			await get_tree().process_frame
	# The seed kept back.
	var v := world.village
	for f in Villager.FOODS:
		v.stash[f[0]] = 0
	var plots: int = (miko.get_node("Farming") as Farming).plots.filter(func(p): return v.contains(p.pos, 3.0)).size()
	v.stash["Potato"] = 5
	miko.bag.counts["Potato"] = 0
	for i in 150:
		await get_tree().process_frame
	var nd: Needs = miko.get_node("Needs")
	nd.hunger = 10.0
	miko.place(v.centre())
	print("Seed: ", plots, " plots, potatoes in storage ", v.stored("Potato"), ", kept for planting ", v.reserve.get("Potato", 0), ", to spare ", v.spare("Potato"), "; Miko eats one ", nd.eat("Potato"), "; next to cook ", Kitchen.next(v), "; a villager finds food ", Villager.all[0]._food_in_storage())
