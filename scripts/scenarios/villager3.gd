extends Scenario
## The three looks side by side, standing; then the third one's poses in turn (--pose=walkDown...).
## Run with --window=villager3.


func run() -> void:
	while Villager.all.size() < 2:
		await get_tree().process_frame
	var vs: Villagers = g.find_child("Villagers", true, false)
	var shown := []
	for k in 3:
		var who := {"name": "Look %d" % k, "look": k}
		vs._fix(who)
		var v := Villager.new()
		v.setup(world, vs, vs._look_for(who), who, {})
		world.things.add_child(v)
		v.position = miko.position + Vector2(-1.6 + k * 1.1, 0.9) * world.px
		v.set_physics_process(false)
		v.set_process(false)
		shown.append(v)
	camera.zoom *= 2.2
	miko.place(miko.position + Vector2(-0.5, 0.2) * world.px)
	for i in 10:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_stand.png")
	var third: Villager = shown[2]
	for pose in ["idleUp", "walkDown", "walkUp", "mineDown", "mineUp", "chopDown", "chopUp", "cookDown", "cookUp", "stabDown", "stabUp", "sleepDown", "sleepUp"]:
		for k in 3:
			var vv: Villager = shown[k]
			var ids: Variant = vv.s.get(pose)
			var list: Array = ids if ids is Array else [ids]
			if not list.is_empty():
				vv._show(int(list[mini(list.size() - 1, int(Shots.arg("frame", "5")) if list.size() > 4 else 1)]))
		for i in 3:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_" + pose + ".png")
	print("Villager 3: shown, look 2 of ", vs.d.looks.size(), ", ", third.person.name)
