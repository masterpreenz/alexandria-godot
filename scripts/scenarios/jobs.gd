extends Scenario
## The "jobs" scenario.
## Run with --window=jobs.


func run() -> void:
	(g.get_node("Hud/JobsWindow") as JobsWindow).visible = true
	if Shots.arg("tab") != "":
		(g.get_node("Hud/JobsWindow") as JobsWindow).tab = Shots.arg("tab")
