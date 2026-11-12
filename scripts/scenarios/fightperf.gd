extends Scenario
## The village fight's frame times and what takes them: the first wave in, Sera standing in the middle of it.
## Run with --window=fightperf --slot=new.


func run() -> void:
	var st: Story = g.get_node("Story")
	for i in 30:
		await get_tree().process_frame
	Chronicle.active.record("scene:messenger")
	while str(st._beats()[st.beat].id) != "rush":
		st._begin(st.beat + 1, false)
		await get_tree().process_frame
	miko.place(world.village.centre() + Vector2(1, 1) * world.px)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 8000:   # (the camera's look, and the horde arriving)
		miko.stats.hp = miko.stats.stat("maxHp")
		await get_tree().process_frame
	if Shots.arg("nolights") != "":
		for l in g.find_children("*", "PointLight2D", true, false):
			(l as PointLight2D).enabled = false
		print("Fight perf: lights off")
	if Shots.arg("mixlights") != "":
		for l in g.find_children("*", "PointLight2D", true, false):
			(l as PointLight2D).blend_mode = Light2D.BLEND_MODE_MIX
		print("Fight perf: lights mixed")
	if Shots.arg("noparticles") != "":
		for n in g.find_children("*", "GPUParticles2D", true, false) + g.find_children("*", "CPUParticles2D", true, false):
			n.emitting = false
			n.visible = false
		print("Fight perf: particles off")
	var p: Perf = Perf.active
	p._all_frames.clear()
	Perf._total.clear()
	Perf._worst.clear()
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 10000:
		miko.stats.hp = miko.stats.stat("maxHp")
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_fight.png")
	var raiders := Raids.active.raiders.filter(func(r): return is_instance_valid(r)).size()
	print("Fight perf: raiders ", raiders, "; ", p.summary())
	print("Fight perf: ", p._engine())
