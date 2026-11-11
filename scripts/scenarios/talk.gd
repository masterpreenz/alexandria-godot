extends Scenario
## Beside a villager: the prompt, then talking (E): the panel; a reply (1); give food; bye.
## Run with --window=talk.


func run() -> void:
	while Villager.all.is_empty():
		await get_tree().process_frame
	var v: Villager = Villager.all[0]
	miko.place(v.position + Vector2(0.6, 0.3) * world.px)
	miko.bag.add("Bread", 2)
	v.person.hunger = 30.0
	for i in 10:
		await get_tree().process_frame
	var tk: Talk = g.get_node("Hud/Talk")
	print("Talk: prompt '", tk.prompt.text, "' shown ", tk.prompt.visible)
	tk.open(v)
	for i in 5:
		await get_tree().process_frame
	print("Talk: ", v.person.name, " says '", tk._line.text, "', replies ", tk._acts.size())
	(tk._acts[1] as Callable).call()
	print("Talk: after food '", tk._line.text, "', hunger ", v.person.hunger)
	print("Tail: visible ", tk._tail.visible, " from ", tk._tail.from, " tip ", tk._tail.tip, " panel ", tk.position, tk.size, " tail global ", tk._tail.global_position)
	for i in 8:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_panel.png")
	tk._say_bye()
	for i in 10:
		await get_tree().process_frame
	print("Talk: closed, speed ", Engine.time_scale, ", bark '", v._bark.text if v._bark else "", "'")
