extends Scenario
## Making camp: the build menu offers only the Bonfire and the Leaf Bed; afterwards, everything again.
## Run with --window=campbuild --slot=new.


func run() -> void:
	var st: Story = g.get_node("Story")
	for i in 20:
		await get_tree().process_frame
	while str(st._beats()[st.beat].id) != "camp":
		st._begin(st.beat + 1, false)
		await get_tree().process_frame
	var bm := BuildMode.active
	bm.set_open(true)
	for i in 10:
		await get_tree().process_frame
	var bar: BuildBar = g.get_node("Hud/BuildBar")
	var tiles: Array = bar._items.get_children().map(func(t): return str(t.item.name))
	print("Camp build: tabs ", bar._categories(), ", tiles ", tiles)
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_camp.png")
	st._begin(st.beat + 1, false)
	for i in 10:
		await get_tree().process_frame
	print("Camp build: after it, tabs ", bar._categories().size())
