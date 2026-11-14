extends Scenario
## A crystal necklace worn at night out in the mist: its light and clearing; then worn nearly out.
## Run with --window=necklace.


func run() -> void:
	clock.hours = float(Shots.arg("hour", "22"))
	miko.place(miko.position + Vector2(float(Shots.arg("dx", "0")), float(Shots.arg("dy", "0"))) * world.px)
	miko.bag.items[miko.bag.free_slot()] = "CrystalNecklace"
	var slot := miko.bag.items.find("CrystalNecklace")
	if Shots.arg("nowear") == "": miko.stats.equip(miko.bag, slot)
	print("Necklace worn: ", miko.stats.worn_in("Trinket"), " durability ", miko.stats.durability_left("CrystalNecklace"))
	if Shots.arg("wornout") != "":
		miko.stats.wear["CrystalNecklace"] = 899.0
	for i in 120:
		await get_tree().process_frame
	if Shots.arg("zoom") != "":
		camera.zoom *= float(Shots.arg("zoom"))
	print("After: worn ", miko.stats.worn_in("Trinket"), " durability ", miko.stats.durability_left("CrystalNecklace"), " tier here ", world.mist.tier_at(miko.position))
