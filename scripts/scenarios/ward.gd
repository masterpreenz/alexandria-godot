extends Scenario
## Beside a cleansing crystal, inside its clearing: its curtain and the ring on the ground.
## Run with --window=ward.


func run() -> void:
	var cr: Crystals = g.get_node("Crystals")
	for i in 10:
		await get_tree().process_frame   # (the crystals are dressed a frame or two in)
	if not cr.wards.is_empty():
		miko.place(cr.wards[0].pos + Vector2(float(Shots.arg("dx", "1.5")), float(Shots.arg("dy", "2.5"))) * world.px)
	for i in 60:
		await get_tree().process_frame
