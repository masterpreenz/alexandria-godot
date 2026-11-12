extends Scenario
## A new game's bag: her necklace and staff on, travel food (smoked fish, bread), her water pouch with 5 water; she
## can drink from it (G) away from a well. Run with --window=starterbag --slot=new.


func run() -> void:
	for i in 20:
		await get_tree().process_frame
	var nd: Needs = miko.get_node("Needs")
	print("Starter bag: items ", miko.bag.items.filter(func(x): return str(x) != ""), "; smoked fish ", miko.bag.count("SmokedFish"),
		", bread ", miko.bag.count("Bread"), ", water ", miko.bag.count("Water"), "; can drink from it ", Wells.has_mug(miko.bag), ", holds ", Wells.holds(miko.bag))
	nd.thirst = 30.0
	nd.drink()
	nd.hunger = 40.0
	nd.eat()
	print("Starter bag: after a drink and a bite, thirst ", roundi(nd.thirst), ", water left ", miko.bag.count("Water"), "; hunger ", roundi(nd.hunger), ", smoked fish ", miko.bag.count("SmokedFish"), ", bread ", miko.bag.count("Bread"))
	var cp: CharacterPanel = CharacterPanel._active
	cp.toggle()
	for i in 10:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_bag.png")
