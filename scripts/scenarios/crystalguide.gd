extends Scenario
## After the opening, the story waits unseen (no card) till Miyu's home; then the starter guide's crystal step: place a
## Cleansing Crystal (she's given the crystals and wood for one). Run with --window=crystalguide --slot=new.


func run() -> void:
	var st: Story = g.get_node("Story")
	for i in 20:
		await get_tree().process_frame
	while str(st._beats()[st.beat].id) != "until_miyu":
		st._begin(st.beat + 1, false)
		await get_tree().process_frame
	for i in 5:
		await get_tree().process_frame
	print("Crystal guide: waiting, card shown ", st._card.visible, ", clock running ", clock.speed > 0.0)
	Chronicle.active.record("miyu_home")
	for i in 5:
		await get_tree().process_frame
	print("Crystal guide: Miyu home, beat ", st._beats()[st.beat].id, ", card ", st._title.text, " shown ", st._card.visible, "; crystals ", miko.bag.count("Crystal"))
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_card.png")
	world.props.place(world.floors.cell_at(miko.position) + Vector2i(3, 0), "CleansingCrystal")
	for i in 10:
		await get_tree().process_frame
	print("Crystal guide: placed, story over ", st.beat < 0)
