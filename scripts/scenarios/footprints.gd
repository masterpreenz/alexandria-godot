extends Scenario
## Deep winter: Miko walked across the snow, her prints behind her.
## Run with --window=footprints.


func run() -> void:
	clock.hours = float(clock.days_per_season * ((GameClock.Season.WINTER - clock.start_season + 4) % 4) + 2) * 24.0 + 9.0
	snow._last_hours = -1.0
	var from := world.village.centre() + Vector2(6.0, 5.0) * world.px
	miko.place(from)
	for i in 20:
		await get_tree().process_frame
	for i in 120:
		miko.position = from + Vector2(i * 0.03, sin(i * 0.05) * 0.4) * world.px
		await get_tree().process_frame
	var fp: SnowFootprints = world.find_child("SnowFootprints", true, false)
	print("Footprints: ", fp._prints.size(), " pressed, snow under her ", snow.ground_snow(miko.position))
	# Far more than the most there may be, quickly: none may blink out (showing one frame, gone the next).
	var was := {}
	var blinks := 0
	var most_seen := 0
	for i in 700:
		fp._press(from + Vector2(fmod(i * 0.07, 12.0), 0.3 * floorf(i / 170.0)) * world.px, Vector2.RIGHT)
		if i % 2 == 0:
			await get_tree().process_frame
			most_seen = maxi(most_seen, fp._prints.size())
			for c in fp.get_children():
				var a_now: float = c.modulate.a if c.visible else 0.0
				if float(was.get(c, 0.0)) > 0.25 and a_now < 0.05:
					blinks += 1
				was[c] = a_now
	print("Footprints: 700 pressed fast: most at once ", most_seen, " (the most kept ", SnowFootprints.MOST, ", a fifth over ", int(SnowFootprints.MOST * 1.2), "), blinked out ", blinks, ", sprites made ", fp.get_child_count())
	for i in 60:
		await get_tree().process_frame
	print("Footprints: a second on: ", fp._prints.size(), " lying, ", fp._spare.size(), " spare")
	camera.zoom *= 1.5
	for i in 5:
		await get_tree().process_frame
