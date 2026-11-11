extends Scenario
## The job board: the order as it stands; a job moved up; a villager put on a job, and what they do.
## Run with --window=jobboard.


func run() -> void:
	var jw: JobsWindow = g.get_node("Hud/JobsWindow")
	jw.visible = true
	jw._built_for = "-"
	for i in 6:
		await get_tree().process_frame
	jw.show_tab("Job Board")
	for i in 6:
		await get_tree().process_frame
	print("Job board: order ", people.board.map(func(j): return JobsWindow.JOB_NAMES[j]), "; rows ", jw._board_rows.size(), ", cards ", jw._board_cards.size())
	jw.move_job(Villager.Job.FISHING, -1)
	jw.move_job(Villager.Job.FISHING, -1)
	jw.move_job(Villager.Job.MINING, -10)
	print("Job board: fishing up two, mining up one: ", people.board.map(func(j): return JobsWindow.JOB_NAMES[j]))
	# A villager set to no work at all, dropped on Lumbering (as the row takes a drop).
	clock.forced = GameClock.Weather.CLEAR
	clock.hours = float(clock.day() - 1) * 24.0 + 9.0
	var p: Dictionary = people.people[1]
	var vl: Villager = null
	for x in Villager.all:
		if x.person == p:
			vl = x
	Villager.only(p, [])
	world.village.stash["Wood"] = 0
	p.hunger = 100.0
	for row in jw._board_box.get_children():
		if row is JobsWindow.JobRow and (row as JobsWindow.JobRow).job == Villager.Job.LUMBERING and not row.is_queued_for_deletion():
			print("Job board: the row takes a villager ", (row as JobsWindow.JobRow)._can_drop_data(Vector2.ZERO, {"villager": p}), ", not something else ", (row as JobsWindow.JobRow)._can_drop_data(Vector2.ZERO, "x"))
			(row as JobsWindow.JobRow)._drop_data(Vector2.ZERO, {"villager": p})
	vl._stand(Villager.now(), 0.0)
	var went := []
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 25000 and vl.doing() != Villager.Job.LUMBERING:
		await get_tree().process_frame
		var what: String = Villager.State.keys()[vl.state]
		if went.is_empty() or went[-1] != what:
			went.append(what)
	for i in 20:
		await get_tree().process_frame
	print("Job board: ", p.name, " set to no work, put on ", JobsWindow.JOB_NAMES[int(p.get("first", -1))], ": went ", went, ", at it now ", vl.doing() == Villager.Job.LUMBERING, "; the card says '", jw._board_cards[1].first.text, "'")
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_board.png")
	var again: Dictionary = JSON.parse_string(people.to_json())
	print("Job board: saved: board ", again.board, ", ", p.name, " first ", again.people[1].get("first"))
	jw.put_on(p, -1)
	print("Job board: taken off: first ", p.get("first", "none"))
