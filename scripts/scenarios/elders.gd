extends Scenario
## The elders: two villagers made the old man and the old woman (their looks), what work they'll take and won't,
## walking and standing, and both at the front of the camera for a picture.
## Run with --window=elders.


func run() -> void:
	while Villager.all.size() < 2:
		await get_tree().process_frame
	clock.forced = GameClock.Weather.CLEAR
	clock.hours = float(clock.day()) * 24.0 + 10.0
	var looks: Array = people.d.looks
	var out := []
	for pair in [[Villager.all[0], 3, "Genzo"], [Villager.all[1], 4, "Haruko"]]:
		var v: Villager = pair[0]
		v.person.look = pair[1]
		v.person.name = pair[2]
		people._fix(v.person)
		v.look = looks[pair[1]]
		v.s = v.look.settings
		v.person.hunger = 90.0
		v.person["thirst"] = 90.0
		Villager.only(v.person, [Villager.Job.ANY])
		out.append(v)
		var takes := []
		for j in Villager.JOBS:
			if Villager.weight_of(v.person, j) > 1:
				takes.append(Villager.JOB_KEYS[j])
		print("Elders: ", v.person.name, " (look ", pair[1], ") set to any work takes ", takes, "; can fight ", not (v.s.stabDown as Array).is_empty(), "; mines when put on it ", v._find_work(Villager.Job.MINING, true), ", fishes when put on it ", v._go_fish(true) or true)
		v._stand(Villager.now(), 0.0)
	miko.place(out[0].position + Vector2(1.2, 0.6) * world.px)
	out[1].position = out[0].position + Vector2(1.0, 0.0) * world.px
	out[0]._stand(Villager.now(), 5.0)
	out[1]._stand(Villager.now(), 5.0)
	camera.zoom *= 2.0
	for i in 20:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_stand.png")
	for v in out:
		v.state = Villager.State.WALK
		v._set_goal(v.position + Vector2(-3.0, 1.5) * world.px)
	for i in 25:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_walk.png")
