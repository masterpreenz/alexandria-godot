extends Scenario
## Watches the villagers a while: how often any of them stands in the mist.
## Run with --window=mistcheck.


func run() -> void:
	var out := 0
	var looks := 0
	for i in int(Shots.arg("watch", "1500")):
		await get_tree().physics_frame
		for v in Villager.all:
			if v.visible:
				looks += 1
				if not Villager.safe_ground(world, v.position): out += 1
	print("Villagers in the mist: ", out, " of ", looks, " looks")
