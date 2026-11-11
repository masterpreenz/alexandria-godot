extends Scenario
## The "map" scenario.
## Run with --window=map.


func run() -> void:
	(g.get_node("Hud/WorldMap") as WorldMap).open()
	if Shots.arg("mapzoom") != "":
		for i in int(Shots.arg("mapzoom")): (g.get_node("Hud/WorldMap") as WorldMap)._step(1, null)
