extends Scenario
## Four mutated villagers round her, each walking a different diagonal, to see which way they face.
## Run with --window=mutants.


func run() -> void:
	var md: Dictionary = world._load_json("res://data/monsters.json")
	var dirs := [Vector2(-1, 0.5), Vector2(1, 0.5), Vector2(-1, -0.5), Vector2(1, -0.5)]
	var gap := float(Shots.arg("gap", "2.2"))
	for dv: Vector2 in dirs:
		var mv := MutatedVillager.spawn(world, md.mutatedVillager, miko.position + dv * gap * world.px)
		mv.target = mv.position + dv * 3.0 * world.px
		mv.state = MutatedVillager.State.WALK
		mv.state_until = MutatedVillager.now() + 10.0
	for i in int(Shots.arg("mframes", "25")):
		await get_tree().process_frame
