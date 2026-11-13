extends Scenario
## Miyu's own sprite set (look 5): her poses in a row beside Sera and an ordinary villager for scale, her fishing rod
## tips, a fall and a bed for her sleeping. (Played as Miyu: scenario playmiyu.) Run with --window=miyuart.

func _miyu_look(v: Villager, facing_right := false, facing_up := false) -> void:
	v.person["unique"] = "miyu"
	v.person["name"] = "Miyu"
	v.person["look"] = 5
	var lk: Dictionary = (get_tree().current_scene.find_child("Villagers", true, false) as Villagers)._look_for(v.person)
	v.look = lk
	v.s = lk.settings
	v.facing_right = facing_right
	v.facing_up = facing_up


func _freeze(v: Villager) -> void:
	v.set_process(false)
	v.set_physics_process(false)


func _put(v: Villager, at: Vector2) -> void:
	v.position = at
	v.reset_physics_interpolation()


func _spawn() -> Villager:
	var vsn: Villagers = get_tree().current_scene.find_child("Villagers", true, false)
	var person := vsn._newcomer()
	var v := Villager.new()
	v.setup(world, vsn, vsn._look_for(person), person, {})
	return v


func run() -> void:
	for i in 30:
		await get_tree().process_frame
	clock.forced = GameClock.Weather.CLEAR
	clock.hours = float(clock.day() - 1) * 24.0 + 11.0
	var centre := world.village.centre()
	var vs: Array = []
	for i in 14:
		vs.append(_spawn())
	await get_tree().process_frame
	var homed: Villager = null
	for v in Villager.all:
		if is_instance_valid(v) and not v.home.is_empty() and v not in vs:
			homed = v
			break
	# Standing: down and up, both ways round, with Sera (Miko) and an ordinary villager.
	miko.place(centre + Vector2(0, 2.0) * world.px)
	var stand_at := centre + Vector2(2.2, 1.3) * world.px
	var combos := [[false, false], [true, false], [false, true], [true, true]]
	for i in 4:
		var v: Villager = vs[i + 1]
		_miyu_look(v, combos[i][0], combos[i][1])
		_freeze(v)
		_put(v, stand_at + Vector2(1.0 * i + 1.0, 0) * world.px)
		v._show_idle()
	var other: Villager = vs[5]
	_freeze(other)
	_put(other, stand_at)
	other._show_idle()
	miko.place(stand_at + Vector2(5.2, 0.0) * world.px)
	for i in 5:
		await get_tree().process_frame
	shot("stand")
	# Her work in a row, frame by frame (down, then up).
	var poses := [["walkDown", 3], ["walkUp", 3], ["chopDown", 7], ["chopUp", 7], ["mineDown", 4], ["mineUp", 4], ["cookDown", 8], ["cookUp", 8], ["fishDown", 6], ["fishUp", 6], ["stabDown", 8], ["stabUp", 8]]
	var row_at := centre + Vector2(1.0, 1.5) * world.px
	for i in poses.size():
		var v: Villager = vs[i + 1] if i < 4 else vs[(i % 11) + 1]
		_miyu_look(v, false, str(poses[i][0]).ends_with("Up"))
		_freeze(v)
		_put(v, row_at + Vector2(1.5 * floori(i / 2.0), 1.6 * (i % 2)) * world.px)
		var frames: Array = v.s.get(poses[i][0], [])
		v._show(int(frames[poses[i][1]]))
	miko.place(row_at + Vector2(3.8, 0.8) * world.px)
	for i in 5:
		await get_tree().process_frame
	shot("poses")
	vs[0].visible = false
	for i in range(2, vs.size()):
		vs[i].visible = false
	# Fishing: the rod tip for every frame (a red dot where the line would leave).
	for dir in ["Down", "Up"]:
		var v: Villager = vs[1]
		_miyu_look(v, false, dir == "Up")
		_freeze(v)
		var at := centre + Vector2(2.2, 1.3) * world.px
		_put(v, at)
		miko.place(at + Vector2(0, 1.8) * world.px)
		for i in 6:
			await get_tree().process_frame
		var dots: Array = []
		for f in 16:
			var frames: Array = v.s.get("fish" + dir)
			var tips: Array = v.s.get("fishTips" + dir)
			var k: float = world.px / float(world.sprites[int(frames[f])].ppu) * v._scale()
			var tip: Array = tips[f]
			var d := Polygon2D.new()
			d.polygon = PackedVector2Array([Vector2(-2, -2), Vector2(2, -2), Vector2(2, 2), Vector2(-2, 2)])
			d.color = Color(1, 0, 0)
			d.z_index = 100
			world.add_child(d)
			dots.append(d)
			v._show(int(frames[f]))
			d.global_position = v.global_position + Vector2(float(tip[0]), float(tip[1])) * k
			for i in 2:
				await get_tree().process_frame
			if f in [0, 3, 6, 9, 12]:
				shot("fish%s%d" % [dir, f])
			d.queue_free()
	# Fainting: her fall (the frames the faint plays: stagger, fall, lying).
	var fv: Villager = vs[1]
	_miyu_look(fv, false, false)
	_put(fv, centre + Vector2(2.2, 1.3) * world.px)
	miko.place(fv.position + Vector2(0, 1.8) * world.px)
	for i in 6:
		await get_tree().process_frame
	var fa: Array = fv.s.faintDown
	for f in [0, 6, 10, 11, 12]:
		fv._show(int(fa[f]))
		for i in 3:
			await get_tree().process_frame
		shot("faint%d" % f)
	# Asleep in a bed.
	var sleeper: Villager = homed
	if sleeper != null:
		_miyu_look(sleeper, false, false)
		_freeze(sleeper)
		sleeper._go_to_sleep()
		sleeper._show(int(sleeper.s.sleepDown[15]))
		sleeper.lie_in_bed()
		miko.place(sleeper.position + Vector2(1.1, 0.4) * world.px)
		for i in 40:
			await get_tree().process_frame
		sleeper._show(int(sleeper.s.sleepDown[15]))
		sleeper.lie_in_bed()
		for i in 5:
			await get_tree().process_frame
		shot("sleep")
		print("Miyuart: asleep in bed at ", sleeper.position, ", turn ", sleeper.home.e.turn, ", facing right ", sleeper.facing_right, " up ", sleeper.facing_up)
	print("Miyuart: look 5 frames idle ", vs[1].s.idleDown, ", walk ", (vs[1].s.walkDown as Array).size(), ", faint ", (vs[1].s.faintDown as Array).size())
