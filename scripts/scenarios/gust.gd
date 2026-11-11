extends Scenario
## The "gust" scenario.
## Run with --window=gust.


func run() -> void:
	var ws: WorldSounds = world.get_node("WorldSounds")
	ws.gust_now()
	var ch := WorldSounds.chime()
	print("Chime ", ch.get_length(), " s; rivers ", ws._rivers.size(), " river volumes ", ws._rivers.map(func(r): return snappedf(db_to_linear(r.player.volume_db), 0.001)), " playing ", ws._rivers.map(func(r): return r.player.playing), " villager steps ", ws._steps.size())
	for i in 60:
		await get_tree().process_frame
