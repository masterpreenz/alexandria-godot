extends Scenario
## The minimap's redraws: standing still, building (a floor a second), then zooming in and out.
## Run with --window=mmbench.


func run() -> void:
	var fl := world.floors
	var other: String = ""
	for n in fl.types:
		if n != fl.base_floor and not fl.is_whole(n):
			other = n
			break
	var t0 := Time.get_ticks_msec()
	print("MMPHASE still")
	for i in 600:
		await get_tree().process_frame
	print("MMPHASE build ", other)
	var c0 := fl.cell_at(miko.position) + Vector2i(3, 3)
	for i in 600:
		if i % 60 == 0:
			fl.paint(c0 + Vector2i(floori(i / 60.0), 0), other)
		await get_tree().process_frame
	print("MMPHASE zoom")
	var mm: Minimap = g.get_node("Hud/Minimap")
	for i in 600:
		if i % 60 == 0:
			mm._step(1 if i % 240 < 120 else -1)
		await get_tree().process_frame
	print("MMPHASE end ", Time.get_ticks_msec() - t0)
