extends Scenario
## The "saves" scenario.
## Run with --window=saves.


func run() -> void:
	if Shots.arg("savenow") != "": (g.get_node("SaveGame") as SaveGame).save(Shots.arg("savenow"), false, "Test save")
	(g.get_node("Hud/SaveMenu") as SaveMenu).open()
