extends Scenario
## The F3 debug view's villager lines: each one's way in red and what they're at over their head. Run on a real save:
## --window=debugways --slot=quick (or --slot=auto).


func _secs(s: float) -> void:
	var until := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame


func run() -> void:
	await _secs(1.0)
	Perf.active._panel.visible = true
	miko.place(world.village.centre() + Vector2(1, 2) * world.px)
	for i in 6:
		await _secs(5.0)
		var held: Array = []
		for v: Villager in Villager.all:
			if is_instance_valid(v) and v._trying_for > 2.0:
				held.append("%s: %s (%s, %.1fs)" % [v.person.name, v.activity(), Villager.State.keys()[v.state], v._trying_for])
		print("Debug ways t", i * 5, ": held up ", held)
		shot("ways%d" % i)
