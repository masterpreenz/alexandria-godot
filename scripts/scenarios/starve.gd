extends Scenario
## Hunger to 0: her bubble, slower, and the pangs.
## Run with --window=starve.


func run() -> void:
	var nd: Needs = miko.get_node("Needs")
	nd.hunger = 0.0
	var hp0: float = miko.stats.hp
	for i in 400:
		await get_tree().process_frame
	print("Starve: bubble '", nd._bubble_label.text if nd._bubble_label else "", "' HP ", hp0, " -> ", miko.stats.hp, " moveSpeed ", miko.stats.stat("moveSpeed"))
	nd._bubble_at = 0.0
	for i in 4:
		await get_tree().process_frame
