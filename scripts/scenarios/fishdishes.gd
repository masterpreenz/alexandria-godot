extends Scenario
## The fish dishes: made at the cooking workbench, eaten, how they keep.
## Run with --window=fishdishes.


func run() -> void:
	var recipes: Array = world._load_json("res://data/build.json").workbenches.CookingWorkbench.recipes
	var nd: Needs = miko.get_node("Needs")
	for dish in ["SmokedFish", "FishSoup", "FishStew"]:
		var made: Array = recipes.filter(func(r): return r.resource == dish)
		miko.bag.counts[dish] = 2
		nd.hunger = 10.0
		var ate := nd.eat(dish)
		print("Fish dishes: ", UiKit.resource_name(dish), ": recipe ", made[0].cost if not made.is_empty() else "NONE", " -> ", made[0].amount if not made.is_empty() else 0,
			"; eaten ", ate, ", hunger 10 -> ", nd.hunger, ", buff ", Needs.FOOD_BUFFS.get(dish, {}), ", spoils ", Spoilage.PER_DAY.get(dish, "never"), " a day, takes cooking ", 3 if dish in WorkbenchWindow.FINE_DISHES else 1,
			", villagers eat it for ", Villager.FOODS.filter(func(f): return f[0] == dish))
