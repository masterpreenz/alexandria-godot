extends Scenario
## Long lines in villagers' bubbles go on to more lines (the bubble taller), not out wide: a raid's alarm, and something
## said. Run with --window=barkwrap.


func run() -> void:
	while Villager.all.size() < 2:
		await get_tree().process_frame
	clock.hours = float(clock.day()) * 24.0 + 12.0
	var a: Villager = Villager.all[0]
	var b: Villager = Villager.all[1]
	b.position = a.position + Vector2(4.0, 0.0) * world.px
	miko.place(a.position + Vector2(2.0, 2.5) * world.px)
	for i in 10:
		await get_tree().process_frame
	a.bark("bark.raid", {"side": "south-west"}, true)
	b._bark_any = 0.0
	b._bark_next = 0.0
	if b._bark == null:
		b._bark = SpeechBubble.new()
		b.add_child(b._bark)
	b._bark.say("The well's run dry again and the crops won't wait for the rain to come back to us.", SpeechBubble.Kind.SAY)
	b._bark.visible = true
	b._bark_until = Villager.now() + 5.0
	for i in 20:
		await get_tree().process_frame
	print("Bark wrap: lines ", a._bark._lines, " / ", b._bark._lines)
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_barks.png")
