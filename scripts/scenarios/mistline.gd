extends Scenario
## Setting off for the village with the mist in: Sera says "Oh no! The mist is already here." once she's walked a few
## steps. Run with --window=mistline --slot=new.


func run() -> void:
	var st: Story = g.get_node("Story")
	for i in 20:
		await get_tree().process_frame
	Chronicle.active.record("scene:messenger")
	while str(st._beats()[st.beat].id) != "rush":
		st._begin(st.beat + 1, false)
		await get_tree().process_frame
	var nd: Needs = miko.get_node("Needs")
	var before := nd._bubble_label != null and nd._bubble_label.visible
	for i in 30:
		miko.place(miko.position + Vector2(-0.1, 0.05) * world.px)
		await get_tree().process_frame
	var shown := nd._bubble_label != null and nd._bubble_label.visible
	print("Mist line: before walking ", before, "; after ", shown, " '", nd._bubble_label.text if nd._bubble_label != null else "", "'")
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_line.png")
