extends Scenario
## Every Hearth and Body talent learnt: the stats, the bag, the rabbits, the villagers' pace, a shove,
## blocked hits, and Second Wind saving her once.
## Run with --window=hearthbody.


func run() -> void:
	var st: CharacterStats = miko.stats
	var slots0 := miko.bag.capacity()
	var rpens: RabbitPens = g.find_child("RabbitPens", true, false)
	var breed0 := rpens._breed_hours()
	for tl in st.character.talents:
		if str(tl.region) in ["Hearth", "Body"]:
			st.ranks[tl.id] = 1
	st.changed.emit()
	var tot := st.total()
	var shown := []
	for k in ["gatherSpeed", "woodYield", "stoneYield", "harvestBonus", "foodKeeps", "cookSpeed", "cookBonus", "craftBonus", "bagSlots", "rabbitBreeding", "butcherBonus", "villageWork", "maxHp", "defense", "calmRegen", "mistResist", "hungerResist", "knockResist", "blockChance", "secondWind"]:
		shown.append("%s %s" % [k, str(tot.get(k, 0))])
	print("Hearth/Body stats: ", ", ".join(shown))
	print("Bag slots ", slots0, " -> ", miko.bag.capacity(), "; rabbits breed every ", breed0, " -> ", snappedf(rpens._breed_hours(), 0.1), " h")
	miko.place(world.village.centre() + Vector2(1, 1) * world.px)
	for i in 400:
		await get_tree().process_frame
	print("Villagers' pace with Miko in the village: ", Villagers.heart)
	miko.knock(Vector2(100, 0), 0.2)
	print("A shove of 100 becomes ", snappedf(miko._knock.length(), 0.1))
	var blocks := [0]
	st.blocked.connect(func(): blocks[0] += 1)
	for i in 400:
		st.hp = float(tot.maxHp)
		st.damage(1.0)
	print("Blocked ", blocks[0], " of 400 hits")
	st.hp = float(tot.maxHp)
	st.damage(99999.0)
	print("Second Wind: after a felling blow HP ", st.hp)
	st.damage(99999.0)
	print("Second Wind: hit again at once, HP ", st.hp)
	for i in 60:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_wind.png")
	for i in 500:
		await get_tree().process_frame
	print("Second Wind: a few seconds on HP ", snappedf(st.hp, 0.1), " of ", tot.maxHp, "; statuses ", (miko.get_node("Needs") as Needs).effects().map(func(x): return x[0]))
	st.damage(99999.0)
	print("Second Wind: felled again while it waits, HP ", st.hp)
