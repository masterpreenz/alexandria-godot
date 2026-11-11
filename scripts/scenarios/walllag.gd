extends Scenario
## Build mode, Demolish: house walls removed one every 20 frames; how long each removal and the frames after.
## Run with --window=walllag.


func run() -> void:
	var bm := BuildMode.active
	bm.set_open(true)
	bm.set_tool("Demolish")
	bm.set_demolish_only("Walls")
	var cells := []
	for k in world.walls.walls.keys().slice(0, 8):
		cells.append(Vector2i(k.x, k.y))
	for c in cells:
		var t0 := Time.get_ticks_usec()
		bm._clear_one(c)
		var took := (Time.get_ticks_usec() - t0) / 1000.0
		var worst := 0.0
		for i in 20:
			var f0 := Time.get_ticks_usec()
			await get_tree().process_frame
			worst = maxf(worst, (Time.get_ticks_usec() - f0) / 1000.0)
		print("Wall off ", c, ": the call ", snappedf(took, 0.1), " ms, worst frame after ", snappedf(worst, 0.1), " ms")
