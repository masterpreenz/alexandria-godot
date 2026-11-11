extends Scenario
## A villager and a slime beside Miko, both hit: shot mid-flinch (red, jolted).
## Run with --window=hitfx.


func run() -> void:
	while Villager.all.is_empty():
		await get_tree().process_frame
	var v: Villager = Villager.all[0]
	v.position = miko.position + Vector2(-1.2, -0.3) * world.px
	var md: Dictionary = world._load_json("res://data/monsters.json")
	var sl: Slime = Slime.spawn(world, md.slime, false, miko.position + Vector2(1.2, -0.3) * world.px, 1.0)
	camera.zoom *= 1.6
	for i in 10:
		await get_tree().process_frame
	v.hit.hurt(3.0)
	sl.hit.hurt(3.0)
	for i in 4:
		await get_tree().process_frame
	print("Hit fx: villager tint ", v.art.self_modulate, ", jolt ", v.get_node("Wading").extra, "; slime tint ", sl.art.self_modulate)
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_hit.png")
	for i in 40:
		await get_tree().process_frame
	print("Hit fx after: villager tint ", v.art.self_modulate, ", jolt ", v.get_node("Wading").extra)
