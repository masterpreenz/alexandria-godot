extends Scenario
## As loaded (the user's save: winter, weather pinned clear): how much snow lies. Then autumn's last
## day, pinned clear, run on into winter: the pin drops and it snows.
## (as if just loaded on winter's third morning, the weather pinned clear, no snow saved)
## Run with --window=winterload.


func run() -> void:
	clock.hours = float(clock.days_per_season * ((GameClock.Season.WINTER - clock.start_season + 4) % 4) + 2) * 24.0 + 8.3
	clock.forced = GameClock.Weather.CLEAR
	snow.set_cover(0.0)
	snow._last_hours = -1.0
	for i in 150:
		await get_tree().process_frame
	print("Winter load: ", GameClock.SEASON_NAMES[clock.season()], " day ", clock.day_of_season(), ", weather ", GameClock.WEATHER_NAMES[clock.weather()], ", pinned ", clock.forced, ", snow lying ", snappedf(snow.cover, 0.01))
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_loaded.png")
	var first_w := float(clock.days_per_season * ((GameClock.Season.WINTER - clock.start_season + 4) % 4)) * 24.0
	clock.hours = first_w - 2.0 + (0.0 if clock.hours < first_w else float(clock.days_per_season * 4) * 24.0)
	clock.forced = GameClock.Weather.CLEAR
	snow.set_cover(0.0)
	for i in 5:
		await get_tree().process_frame
	print("Winter load: back in ", GameClock.SEASON_NAMES[clock.season()], ", pinned ", clock.forced, ", snow ", snappedf(snow.cover, 0.01))
	clock.hours += 5.0
	for i in 5:
		await get_tree().process_frame
	print("Winter load: 5 h on, ", GameClock.SEASON_NAMES[clock.season()], " day ", clock.day_of_season(), ", weather ", GameClock.WEATHER_NAMES[clock.weather()], ", pinned ", clock.forced, ", snow ", snappedf(snow.cover, 0.01))
