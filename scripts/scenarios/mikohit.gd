extends Scenario
## Miko hit: mid-flinch, her tint and jolt (and a picture).
## Run with --window=mikohit.


func run() -> void:
	camera.zoom *= 1.8
	for i in 10:
		await get_tree().process_frame
	miko.stats.damage(10.0)
	for i in 5:
		await get_tree().process_frame
	print("Miko hit: tint ", miko.art.self_modulate, ", jolt ", miko.wading.extra, ", material ", miko.art.material)
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_hit.png")
