extends Scenario
## Miko beside a corrupted tree, which is struck: it blinks red and shakes.
## Run with --window=treehit.


func run() -> void:
	for i in 5:
		await get_tree().process_frame
	var cr := Corruption.active
	var tree: Gatherable = null
	for t in cr.corrupted:
		if is_instance_valid(t) and t.standing():
			tree = t
			break
	if tree == null:
		print("Tree hit: no corrupted tree")
	else:
		miko.place(tree.foot + Vector2(-0.8, 0.6) * world.px)
		for i in 300:
			await get_tree().process_frame
			if cr.armed.has(tree):
				break
		var dm: Damageable = cr.armed[tree][0] if cr.armed.has(tree) else null
		if dm != null:
			dm.hurt(2.0)
		for i in 4:
			await get_tree().process_frame
		print("Tree hit: armed ", dm != null, ", tint ", tree.art.self_modulate, ", shaken ", tree.art.position != tree._rest)
		get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_tree.png")
