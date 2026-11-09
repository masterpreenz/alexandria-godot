class_name Shots
## Small shared helpers: command-line screenshots (for checking the port without the editor) and wheel zoom.


## With [code]-- --shot=path.png[/code] on the command line: frames the view ([code]--at=x,y[/code],
## [code]--zoom=z[/code], [code]--hour=h[/code] handled by the caller), waits a few frames, saves a screenshot and quits.
static func take_if_asked(node: Node, camera: Camera2D) -> void:
	var shot := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="): shot = arg.substr(7)
		elif arg.begins_with("--at="):
			var p := arg.substr(5).split(",")
			camera.position = Vector2(float(p[0]), float(p[1]))
		elif arg.begins_with("--zoom="): camera.zoom = Vector2.ONE * float(arg.substr(7))
	if shot == "":
		return
	var frames := 8
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--frames="): frames = int(arg.substr(9))
	for i in frames:
		await RenderingServer.frame_post_draw
	node.get_viewport().get_texture().get_image().save_png(shot)
	print("Saved ", shot)
	node.get_tree().quit()


## A command-line value: [code]--name=value[/code], or [param fallback].
static func arg(name: String, fallback: String = "") -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + name + "="): return a.substr(name.length() + 3)
	return fallback


static func wheel_zoom(event: InputEvent, camera: Camera2D, least: float, most: float) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera.zoom = (camera.zoom * 1.15).clamp(Vector2(least, least), Vector2(most, most))
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera.zoom = (camera.zoom / 1.15).clamp(Vector2(least, least), Vector2(most, most))
