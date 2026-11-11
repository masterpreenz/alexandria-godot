extends Scenario
## Miko by a rock, stepping about beside it: where "Press E to mine" sits from the rock (should stay put).
## Run with --window=mineprompt.


func run() -> void:
	for i in 5:
		await get_tree().process_frame
	var rock: Gatherable = null
	var best := INF
	for rk in Gatherable.all:
		if is_instance_valid(rk) and not rk.axe and not rk.depleted() and rk.foot.distance_to(miko.position) < best:
			best = rk.foot.distance_to(miko.position)
			rock = rk
	var mn: Node = miko.get_node("Miner")
	var lbl: Label = mn.prompt
	for step in [Vector2(-0.5, 0.4), Vector2(0.4, 0.5), Vector2(0.0, 0.7)]:
		miko.place(rock.foot + step * world.px)
		for i in 10:
			await get_tree().process_frame
		var rock_screen := get_viewport().get_canvas_transform() * rock.foot
		print("Mine prompt: '", lbl.text, "' at ", (lbl.position - rock_screen).round(), " from the rock")
