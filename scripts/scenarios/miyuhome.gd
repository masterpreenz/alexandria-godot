extends Scenario
## Miyu brought home: carried into the village (the elder marked), his scene (it closes by itself), then on to a bed in
## the elders' house, and laid in it (E): she lives there now, asleep. Run with --window=miyuhome --slot=new (the
## opening skipped through to its end).


func run() -> void:
	for i in 30:
		await get_tree().process_frame
	var st: Story = g.get_node("Story")
	for e in ["village_warded", "scene:messenger", "scene:aftermath", "intro_fed", "scene:food_given", "scene:peculiar"]:
		Chronicle.active.record(e)
	while str(st._beats()[st.beat].id) != "until_miyu":
		st._begin(st.beat + 1, false)
		await get_tree().process_frame
	st._release()
	for i in 200:
		if not miko.locked:
			break
		await get_tree().process_frame
	miko.locked = false
	var ch := Chronicle.active
	var rescue: Rescue = Rescue.active
	# Heard, found, picked up: she's in Sera's arms, out past the village.
	Rumors.active.heard.erase("find_miyu")
	Rumors.active.offers["find_miyu"] = "x"
	Rumors.active.hear("find_miyu", Villager.all[0])
	Rumors.active.heard["find_miyu"].step = 1
	rescue.state = "carried"
	rescue._carry(false)
	miko.place(world.village.centre() + Vector2(0, 30) * world.px)
	for i in 10:
		await get_tree().process_frame
	print("Miyu home: carried ", rescue.state, ", told the elder yet ", ch.happened("miyu_carried_home"))
	# Into the village.
	var elder: Villager = null
	for v in Villager.all:
		if is_instance_valid(v) and str(v.person.get("unique", "")) == "elder":
			elder = v
	miko.place(elder.position + Vector2(0.7, 0.3) * world.px)
	for i in 10:
		await get_tree().process_frame
	print("Miyu home: in the village, to the elder ", ch.happened("miyu_carried_home"), ", elder marked ", Story.active._marks.uniques.has("elder"), ", his scene waiting ", Scenes.for_speaker(elder.person).get("id", ""))
	shot("to_elder")
	var talk: Talk = g.get_node("Hud/Talk")
	talk.open(elder)
	var said := []
	for i in 30:
		await get_tree().process_frame
		if not talk.visible:
			break
		talk._finish_typing()
		said.append(talk._line.text.left(30))
		if not talk._acts.is_empty():
			talk._act_or_finish(talk._acts[0])
	print("Miyu home: his scene ", said.size(), " lines, talk closed by itself ", not talk.visible, ", told ", ch.happened("miyu_told"))
	for i in 5:
		await get_tree().process_frame
	print("Miyu home: on to a bed ", rescue.state, " at ", rescue.bed, " (", snappedf(rescue.bed.distance_to(elder.position) / world.px, 0.1), " units from him)" if rescue.bed != Vector2.INF else "")
	if rescue.bed == Vector2.INF:
		return
	miko.place(rescue.bed + Vector2(0.6, 0.4) * world.px)
	for i in 10:
		await get_tree().process_frame
	print("Miyu home: by the bed, prompt '", rescue.prompt.text, "' showing ", rescue.prompt.visible)
	shot("by_bed")
	rescue._pressed = true
	for i in 20:
		await get_tree().process_frame
	var miyu: Villager = null
	for v in Villager.all:
		if is_instance_valid(v) and str(v.person.get("unique", "")) == "miyu":
			miyu = v
	print("Miyu home: laid down ", rescue.state, ", home ", ch.happened("miyu_home"), "; Miyu ", "there" if miyu != null else "missing",
		(", in bed %s, asleep %s, %.1f units from the bed" % [miyu.in_bed, miyu.state == Villager.State.ASLEEP, miyu.home.pos.distance_to(rescue._bed_entry(miyu.home.pos).get("pos", Vector2.ZERO)) / world.px]) if miyu != null and not miyu.home.is_empty() else "")
	if miyu != null:
		print("Miyu home: her id ", miyu.get_instance_id(), " state ", Villager.State.keys()[miyu.state], ", visible ", miyu.visible, ", hour ", snappedf(world.clock.hour(), 0.1), ", rest until ", snappedf(float(miyu.person.get("restUntil", -1)) - world.clock.hours, 0.1), " h more")
		for i in 240:
			await get_tree().process_frame
		print("Miyu home: 4 s on, ", Villager.State.keys()[miyu.state], ", in bed ", miyu.in_bed, ", held ", miyu.held, ", process ", miyu.is_physics_processing(), ", state until ", snappedf(miyu.state_until - Villager.now(), 0.1))
	shot("in_bed")
