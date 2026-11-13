extends Scenario
## The build bar's pictures: each prop and wall shown as it's built (its placed frame), a picture per tab.
## Run with --window=buildthumbs.


func run() -> void:
	for i in 20:
		await get_tree().process_frame
	var build: BuildMode = BuildMode.active
	build.set_open(true)
	var bar: BuildBar = g.find_children("*", "BuildBar", true, false)[0]
	var off := 0
	for it in build.items:
		if (it.kind == "Prop" or it.kind == "Wall") and it.get("icon") is Dictionary:
			off += 1
	print("Build thumbs: props and walls still on a separate picture ", off)
	for c in ["Comfort", "Walls", "Decor", "Light"]:
		bar._pick_category(c)
		for i in 10:
			await get_tree().process_frame
		shot(c)
	build.set_open(false)
