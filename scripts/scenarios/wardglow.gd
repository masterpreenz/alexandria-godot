extends Scenario
## A cleansing crystal beside the village's teleport crystal, close up: both glowing and sparkling.
## Run with --window=wardglow.


func run() -> void:
	var tp: Array = world.props_named("TeleportCrystal")
	var near_tp: Vector2 = tp[0] if not tp.is_empty() else miko.position
	var wc := world.floors.cell_at(near_tp) + Vector2i(2, -2)
	world.props.place(wc, "CleansingCrystal")
	miko.place((near_tp + world.floors.cell_centre(wc)) / 2.0 + Vector2(0, 0.9) * world.px)
	camera.zoom *= 1.5
	for i in 90:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_day.png")
	clock.hours = float(clock.day()) * 24.0 + 22.0
	for i in 90:
		await get_tree().process_frame
