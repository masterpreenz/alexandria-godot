extends Scenario
## The story's card sits just over Sera's head, and its hint's parts light up as she does each (walk, then jump; run
## left undone). Run with --window=hints --slot=new.


func run() -> void:
	var st: Story = g.get_node("Story")
	for i in 30:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_start.png")
	for i in 3:
		miko.place(miko.position + Vector2(0, -0.6) * world.px)
		await get_tree().process_frame
	miko.jump()
	for i in 10:
		await get_tree().process_frame
	print("Hints: done ", st._did.keys(), "; card at ", st._card.position, " size ", st._card.size, "; text ", st._hint.text)
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_ticked.png")
