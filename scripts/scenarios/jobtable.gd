extends Scenario
## The jobs window: every villager a row, every job a column of ten boxes; set, and what they then do.
## Run with --window=jobtable.


func run() -> void:
	var jw: JobsWindow = g.get_node("Hud/JobsWindow")
	jw.visible = true
	jw._built_for = "-"
	for i in 6:
		await get_tree().process_frame
	var p: Dictionary = people.people[1]
	var vl: Villager = null
	for v in Villager.all:
		if v.person == p:
			vl = v
	print("Job table: window ", jw.size, " of ", get_viewport().get_visible_rect().size, "; ", p.name, " weights ", Villager.JOBS.map(func(j): return Villager.weight_of(p, j)), " '", JobsWindow.jobs_text(p), "'")
	# As clicked: mining off (the first box), fishing 10, farming 4.
	var row: Dictionary = jw._rows[1]
	(row.pips[Villager.Job.MINING] as JobsWindow.Pips).picked.emit(1)
	(row.pips[Villager.Job.LUMBERING] as JobsWindow.Pips).picked.emit(1)
	(row.pips[Villager.Job.FARMING] as JobsWindow.Pips).picked.emit(4)
	await get_tree().process_frame
	var took := {"fish": 0, "farm": 0, "mine": 0}
	for i in 3000:
		took.fish += 1 if vl._wants(Villager.Job.FISHING) else 0
		took.farm += 1 if vl._wants(Villager.Job.FARMING) else 0
		took.mine += 1 if vl._wants(Villager.Job.MINING) else 0
	print("Job table: mining and lumbering 1, farming 4: weights ", Villager.JOBS.map(func(j): return Villager.weight_of(p, j)), " '", JobsWindow.jobs_text(p), "'; of 3000 times, takes fishing ", took.fish, ", farming ", took.farm, ", mining ", took.mine)
	for j in Villager.JOBS:
		if j != Villager.Job.FARMING:
			(row.pips[j] as JobsWindow.Pips).picked.emit(1)
	await get_tree().process_frame
	var alone := 0
	for i in 1000:
		alone += 1 if vl._wants(Villager.Job.FARMING) else 0
	print("Job table: only farming, at 4: '", JobsWindow.jobs_text(p), "', takes farming ", alone, " of 1000; saved ", JSON.parse_string(people.to_json()).people[1].get("weights"))
	var sizes := []
	for t in ["Storage Rules", "Jobs"]:
		jw.show_tab(t)
		for i in 4:
			await get_tree().process_frame
		sizes.append(jw.size)
	print("Job table: the window on Storage Rules, Jobs: ", sizes)
	var went := [jw.tab]
	for code in [KEY_E, KEY_E, KEY_E, KEY_Q]:
		var key := InputEventKey.new()
		key.keycode = code
		key.pressed = true
		Input.parse_input_event(key)
		await get_tree().process_frame
		await get_tree().process_frame
		went.append(jw.tab)
	# Typing in the search box: she doesn't walk, the tabs don't switch.
	jw.show_tab("Storage Rules")
	await get_tree().process_frame
	var search: LineEdit = jw.find_children("*", "LineEdit", true, false)[0]
	search.grab_focus()
	miko.locked = false
	var stood := miko.position
	Input.action_press("ui_right")
	var d_key := InputEventKey.new()
	d_key.keycode = KEY_E
	d_key.pressed = true
	Input.parse_input_event(d_key)
	for i in 30:
		await get_tree().physics_frame
	print("Job table: typing in the search box, right held 30 frames and E pressed: she moved ", snappedf(miko.position.distance_to(stood), 0.1), " px, tab still ", jw.tab)
	search.release_focus()
	for i in 30:
		await get_tree().physics_frame
	Input.action_release("ui_right")
	print("Job table: the box left, right held 30 more: she moved ", snappedf(miko.position.distance_to(stood), 0.1), " px")
	print("Job table: E, E, E, Q: ", went, "; talk prompt up ", g.get_node("Hud/Talk").visible)
