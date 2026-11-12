extends Scenario
## The map's still things off screen are hidden by square, shown again as they come into sight: walking along, pictures
## of what's in view (nothing should be missing); the world map shows everything. Run with --window=culling.


func run() -> void:
	clock.hours = float(clock.day()) * 24.0 + 12.0
	for i in 30:
		await get_tree().process_frame
	var hidden := 0
	var total := 0
	for k in Culler._squares:
		for n in Culler._squares[k]:
			if is_instance_valid(n):
				total += 1
				if not n.visible: hidden += 1
	print("Culling: ", hidden, " of ", total, " still things hidden now")
	# A fast walk across: anything in view hidden?
	var missing := 0
	for step in 40:
		miko.place(miko.position + Vector2(-1.5, 0.6) * world.px)
		for i in 3:
			await get_tree().process_frame
		var view := world.view_rect()
		for k in Culler._squares:
			for n in Culler._squares[k]:
				if is_instance_valid(n) and not n.visible and view.has_point((n as Node2D).global_position):
					missing += 1
	print("Culling: things in view found hidden while walking (over 40 steps) ", missing)
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_walk.png")
	var wm := g.find_children("*", "WorldMap", true, false)
	if not wm.is_empty():
		wm[0].open()
		var all_on := true
		for k in Culler._squares:
			for n in Culler._squares[k]:
				if is_instance_valid(n) and not n.visible: all_on = false
		print("Culling: world map open, everything shown ", all_on)
		wm[0].close()
