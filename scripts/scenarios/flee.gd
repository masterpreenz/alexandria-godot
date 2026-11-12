extends Scenario
## A villager at 15% health with a mutated villager a few steps off: they run; distance and state each second.
## Run with --window=flee.


func run() -> void:
	clock.hours = float(clock.day() - 1) * 24.0 + 10.0
	while Villager.all.is_empty():
		await get_tree().process_frame
	var v: Villager = Villager.all[0]
	v.position = world.village.centre() + Vector2(1.0, 1.0) * world.px
	v.hit.hp = v.hit.max_hp * 0.15
	var md: Dictionary = world._load_json("res://data/monsters.json")
	var mv := MutatedVillager.spawn(world, md.mutatedVillager, v.position + Vector2(2.5, 0.0) * world.px)
	mv.raid_to = v.position
	miko.place(v.position + Vector2(-1.0, 2.5) * world.px)
	var pic := false
	for i in int(Shots.arg("fleeframes", "600")):
		await get_tree().process_frame
		if i % 60 == 0:
			print("Flee ", floori(i / 60.0), " s: ", Villager.State.keys()[v.state], ", ", snappedf(v.position.distance_to(mv.position) / world.px, 0.1), " units from it, HP ", roundi(v.hit.hp), " '", v.activity(), "'")
		if not pic and v.state == Villager.State.FLEE and i > 20:
			pic = true
			miko.place(v.position + Vector2(-1.5, 2.0) * world.px)
			for k in 3:
				await get_tree().process_frame
			print("Flee pic: ", v.person.name, " bark showing ", v._bark != null and v._bark.visible)
		if i == 450:
			miko.place(v.position + Vector2(-1.5, 2.0) * world.px)
			for k in 3:
				await get_tree().process_frame
			print("Flee later: emote showing ", v.emote != null and v.emote.visible, ", bark ", v._bark != null and v._bark.visible, " ", v._bark.text if v._bark != null else "", ", mood ", v.mood, ", bubble ", v.bubble != null and v.bubble.visible)
			get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_cry.png")
			get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_run.png")
		if not is_instance_valid(v):
			print("Flee: the villager died")
			break
