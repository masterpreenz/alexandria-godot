extends Scenario
## A rabbit pen, demolished from a corner tile of it (not the middle one it stands on).
## Run with --window=penaway.


func run() -> void:
	for i in 5:
		await get_tree().process_frame
	var pc := world.floors.cell_at(miko.position) + Vector2i(3, 0)
	world.props.place(pc, "RabbitPen")
	var bm := BuildMode.active
	print("Pen: hover on its corner '", bm._demolish_hover(pc + Vector2i(1, 1), true).get("title", ""), "'")
	bm._clear_one(pc + Vector2i(1, 1))
	print("Pen: left after demolishing its corner ", world.props_named("RabbitPen").filter(func(p): return world.floors.cell_at(p) == pc).size())
