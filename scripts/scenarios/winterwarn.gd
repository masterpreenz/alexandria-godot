extends Scenario
## Autumn's last two days: what the village log says each.
## Run with --window=winterwarn.


func run() -> void:
	var fr: Fires = miko.get_node("Fires")
	clock.forced = -1
	var autumn := float(clock.days_per_season * ((GameClock.Season.AUTUMN - clock.start_season + 4) % 4)) * 24.0
	for back in [3, 2, 1]:
		clock.hours = autumn + float(clock.days_per_season - back) * 24.0 + 9.0
		fr._warned_day = -1
		for i in 5:
			await get_tree().process_frame
		print("Winter warning, ", back, " days of autumn left: ", VillageLog._entries.get("winter-coming", {}).get("text", "(nothing)"))
	print("Winter wood a day: ", fr.winter_wood_a_day(), " from ", fr.fires.size(), " fires")
