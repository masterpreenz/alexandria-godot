extends Scenario
## The "picker" scenario.
## Run with --window=picker.


func run() -> void:
	(g.get_node("Hud/Hotbar") as Hotbar).clicked(0)
