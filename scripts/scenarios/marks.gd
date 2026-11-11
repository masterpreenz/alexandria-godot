extends Scenario
## The story's first monsters are marked: a slime sent at Sera has its outline on and an arrow over it; one off the
## screen, an arrow at the edge pointing to it. Left click: one swing every 0.8s at most, a light knock.
## Run with --window=marks --slot=new.


func run() -> void:
	var st: Story = g.get_node("Story")
	for i in 30:
		await get_tree().process_frame
	# Walk: the slime comes.
	for i in 14:
		miko.place(miko.position + Vector2(0, -0.8) * world.px)
		await get_tree().process_frame
	for i in 30:
		await get_tree().process_frame
	print("Marks: marked ", st._marks.marked.size(), ", outline on ", st._marks.marked.map(func(c): return snappedf(c.outline.shown, 0.1)))
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_near.png")
	miko.place(miko.position + Vector2(14, 0) * world.px)
	for i in 30:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_off.png")
	# Left click spam: how many swings in two seconds.
	var m: Melee = null
	for n in g.find_children("*", "Melee", true, false):
		m = n
	var swings := 0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 2000:
		if m._can_swing():
			m._swing(get_viewport().get_visible_rect().get_center() + Vector2(40, 0))
			swings += 1
		await get_tree().process_frame
	print("Marks: swings in 2s clicking every frame ", swings, "; a knock does ", Melee.BASE_DAMAGE + miko.stats.stat("attack") * Melee.ATTACK_SHARE)
