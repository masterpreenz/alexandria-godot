extends Scenario
## Enough XP for a level: the effect, half a second in.
## Run with --window=levelup.


func run() -> void:
	miko.stats.gain_xp(miko.stats.xp_to_next() - miko.stats.xp)
	for i in int(Shots.arg("lvframes", "30")):
		await get_tree().process_frame
