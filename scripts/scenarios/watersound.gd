extends Scenario
## A villager sent to water a dry field: the watering sound while they're at it.
## Run with --window=watersound.


func run() -> void:
	var fm: Farming = miko.get_node("Farming")
	print("Watering sound: ", snappedf(Sfx.stream(Farming.WATER_SOUND).get_length(), 0.01), " s")
	var c0 := world.floors.cell_at(miko.position) + Vector2i(1, -1)
	world.props.place(c0, "FarmPlot")
	for i in 3:
		await get_tree().process_frame
	var pl: Dictionary = fm.plots.filter(func(q): return world.floors.cell_at(q.pos) == c0)[0]
	fm.sow(pl, "Potato")
	fm._state(pl).wateredAt = -1000.0
	clock.hours = float(clock.day() - 1) * 24.0 + 10.0
	while Villager.all.is_empty():
		await get_tree().process_frame
	var v: Villager = Villager.all[0]
	v.position = pl.pos + Vector2(1.5, 0.5) * world.px
	v.carrying = 0
	v.farm_task = "water"
	v.planting = false
	v._go_to_plot(pl)
	var sounds := 0
	var was := -1.0
	for i in 900:
		await get_tree().process_frame
		if v.state == Villager.State.FARM and v._next_till != was:
			was = v._next_till
			sounds += 1
		if not fm.dry(pl):
			break
	print("Watering: watered ", not fm.dry(pl), ", sounds while at it ", sounds)
