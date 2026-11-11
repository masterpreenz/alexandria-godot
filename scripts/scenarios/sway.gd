extends Scenario
## Among trees by day: two pictures 0.6 s apart (the sway), then one as a wind gust passes.
## Run with --window=sway.


func run() -> void:
	clock.hours = 12.0
	miko.place(miko.position + Vector2(float(Shots.arg("dx", "0")), float(Shots.arg("dy", "0"))) * world.px)
	for i in 30:
		await get_tree().process_frame
	var base := Shots.arg("shot").get_basename()
	get_viewport().get_texture().get_image().save_png(base + "_a.png")
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 600:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(base + "_b.png")
	var ws: WorldSounds = world.get_node("WorldSounds")
	ws.gust_now()
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(ws._gust_length * 450.0):
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(base + "_gust.png")
