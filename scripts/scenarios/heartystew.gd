extends Scenario
## The Hearty golden stew: made at the cooking bench from a carrot, a cabbage and raw meat; eaten first of her food,
## it fills 70 and quickens HP and mana coming back for 15 minutes. Run with --window=heartystew --slot=new.


func run() -> void:
	for i in 20:
		await get_tree().process_frame
	var recipe := []
	for r in world._load_json("res://data/build.json").workbenches.CookingWorkbench.recipes:
		if str(r.resource) == "HeartyStew":
			recipe = r.cost
	var nd: Needs = miko.get_node("Needs")
	miko.bag.add("HeartyStew", 1)
	nd.hunger = 20.0
	var regen0 := miko.stats.stat("hpRegen")
	nd.eat()
	print("Hearty stew: recipe ", recipe.map(func(c): return "%s %d" % [c.resource, c.amount]), "; hunger after ", roundi(nd.hunger),
		"; HP regen ", regen0, " -> ", miko.stats.stat("hpRegen"), ", mana regen ", miko.stats.stat("manaRegen"),
		"; lasts ", roundi(nd._food_until.get("HeartyStew", 0.0) - Needs._now()), "s; name ", UiKit.resource_name("HeartyStew"))
