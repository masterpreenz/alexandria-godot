extends Scenario
## In a story scene, the talk window's portrait and name follow whoever's speaking: Taro's face on his lines, Sera's
## own portrait on hers. Run with --window=talkfaces --slot=new.


func run() -> void:
	var st: Story = g.get_node("Story")
	for i in 20:
		await get_tree().process_frame
	while str(st._beats()[st.beat].id) != "messenger":
		st._begin(st.beat + 1, false)
		await get_tree().process_frame
	var talk: Talk = g.get_node("Hud/Talk")
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 15000 and not talk.visible:
		await get_tree().process_frame
	var seen := []
	var sera_face := HudStyle.icon("portrait")
	while talk.visible and not talk._acts.is_empty() and seen.size() < 6:
		seen.append("%s(%s)" % [talk._name.text, "her portrait" if talk._face.texture == sera_face else ("a face" if talk._face.texture != null else "none")])
		if talk._name.text == Miko.NAME and not FileAccess.file_exists(Shots.arg("shot").get_basename() + "_sera.png"):
			get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_sera.png")
		(talk._acts[0] as Callable).call()
		await get_tree().process_frame
	print("Talk faces: ", seen)
