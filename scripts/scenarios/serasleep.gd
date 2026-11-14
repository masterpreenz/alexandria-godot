extends Scenario
## Sera as a villager (while someone else is played) put to bed: lying on it, head on the pillow, turned the bed's
## way, as any villager lies. Run with --window=serasleep.


func run() -> void:
	clock.hours = float(clock.day() - 1) * 24.0 + 23.0
	for i in 200:
		await get_tree().process_frame
	camera.zoom *= 2.0
	var lk := Playable.active._sera_as_villager()
	print("Sera sleeps: her sleep art faces right ", lk.settings.get("sleepFacesRight"), ", lying ", lk.get("lying"))
	var n := 0
	for v in Villager.all:
		if v.home.is_empty() or v.person.has("unique"):
			continue
		# (dressed as Sera, as she is when she lives in the village)
		v.look = lk
		v.s = lk.settings
		if v.in_bed:
			v._wake_up(Villager.now())
		v._go_to_sleep()
		v.sleep_clock = 5.0
		miko.place(v.position + Vector2(0.9, 0.9) * world.px)
		miko.visible = false
		for i in 60:
			for r in world.roofs.roofs:
				for tl in r.tiles:
					if is_instance_valid(tl): (tl as CanvasItem).visible = false
			await get_tree().process_frame
		var fit: Array = Needs._fit(world, v.home, v.look.get("lying", {}).get(v.sleep_pose()), v.facing_right != v._sleep_faces_right(), 1.0)
		if fit.size() >= 5:
			print("Sera sleeps: head lands ", ((v.position + (fit[4] as Vector2).rotated(v.art.rotation)) - fit[2]).round(), " px from the pillow; bed turn ", int(v.home.e.turn), ", turned ", snappedf(rad_to_deg(v.art.rotation), 0.1), " deg, drawn flipped ", v.art.scale.x < 0.0)
		shot("bed%d" % n)
		n += 1
		if n >= 3:
			break
