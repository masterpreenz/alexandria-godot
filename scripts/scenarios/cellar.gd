extends Scenario
## A cellar put in a house: what it keeps cold, what spoils with and without it; down and back up.
## Run with --window=cellar.


func run() -> void:
	var cl: Cellars = g.get_node("Cellars")
	var v := world.village
	for r in Spoilage.PER_DAY:
		v.stash[r] = 0
	v.stash["Food"] = 80
	v.stash["Potato"] = 120
	print("Cellar: none yet, cold share ", cl.cold_share())
	var spot := world.floors.cell_at(v.centre()) + Vector2i(4, -5)
	world.props.place(spot, "Cellar", 1.0, 0)
	world.props.place(spot + Vector2i(4, 0), "Cellar", 1.0, 1)
	for i in 5:
		await get_tree().process_frame
	print("Cellar: one built, holds ", cl.holds(), " of 200 food: cold share ", cl.cold_share(), " (storage's food spoils at ", snappedf(1.0 - cl.cold_share() * (1.0 - Cellars.COLD_RATE), 0.01), " of the usual)")
	miko.place(world.floors.cell_centre(spot) + Vector2(2.0, 1.2) * world.px)
	miko.position = world.floors.cell_centre(spot) + Vector2(0.4, 1.3) * world.px
	for i in 30:
		await get_tree().process_frame
	print("Cellar: prompt '", cl.prompt.text, "' showing ", cl.prompt.visible)
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_door.png")
	cl._came_from = world.floors.cell_centre(spot)
	cl._go(true)
	for i in 90:
		await get_tree().process_frame
	print("Cellar: down there ", Cellars.inside(miko.position), ", mist ", world.mist.tier_at(miko.position))
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_down.png")
	miko.place(world.floors.cell_centre(cl._door_cell() + Vector2i(0, -1)))
	for i in 120:
		await get_tree().process_frame
	var vl: Villager = Villager.all[0]
	# A villager with potatoes: to the doors, down, and up again with them put away.
	clock.hours = float(clock.day() - 1) * 24.0 + 10.0
	vl.position = world.floors.cell_centre(spot) + Vector2(0.5, 2.5) * world.px
	vl.carrying = 3
	vl.carry_kind = "Potato"
	var had := v.stored("Potato")
	vl._go_store()
	var went_down := false
	for i in 900:
		await get_tree().process_frame
		if vl.state == Villager.State.CELLAR and not went_down:
			went_down = true
			print("Cellar: villager down there, in the room ", Cellars.room_has(world.floors.cell_at(vl.position)), ", '", vl.activity(), "'")
		if went_down and vl.state != Villager.State.CELLAR:
			break
	print("Cellar: villager went down ", went_down, ", back up ", snappedf(vl.position.distance_to(world.floors.cell_centre(spot)) / world.px, 0.1), " units from the doors, potatoes ", had, " -> ", v.stored("Potato"))
	vl.person.hunger = 5.0
	print("Cellar: hungry, heads for the cellar ", vl._go_eat() and vl._via_cellar)
	vl.carrying = 3
	vl.carry_kind = "Potato"
	vl._go_store()
	var food_goes := vl.target.distance_to(world.floors.cell_centre(spot)) / world.px
	vl.carry_kind = "Wood"
	vl._go_store()
	print("Cellar: a villager with potatoes heads ", snappedf(food_goes, 0.1), " units from the trapdoor; with wood, ", snappedf(vl.target.distance_to(world.floors.cell_centre(spot)) / world.px, 0.1))
	vl.carrying = 0
	var bm := BuildMode.active
	var in_room := Cellars.AT + Vector2i(1, 3)
	print("Cellar: building down there: a chest '", bm.why_not(bm.item_for("Prop", "Chest"), world.floors.cell_centre(in_room)), "', a bed '", bm.why_not(bm.item_for("Prop", "WoodenBed"), world.floors.cell_centre(in_room)), "', in bounds ", world.floors.in_bounds(in_room), ", no-build ", bm.no_build(in_room))
	miko.place(world.floors.cell_centre(Cellars.AT + Vector2i(2, 2)))
	for i in 10:
		await get_tree().process_frame
	bm.set_open(true)
	bm.select(bm.item_for("Prop", "Chest"))
	# (the mouse over the room: is anything of the interface taken to be under it?)
	var on_screen := get_viewport().get_canvas_transform() * world.floors.cell_centre(in_room)
	Input.warp_mouse(on_screen)
	var motion := InputEventMouseMotion.new()
	motion.position = on_screen
	motion.global_position = on_screen
	get_viewport().push_input(motion)
	for i in 5:
		await get_tree().process_frame
	var hovered := get_viewport().gui_get_hovered_control()
	print("Cellar: under the mouse in the room: ", str(hovered.name) if hovered != null else "nothing", ", taken as interface ", bm._over_ui())
	# R, then placed: turned?
	var key := InputEventKey.new()
	key.keycode = KEY_R
	key.pressed = true
	var turn0 := bm.prop_turn
	bm._unhandled_input(key)
	bm._place_prop(in_room + Vector2i(2, 0), 1.0)
	var placed_e: Dictionary = world.props.cells.get(Vector3i(in_room.x + 2, in_room.y, 0), {})
	print("Cellar: R pressed, turn ", turn0, " -> ", bm.prop_turn, "; a chest placed then has turn ", placed_e.get("turn", "?"), ", shown mirrored ", not placed_e.is_empty() and world.props.shown_flipped(placed_e))
	bm._place_prop(in_room, 1.0)
	print("Cellar: through build mode, chest status ", bm.status_of(bm.item_for("Prop", "Chest")), ", placed ", world.props.get_prop(in_room, 0), "; a bed there says '", bm.why_not(bm.item_for("Prop", "WoodenBed"), world.floors.cell_centre(in_room + Vector2i(1, 0))), "'")
	bm.set_open(false)
	world.props.place(in_room, "Chest")
	print("Cellar: a chest placed down there ", world.props.get_prop(in_room, 0), "; the villagers' chest spot is in the room ", Cellars.room_has(world.floors.cell_at(UseSpots.nearest_chest_spot(world, v.centre()))))
	print("Cellar: back up, ", snappedf(miko.position.distance_to(world.floors.cell_centre(spot)) / world.px, 0.1), " units from the trapdoor")
