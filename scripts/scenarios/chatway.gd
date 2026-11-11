extends Scenario
## Nobody chats in a doorway or by the storage: who's in the way now, and many tries at a chat.
## Run with --window=chatway.


func run() -> void:
	clock.hours = float(clock.day() - 1) * 24.0 + 19.0
	for i in 10:
		await get_tree().process_frame
	var chest: Variant = UseSpots.nearest_chest_spot(world, world.village.centre())
	var door: Array = world.walls.nearest_door(world.village.centre(), 40.0 * world.px)
	print("Chat way: by the chest ", chest != null and Villager.in_the_way(world, chest), ", on open ground ", Villager.in_the_way(world, world.village.centre() + Vector2(3.0, 2.2) * world.px), ", a door found ", not door.is_empty())
	var a: Villager = Villager.all[0]
	var b: Villager = Villager.all[1]
	var blocked := 0
	var met := 0
	for where in [chest, world.village.centre() + Vector2(3.0, 2.2) * world.px]:
		if where == null:
			continue
		for i in 20:
			for vl in [a, b]:
				vl.partner = null
				vl._stand(Villager.now(), 0.0)
			b.position = where
			a.position = (where as Vector2) + Vector2(randf_range(-2.5, 2.5), randf_range(-1.2, 1.2)) * world.px
			for other in Villager.all:
				if other != a and other != b:
					other.position = world.village.centre() + Vector2(-30, -30) * world.px
			if a._go_chat(Villager.now()):
				met += 1
				blocked += 1 if Villager.in_the_way(world, a.target) or Villager.in_the_way(world, b.position) else 0
		print("Chat way: 20 tries with one of them ", "by the chest" if where == chest else "on open ground", ": chats begun so far ", met, ", of them in the way ", blocked)
