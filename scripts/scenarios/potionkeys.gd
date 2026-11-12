extends Scenario
## The potion slots beside the hotbar: Q drinks an HP potion, R a mana potion, each slot showing how many are left.
## Run with --window=potionkeys --slot=new.


func _key(k: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.pressed = true
	get_viewport().push_input(e)
	await get_tree().process_frame
	var up := InputEventKey.new()
	up.keycode = k
	up.pressed = false
	get_viewport().push_input(up)
	await get_tree().process_frame


func run() -> void:
	for i in 20:
		await get_tree().process_frame
	miko.stats.hp = 30.0
	miko.stats.mana = 10.0
	await _key(KEY_Q)
	await _key(KEY_R)
	print("Potion keys: after Q and R, HP ", roundi(miko.stats.hp), ", mana ", roundi(miko.stats.mana), "; left ", miko.bag.count("HpPotion"), " HP, ", miko.bag.count("ManaPotion"), " mana")
	for i in 5:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_bar.png")
