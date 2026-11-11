extends Scenario
## Walks right, then stops: how far the view's centre is from where she's drawn, frame by frame after.
## Run with --window=stopcam.


func run() -> void:
	Input.action_press("ui_right")
	for i in 40:
		await get_tree().process_frame
	Input.action_release("ui_right")
	var gaps := []
	for i in 30:
		await get_tree().process_frame
		gaps.append(snappedf((camera.get_screen_center_position() - g.follow_offset - miko.drawn_position()).length(), 0.1))
	print("Stop: view behind her by ", gaps)
