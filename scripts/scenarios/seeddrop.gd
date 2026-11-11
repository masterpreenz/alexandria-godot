extends Scenario
## 40 slimes felled: how many dropped a seed, and which.
## Run with --window=seeddrop.


func run() -> void:
	var md: Dictionary = world._load_json("res://data/monsters.json")
	var before := world.get_children().filter(func(n): return n is Pickup).size()
	for i in 40:
		var sl: Slime = Slime.spawn(world, md.slime, false, miko.position + Vector2(6.0 + i * 0.1, 3.0) * world.px, 1.0)
		sl.hit.hurt(9999.0)
	for i in 5:
		await get_tree().process_frame
	var kinds := {}
	for n in get_tree().get_nodes_in_group("pickups") if get_tree().has_group("pickups") else []:
		kinds[n.resource] = int(kinds.get(n.resource, 0)) + 1
	var found := {}
	for n in world.find_children("*", "Pickup", true, false):
		found[str(n.get("resource"))] = int(found.get(str(n.get("resource")), 0)) + 1
	print("Seed drops from 40 slimes (", before, " pickups before): ", found)
	var vs: Villagers = g.find_child("Villagers", true, false)
	for i in 300:
		await get_tree().process_frame
	print("Villagers: up to ", vs.s.newcomersUpTo, " newcomers; here now ", vs.people.map(func(q): return "%s look %d" % [q.name, int(q.look)]))
