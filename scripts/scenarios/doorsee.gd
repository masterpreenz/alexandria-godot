extends Scenario
## Every door: whether its outline is showing (hidden behind its house); a picture by a hidden one.
## Run with --window=doorsee.


func run() -> void:
	var hidden_at := Vector2.INF
	for i in 20:
		await get_tree().process_frame
	for o in get_tree().root.find_children("DoorOutline", "", true, false):
		var oc := o as OccludedOutline
		print("Door at ", oc.body.global_position.round(), " covered ", oc.covered, " outline shown ", snappedf(oc.shown, 0.1))
		if oc.covered and hidden_at == Vector2.INF:
			hidden_at = oc.body.global_position
	if hidden_at != Vector2.INF:
		miko.place(hidden_at + Vector2(-2.5, 2.0) * world.px)
		for i in 20:
			await get_tree().process_frame
