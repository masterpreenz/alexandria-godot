extends Scenario
## The "chest" scenario.
## Run with --window=chest (or --window=totals) (or --window=ask).


func run() -> void:
	if not world.village.chests().is_empty():
		miko.place(world.village.chests()[0] + Vector2(0, 0.6 * world.px))
	vd.chest_window.open()
	if Shots.arg("window") == "totals": vd.chest_window.show_totals(true)
	if Shots.arg("window") == "ask": vd.chest_window._ask_for("Wood")
