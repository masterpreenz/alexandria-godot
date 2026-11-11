extends Scenario
## Hurt and short of mana: the bars over her head; then full again: gone.
## Run with --window=headbars.


func run() -> void:
	miko.stats.damage(40.0)
	miko.stats.spend_mana(30.0)
	camera.zoom *= 1.6
	for i in 30:
		await get_tree().process_frame
	var hb: HeadBars = miko.get_node("HeadBars")
	print("Head bars: showing hurt ", hb.visible)
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_hurt.png")
	miko.stats.hp = miko.stats.stat("maxHp")
	miko.stats.mana = miko.stats.stat("maxMana")
	for i in 400:
		await get_tree().process_frame
	print("Head bars: showing when full ", hb.visible)
