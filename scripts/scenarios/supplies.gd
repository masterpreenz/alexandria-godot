extends Scenario
## Under Sera's card: what she has to eat and drink in her bag. Run with --window=supplies.


func run() -> void:
	for i in 20:
		await get_tree().process_frame
	miko.bag.add("Water", 3)
	miko.bag.add("GrilledFish", 2)
	for i in 10:
		await get_tree().process_frame
	var food := 0
	for pair in Needs.EAT_ORDER:
		food += miko.bag.count(str(pair[0]))
	print("Supplies: food ", food, ", water ", miko.bag.count("Water"))
	shot("card")
