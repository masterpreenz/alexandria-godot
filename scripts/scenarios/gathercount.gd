extends Scenario
## The guide's gathering beat counts up: 0/10 wood, 0/5 stone, then 4/10 and 2/5 as she gathers.
## Run with --window=gathercount --slot=new.


func run() -> void:
	var st: Story = g.get_node("Story")
	for i in 20:
		await get_tree().process_frame
	while st.beat >= 0 and str(st._beats()[st.beat].id) != "gather":
		st._begin(st.beat + 1, false)
		await get_tree().process_frame
	await get_tree().process_frame
	print("Gather count: at the start ", st._hint.text)
	miko.bag.add("Wood", 4)
	miko.bag.add("Stone", 2)
	for i in 5:
		await get_tree().process_frame
	print("Gather count: after some ", st._hint.text)
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_count.png")
