extends Scenario
## The "moods" scenario.
## Run with --window=moods.


func run() -> void:
	while Villager.all.size() < 3:
		await get_tree().process_frame
	var ms := ["affection", "idea", "alarm"]
	for k in 3:
		var v: Villager = Villager.all[k]
		v.position = miko.position + Vector2(-2.6 + k * 2.6, -0.4) * world.px
		v.show_mood(ms[k], 30.0)
	for i in int(Shots.arg("mframes", "40")):
		await get_tree().process_frame
