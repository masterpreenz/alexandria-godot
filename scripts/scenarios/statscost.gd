extends Scenario
## What working out a character's stats costs: total() asked many times, as the game does each frame; and the per-frame
## cost of the stats nodes (Sera's and the companions') in a short stretch of play. Run with --window=statscost.


func run() -> void:
	for i in 30:
		await get_tree().process_frame
	var st := miko.stats
	var t0 := Time.get_ticks_usec()
	for i in 2000:
		st.total()
	print("Stats cost: total() x2000 ", (Time.get_ticks_usec() - t0) / 1000.0, " ms")
	t0 = Time.get_ticks_usec()
	for i in 2000:
		st.stat("magic")
	print("Stats cost: stat() x2000 ", (Time.get_ticks_usec() - t0) / 1000.0, " ms")
	st.set_buff("test", {"magic": 3.0})
	print("Stats cost: a buff counts ", st.stat("magic"), ", gone again ", (func(): st.set_buff("test", null); return st.stat("magic")).call())
	for i in 300:
		await get_tree().process_frame
	print("Stats cost: character_stats.process worst ", snappedf(float(Perf._worst.get(&"character_stats.process", 0)) / 1000.0, 0.01), " ms, avg ", snappedf(float(Perf._total.get(&"character_stats.process", [0, 1])[0]) / maxf(1.0, float(Engine.get_process_frames())) / 1000.0, 0.001), " ms a frame")
