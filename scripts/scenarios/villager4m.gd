extends Scenario
## The second young man's look (look 6) beside the first (look 0) for size: each of his poses, facing down and up, to
## the left and to the right. Run with --window=villager4m.

const POSES := [["idle", "idleDown", 0], ["walk", "walkDown", 3], ["chop", "chopDown", 7], ["mine", "mineDown", 4], ["fish", "fishDown", 6],
	["bowdraw", "bowDown", 5], ["bowloose", "bowDown", 9], ["stab", "stabDown", 8], ["sleep0", "sleepDown", 0], ["sleep7", "sleepDown", 7], ["sleep15", "sleepDown", 15]]


func _man(vs: Villagers, look: int, at: Vector2) -> Villager:
	var who := {"name": "Look %d" % look, "look": look}
	vs._fix(who)
	var v := Villager.new()
	v.setup(world, vs, vs._look_for(who), who, {})
	v.position = at
	v.set_physics_process(false)
	v.set_process(false)
	return v


func run() -> void:
	for i in 40:
		await get_tree().process_frame
	clock.forced = GameClock.Weather.CLEAR
	clock.hours = float(clock.day() - 1) * 24.0 + 11.0
	var vs: Villagers = g.find_child("Villagers", true, false)
	var base := world.village.centre() + Vector2(0, 2.0) * world.px
	var row: Array = []
	for k in 5:
		row.append(_man(vs, 0 if k == 0 else 6, base + Vector2(k * 1.1, 0) * world.px))
	camera.zoom *= 2.4
	miko.place(base + Vector2(2.2, 0.0) * world.px)
	miko.visible = false
	print("villager4m: looks ", vs.d.looks.size(), " male ", Villager.male(row[1].person), " cooking skill ", Villagers.skill(row[1].person, 4))
	# (look 0 faces down-left as the reference; the four of his: down/up, left/right)
	var faces := [[false, false], [false, false], [true, false], [false, true], [true, true]]
	for pose in POSES:
		for k in 5:
			var v: Villager = row[k]
			var key: String = pose[1]
			var up: bool = faces[k][1]
			if up:
				key = key.replace("Down", "Up")
			v.facing_right = faces[k][0]
			v.facing_up = up
			var ids: Variant = v.s.get(key)
			var list: Array = ids if ids is Array else [ids]
			if list.is_empty():
				continue
			v._show(int(list[mini(int(pose[2]), list.size() - 1)]))
		for i in 4:
			await get_tree().process_frame
		shot(str(pose[0]))
	# Asleep in a bed of the village (the first villager with a home, wearing his look).
	for r in row:
		r.visible = false
	miko.visible = true
	var sleeper: Villager = null
	for v in Villager.all:
		if is_instance_valid(v) and not v.home.is_empty() and v not in row:
			sleeper = v
			break
	if sleeper != null:
		sleeper.person["look"] = 6
		var lk: Dictionary = vs._look_for(sleeper.person)
		sleeper.look = lk
		sleeper.s = lk.settings
		sleeper.set_process(false)
		sleeper.set_physics_process(false)
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
		shot("bed")
	else:
		print("villager4m: no one with a bed")
	print("villager4m: done")
