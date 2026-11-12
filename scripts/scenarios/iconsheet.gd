extends Scenario
## Saves the icons still standing in for real art (PLACEHOLDER_ART.md) as pictures, for the sheets of them.
## Run with --window=iconsheet --out=<folder>.


func _save(tex: Texture2D, nm: String) -> void:
	var out := Shots.arg("out")
	if tex == null:
		print("Icons: none for ", nm)
		return
	tex.get_image().save_png(out.path_join(nm + ".png"))


func run() -> void:
	await get_tree().process_frame
	for r in ["Crystal", "Candy", "Hide", "Rabbit", "Bottle", "HpPotion", "ManaPotion", "Carrot", "Cabbage", "Wheat", "Cotton",
			"CabbageSeed", "WheatSeed", "CottonSeed", "Flour", "Bread", "CarrotStew", "CabbageSoup", "Fiber", "Fish", "GrilledFish",
			"Bait", "SmokedFish", "FishSoup", "FishStew", "Water"]:
		_save(UiKit.resource_icon(r), r)
	for it in ["Mug", "Bucket", "WaterPouch"]:
		_save(UiKit.item_icon(it), it)
	for h in ["build", "bagButton", "characterButton"]:
		_save(HudStyle.icon(h), "hud_" + h)
	for b in (world._load_json("res://data/build.json").catalog as Array):
		if str(b.name) in ["Fence", "RabbitPen", "FarmPlot"]:
			_save(UiKit.sprite_texture(int(b.get("icon", -1))), "build_" + str(b.name))
	print("Icons: saved")
