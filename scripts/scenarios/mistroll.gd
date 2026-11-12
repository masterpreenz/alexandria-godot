extends Scenario
## The mist rolling in on Sera's camp the night of the attack: from all round towards her over a few seconds, not all
## at once; frame times while it does, and pictures along the way. Run with --window=mistroll --slot=new.


func run() -> void:
	var st: Story = g.get_node("Story")
	for i in 30:
		await get_tree().process_frame
	clock.hours = float(clock.day()) * 24.0 + float(Shots.arg("hour", "25.5"))
	var p: Perf = Perf.active
	p._all_frames.clear()
	Perf._total.clear()
	Perf._worst.clear()
	st._act({"do": "mist_in"})
	print("Mist roll: queued ", world.mist._rolling.map(func(b): return b.size()).reduce(func(a, c): return a + c, 0), " in ", world.mist._rolling.size(), " bands; moving ", world.mist._moving.size(), "; no mist held ", Story.mist_held())
	var t0 := Time.get_ticks_msec()
	var shots := [1.0, 3.0, 5.0, 7.5]
	while Time.get_ticks_msec() - t0 < 10000:
		var s := (Time.get_ticks_msec() - t0) / 1000.0
		if not shots.is_empty() and s >= shots[0]:
			get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_%ds.png" % roundi(shots[0] * 10))
			shots.pop_front()
		await get_tree().process_frame
	print("Mist roll: ", p.summary().split("\n")[0], "; mist where she is ", world.mist.tier_at(miko.position))
	var w := 0.0
	for k in Perf._worst:
		if String(k).begins_with("mist"):
			w = maxf(w, Perf._worst[k] / 1000.0)
	var m := world.mist
	for off in [Vector2(6, 0), Vector2(0, 4), Vector2(-8, 2)]:
		var q: Vector2 = miko.position + off * world.px
		var x := floori((q.x - m.rect.position.x) / m.cell)
		var y := floori((q.y - m.rect.position.y) / m.cell)
		var i := y * m.width + x
		print("Mist roll: ", off, " target ", m.target[i], " shown ", snappedf(m._shown[i], 0.01), " moving ", m._moving.size(), " rolling left ", m._rolling.size())
	print("Mist roll: worst mist frame ", snappedf(w, 0.1), " ms")
