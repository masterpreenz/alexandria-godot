extends Scenario
## The seven spell books in Sera's bag, with their own pictures (only the water one is found in the game yet).
## Run with --window=spellbooks.


func run() -> void:
	for i in 20:
		await get_tree().process_frame
	for b in ["LifeTome", "WaterTome", "FireTome", "LightningTome", "LightTome", "DarkTome", "MikoTome"]:
		var slot := miko.bag.free_slot()
		if slot >= 0:
			miko.bag.items[slot] = b
		var it: Dictionary = UiKit.data.items.get(b, {})
		print("Spell books: ", b, " '", it.get("name", "?"), "' icon ", it.get("icon", {}), " exists ", ResourceLoader.exists(str(it.get("icon", {}).get("tex", ""))))
	var cp: CharacterPanel = CharacterPanel._active
	cp.toggle()
	for i in 10:
		await get_tree().process_frame
	shot("bag")
