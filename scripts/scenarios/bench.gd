extends Scenario
## The "bench" scenario.
## Run with --window=bench.


func run() -> void:
	var wb: WorkbenchWindow = g.get_node("Hud/WorkbenchWindow")
	for prop in wb.benches:
		if Shots.arg("bench") != "" and prop != Shots.arg("bench"):
			continue
		if not world.props_named(prop).is_empty():
			miko.place(world.props_named(prop)[0] + Vector2(0, 0.6 * world.px))
			wb.open(prop, world.props_named(prop)[0])
			break
