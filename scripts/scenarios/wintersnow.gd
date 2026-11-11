extends Scenario
## The weather through the last day of autumn and the first two of winter, for a few weather seeds.
## Run with --window=wintersnow.


func run() -> void:
	var first_winter := float(clock.days_per_season * ((GameClock.Season.WINTER - clock.start_season + 4) % 4)) * 24.0
	print("Winter snow: weather pinned by hand ", clock.forced)
	clock.forced = -1
	for seed_now in [1234, 1, 99]:
		clock.weather_seed = seed_now
		var seen := []
		for h in range(-24, 48, 6):
			clock.hours = first_winter + h + 1.0
			clock._slot = -1
			clock._update_weather()
			seen.append("%s d%d %s" % [GameClock.SEASON_NAMES[clock.season()], clock.day_of_season(), GameClock.WEATHER_NAMES[clock.weather()]])
		print("Winter snow (seed ", seed_now, "): ", seen)
