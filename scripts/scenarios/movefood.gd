extends Scenario
## A cellar built with 150 food up in the chests: the villagers carry it down, load by load.
## Run with --window=movefood.


func run() -> void:
	var cl: Cellars = g.get_node("Cellars")
	var v := world.village
	for r in Spoilage.PER_DAY:
		v.stash[r] = 0
	v.stash["Potato"] = 100
	v.stash["BakedPotato"] = 50
	clock.forced = GameClock.Weather.CLEAR
	clock.hours = float(clock.day() - 1) * 24.0 + 9.0
	for vl in Villager.all:
		vl.person.hunger = 100.0
	world.props.place(world.floors.cell_at(v.centre()) + Vector2i(4, -5), "Cellar", 1.0, 0)
	for i in 5:
		await get_tree().process_frame
	print("Move food: cellar holds ", cl.holds(), ", food ", cl.food_stored(), ", cold ", cl.cold, ", to move ", cl.to_move(), ", cold share ", cl.cold_share())
	var t0 := Time.get_ticks_msec()
	var last := -1
	while Time.get_ticks_msec() - t0 < int(Shots.arg("moveseconds", "100")) * 1000 and cl.to_move() > 0:
		await get_tree().process_frame
		if cl.cold != last:
			last = cl.cold
			var dn := world.props.node_at(world.floors.cell_at(v.centre()) + Vector2i(4, -5), 1)
			print("  doors open ", cl._open_until.size(), ", art ", world.sprites[int((dn.get_child(0) as Sprite2D).get_meta("sprite", 0))].name if dn != null else "no node")
			print("Move food ", floori((Time.get_ticks_msec() - t0) / 1000.0), " s: cold ", cl.cold, " of ", cl.holds(), ", movers ", Cellars.movers.keys().map(func(q): return q.person.name + " " + q.activity()))
	print("Move food end: cold ", cl.cold, ", food still ", cl.food_stored(), ", cold share ", snappedf(cl.cold_share(), 0.01), ", saved ", cl.to_json())
