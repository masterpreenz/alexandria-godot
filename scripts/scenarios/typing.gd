extends Scenario
## Talk lines type out a letter at a time with a blip in the speaker's voice; the first press while it's typing shows
## the rest, the next goes on. Run with --window=typing --slot=new.


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
	var steps := []
	for i in 12:
		steps.append(talk._line.visible_characters)
		await get_tree().process_frame
	print("Typing: letters shown frame by frame ", steps, " of ", talk._line.text.length(), "; voice ", "pitch %.2f" % talk._voice, ", blips playing ", talk._blip != null)
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_typing.png")
	var line0: String = talk._line.text
	talk._act_or_finish(talk._acts[0])
	print("Typing: first press shows it all ", talk._line.visible_characters == -1, ", same line ", talk._line.text == line0)
	talk._act_or_finish(talk._acts[0])
	await get_tree().process_frame
	print("Typing: second press goes on: ", talk._name.text, " says '", talk._line.text.left(30), "', voice ", "pitch %.2f" % talk._voice)
