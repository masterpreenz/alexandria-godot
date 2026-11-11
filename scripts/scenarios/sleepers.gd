extends Scenario
## Every housed villager put to bed: how far each is turned, and a close picture of each.
## Run with --window=sleepers.


func run() -> void:
	clock.hours = float(clock.day() - 1) * 24.0 + 23.0
	for i in 200:
		await get_tree().process_frame
	camera.zoom *= 2.0
	var n := 0
	for v in Villager.all:
		if v.home.is_empty():
			continue
		if not v.in_bed:
			v._go_to_sleep()
		v.sleep_clock = 5.0
		miko.place(v.position + Vector2(0.9, 0.9) * world.px)
		miko.visible = false
		for i in 60:
			for r in world.roofs.roofs:
				for tl in r.tiles:
					if is_instance_valid(tl): (tl as CanvasItem).visible = false
			await get_tree().process_frame
		var fit: Array = Needs._fit(world, v.home, v.look.get("lying", {}).get("sleepUp" if v.facing_up else "sleepDown"), v.facing_right, 1.0)
		if fit.size() >= 5:
			print("  head lands ", ((v.position + (fit[4] as Vector2).rotated(v.art.rotation)) - fit[2]).round(), " px from the pillow, middle ", ((v.position + (fit[3] as Vector2).rotated(v.art.rotation)) - fit[1]).round(), " from the mattress's middle; pillow from middle ", ((fit[2] as Vector2) - fit[1]).round(), ", head from middle ", ((fit[4] as Vector2) - fit[3]).round())
		print("Sleeper ", v.person.name, " look ", int(v.person.look), ": turned ", snappedf(rad_to_deg(v.art.rotation), 0.1), " deg, bed turn ", int(v.home.e.turn))
		get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_%d.png" % n)
		n += 1
