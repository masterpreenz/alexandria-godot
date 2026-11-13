extends Scenario
## The forest rumor's marker: in F6, the section it names, not over the line in F7. Heard afresh, and as an older
## game had it (its place found just outside F6): found again in F6. Run with --window=forestmark.


func run() -> void:
	for i in 30:
		await get_tree().process_frame
	var r := Rumors.active
	var cr := MapMarks.section_of("F6")
	var f6 := MapMarks.section_bounds(int(cr[0]), int(cr[1]))
	r.heard.erase("forest_clearing")
	r.offers["forest_clearing"] = Villager.all[0].person.name
	r.hear("forest_clearing", Villager.all[0])
	var st: Dictionary = r.heard.forest_clearing
	st.tracked = true
	var at := r.place_of(st, r.by_id.forest_clearing, 0)
	var m: Array = r.marks().filter(func(x): return x.id == "forest_clearing")
	print("Forest mark: F6 ", f6, ", place ", world.floors.cell_at(at), " in F6 ", f6.has_point(world.floors.cell_at(at)), ", ring at ", world.floors.cell_at(m[0].at), " in F6 ", f6.has_point(world.floors.cell_at(m[0].at)))
	# As an older game had it: just over the line.
	var outside := world.floors.cell_centre(Vector2i(f6.position.x - 3, f6.position.y + 4))
	st.places["find"] = [outside.x, outside.y]
	r._placed_again = false
	for i in 90:
		await get_tree().process_frame
	var wm: WorldMap = get_tree().root.find_children("*", "WorldMap", true, false)[0]
	wm.open()
	for i in 10:
		await get_tree().process_frame
	at = r.place_of(st, r.by_id.forest_clearing, 0)
	print("Forest mark: an older game's place found again ", world.floors.cell_at(at), " in F6 ", f6.has_point(world.floors.cell_at(at)))
	var m2: Array = r.marks().filter(func(x): return x.id == "forest_clearing")
	print("Forest mark: ring at ", world.floors.cell_at(m2[0].at), " radius ", m2[0].radius / world.px)
	for i in 20:
		await get_tree().process_frame
	shot("map")
