extends Scenario
## The "cams" scenario.
## Run with --window=cams.


func run() -> void:
	for c in get_tree().root.find_children("*", "Camera2D", true, false):
		print("Camera ", c.get_path(), " callback ", c.process_callback, " interp ", c.is_physics_interpolated())
