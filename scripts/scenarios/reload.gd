extends Scenario
## The "reload" scenario.
## Run with --window=reload.


func run() -> void:
	if SaveSystem.loaded_slot == "":
		print("Reloading into ", Shots.arg("slot2"))
		(g.get_node("SaveGame") as SaveGame).restart(Shots.arg("slot2"))
		return
	print("Reloaded from ", SaveSystem.loaded_slot, ": villagers ", Villager.all.size(), " creatures ", Creature.all.size(), " gatherables ", Gatherable.all.size(), " Miko at ", miko.position)
