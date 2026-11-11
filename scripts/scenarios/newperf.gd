extends Scenario
## How a new game runs at its start: Sera on the road, the first seconds of the story, then a walk up the road.
## Prints the frame times, the costliest parts, and where each villager got to (none should be stuck).
## Run with --window=newperf --slot=new (add --perf=show for the debug list in the pictures).


func _measure(label: String, walk: bool) -> void:
	var p: Perf = Perf.active
	p._all_frames.clear()
	Perf._total.clear()
	Perf._worst.clear()
	for v in Villager.all:
		v.set_meta("p0", v.position)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 6000:
		if walk:
			miko.place(miko.position + Vector2(-0.08, 0.04) * world.px)
		await get_tree().process_frame
	print(label, ": ", p.summary())
	var stuck := []
	for v in Villager.all:
		if is_instance_valid(v) and not v.in_bed and v.position.distance_to(v.get_meta("p0", v.position)) < 0.5 * world.px \
				and v.state != Villager.State.STAND and v.state != Villager.State.ASLEEP:
			stuck.append(str(v.person.name))
	print(label, ": villagers who didn't get anywhere ", stuck)
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_" + label + ".png")


func run() -> void:
	for i in 60:
		await get_tree().process_frame
	await _measure("standing", false)
	await _measure("walking", true)
