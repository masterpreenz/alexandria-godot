extends Scenario
## The "plant" scenario.
## Run with --window=plant.


func run() -> void:
	var tp: TreePlanter = miko.get_node("TreePlanter")
	miko.bag.add("Seed", 3)
	miko.facing_right = true
	miko.facing_up = false
	var spot := miko.position + Vector2(2.0, 1.0) * world.px
	print("Plant here? '", tp.why_not(spot), "'")
	var sapling := tp.plant_at(spot)
	print("Planted: sapling ", sapling.sapling(), " depleted ", sapling.depleted(), " scale ", sapling.art.scale, " next in ", sapling.hours_to_next(), "h")
	clock.hours += 10.0
	sapling._grow_up()
	print("After 10h: sapling ", sapling.sapling(), " wood ", sapling.left, " scale ", sapling.art.scale, " next in ", sapling.hours_to_next(), "h")
	clock.hours += 20.0
	sapling._grow_up()
	print("After 30h: wood ", sapling.left, " scale ", sapling.art.scale, " next in ", sapling.hours_to_next(), "h; saved ", miko.get_node("TreePlanter").to_json().left(120))
	print("Sleep villagers alpha: ", Villager.all.map(func(v): return [v.in_bed, snappedf(v.modulate.a, 0.01)]))
