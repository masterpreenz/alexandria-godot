extends Scenario
## The gear with the user's icons, in her bag: staff, necklaces, charm, wand, shield, robe, gloves, pants.
## Run with --window=gearicons --slot=new.


func run() -> void:
	for i in 20:
		await get_tree().process_frame
	var missing := []
	for it in ["Tools", "Mug", "Bucket", "CrystalNecklace", "ShrineCharm", "OakWand", "WoodenShield", "LinenRobe", "ClothGloves", "ClothPants"]:
		var slot := miko.bag.free_slot()
		if slot >= 0:
			miko.bag.items[slot] = it
		if UiKit.item_icon(it) == null:
			missing.append(it)
	miko.bag.add("Crystal", 3)
	print("Gear icons: without a picture ", missing)
	var cp: CharacterPanel = CharacterPanel._active
	cp.toggle()
	for i in 5:
		await get_tree().process_frame
	cp.clicked(4, false)   # (the first bit of gear picked: its picture in the box below)
	for i in 10:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_bag.png")
