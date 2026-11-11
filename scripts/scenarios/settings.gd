extends Scenario
## The "settings" scenario.
## Run with --window=settings.


func run() -> void:
	var sm: SaveMenu = g.get_node("Hud/SaveMenu")
	sm.open()
	sm._set_tab(Shots.arg("tab", "Display"))
