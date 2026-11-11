extends Scenario
## The "talents" scenario.
## Run with --window=talents.


func run() -> void:
	(g.get_node("Hud/CharacterPanel") as CharacterPanel).toggle_talents()
