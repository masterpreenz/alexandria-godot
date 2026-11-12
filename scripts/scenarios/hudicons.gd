extends Scenario
## The Build and Bag buttons beside the hotbar, with their own pictures (assets/Icons/UI); no Character button.
## Run with --window=hudicons.


func run() -> void:
	for i in 10:
		await get_tree().process_frame
	var names := []
	for b in g.find_children("*", "Button", true, false):
		if b.get("icon_name") != null:
			names.append(str(b.get("icon_name")))
	print("HUD icons: quick buttons ", names)
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_hud.png")
