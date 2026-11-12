extends Scenario
## After the fight, the elder is marked (a ring and an arrow) for the talk with the survivors, and the mark goes when
## that's done. Run with --window=eldermark --slot=new.


func run() -> void:
	var st: Story = g.get_node("Story")
	for i in 20:
		await get_tree().process_frame
	while str(st._beats()[st.beat].id) != "aftermath":
		st._begin(st.beat + 1, false)
		await get_tree().process_frame
	for i in 5:
		await get_tree().process_frame
	var elders := Villager.all.filter(func(v): return is_instance_valid(v) and str(v.person.get("unique", "")) == "elder")
	print("Elder mark: elders ", elders.map(func(v): return v.person.name), "; marked ", st._marks.marked.filter(func(n): return n is Villager).map(func(n): return n.person.name))
	if not elders.is_empty():
		miko.place(elders[0].position + Vector2(-3, 2) * world.px)
	for i in 10:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_elder.png")
