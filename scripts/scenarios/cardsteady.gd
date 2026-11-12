extends Scenario
## The starter guide's card over Sera holds steady: how far it moves frame to frame while she walks and swings her
## staff (a few px at most), against how far her sprite's top bobs. Run with --window=cardsteady --slot=new.


func run() -> void:
	var st: Story = g.get_node("Story")
	for i in 30:
		await get_tree().process_frame
	var m: Melee = null
	for n in g.find_children("*", "Melee", true, false):
		m = n
	var last := st._card.position
	var worst := 0.0
	var moved := []
	for i in 180:
		miko.place(miko.position + Vector2(0.05, -0.03) * world.px)
		if i % 30 == 0 and m._can_swing():
			m._swing(get_viewport().get_visible_rect().get_center() + Vector2(60, 0))
		await get_tree().process_frame
		var d := st._card.position.distance_to(last)
		worst = maxf(worst, d)
		moved.append(d)
		last = st._card.position
	moved.sort()
	print("Card steady: biggest step ", snappedf(worst, 0.1), " px, typical ", snappedf(moved[int(moved.size() / 2.0)], 0.1), " px")
