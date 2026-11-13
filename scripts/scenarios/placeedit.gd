extends Scenario
## The place editor (F7): build mode free (nothing paid, nothing ruled out), the places' list, going to one (its area
## picked), something placed there for free, and saved back (to a test name, removed after). Run with --window=placeedit.


func run() -> void:
	for i in 20:
		await get_tree().process_frame
	var build: BuildMode = BuildMode.active
	print("Place edit: allowed ", BuildMode.dev_allowed())
	build.toggle_dev()
	for i in 10:
		await get_tree().process_frame
	build.go_to_place("wayside_well")
	for i in 30:
		await get_tree().process_frame
	shot("editor")
	# A bookshelf out in the wilds (indoors only, usually) and a lamp, paid for by nobody.
	var wood_before := build.world.village.have(miko.bag, miko, "Wood")
	var c := build.area.position + Vector2i(1, 1)
	build.select(build.item_for("Prop", "Bookshelf"))
	print("Place edit: why not a bookshelf out here ", "'" + build.why_not(build.selected, world.floors.cell_centre(c)) + "'", ", status ", build.status_of(build.selected))
	build._place_prop(c, 1.0)
	build.select(build.item_for("Prop", "StreetLamp"))
	build._place_prop(c + Vector2i(5, 3), 1.0)
	print("Place edit: placed ", world.props.get_prop(c, 1), " and ", world.props.get_prop(c + Vector2i(5, 3), 1), ", wood before ", wood_before, " after ", build.world.village.have(miko.bag, miko, "Wood"))
	var ok := build.save_area("zz_place_edit_test")
	var t := VillageTemplate.load_named("zz_place_edit_test")
	print("Place edit: saved ", ok, ", area ", build.area, ", kept addToSaves ", t.get("addToSaves", "-"), " clear ", t.get("clear", "-"),
		", props ", t.props.map(func(r): return r.type))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(VillageTemplate.path_of("zz_place_edit_test")))
	# Saved over a place that has walls taken out (a copy of the west village): they stay listed as gone, and what it
	# says beyond what's built is kept.
	DirAccess.copy_absolute(ProjectSettings.globalize_path(VillageTemplate.path_of("west_village")), ProjectSettings.globalize_path(VillageTemplate.path_of("zz_place_edit_test")))
	build.go_to_place("zz_place_edit_test")
	var w_ok := build.save_area("zz_place_edit_test")
	var wt := VillageTemplate.load_named("zz_place_edit_test")
	print("Place edit: the west village saved again ", w_ok, ": gone walls kept ", wt.walls.filter(func(r): return bool(r.get("gone", false))).size(), " (the original has ",
		VillageTemplate.load_named("west_village").walls.filter(func(r): return bool(r.get("gone", false))).size(), "), added to saves ", wt.get("addToSaves", "-"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(VillageTemplate.path_of("zz_place_edit_test")))
	build.toggle_dev()
	print("Place edit: off again ", not BuildMode.dev, ", status of a bookshelf ", build.status_of(build.item_for("Prop", "WideBookshelf")))
