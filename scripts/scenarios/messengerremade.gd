extends Scenario
## The messenger running to Sera's camp is remade on the way (given his bed: a new node for him): he's found again and
## still comes, and his news opens. Run with --window=messengerremade --slot=new.


func run() -> void:
	var st: Story = g.get_node("Story")
	for i in 20:
		await get_tree().process_frame
	while str(st._beats()[st.beat].id) != "messenger":
		st._begin(st.beat + 1, false)
		await get_tree().process_frame
	for i in 20:
		await get_tree().process_frame
	# His node gone from under the story, as when he's given his bed.
	var old: Villager = st._messenger_v
	print("Messenger remade: on his way ", old != null)
	if old != null:
		old.move_out()
	var talk: Talk = g.get_node("Hud/Talk")
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 15000 and not talk.visible:
		await get_tree().process_frame
	print("Messenger remade: his news opened ", talk.visible, " after ", snappedf((Time.get_ticks_msec() - t0) / 1000.0, 0.1), "s; by ", talk._name.text)
