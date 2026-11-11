extends Scenario
## A day in which food and wood run down, hour by hour: what the log says.
## Run with --window=ledger.


func run() -> void:
	var lg: Ledger = g.get_node("Ledger")
	var v := world.village
	for f in Villager.FOODS:
		v.stash[f[0]] = 0
	v.stash["BakedPotato"] = 60
	v.stash["Wood"] = 40
	clock.hours = floorf(clock.hours) + 0.5
	lg.notes.clear()
	for h in 12:
		clock.hours += 1.0
		v.stash["BakedPotato"] = v.stored("BakedPotato") - 2
		v.stash["Wood"] = v.stored("Wood") - 1
		v.stash["Stone"] = v.stored("Stone") + 1
		for i in 3:
			await get_tree().process_frame
	print("Ledger: a day's change food ", roundi(lg.a_day("Food")), ", wood ", roundi(lg.a_day("Wood")), ", stone ", roundi(lg.a_day("Stone")))
	for k in ["Food", "Wood", "Stone"]:
		print("  ", k, ": ", VillageLog._entries.get("running-down:" + k, {}).get("text", "(nothing)"))
