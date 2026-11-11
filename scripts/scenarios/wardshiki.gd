extends Scenario
## A shield shikigami out, a slime and a mutated villager coming at Miko: they turn on it, it wards her
## and stands its ground; then she walks off and it follows.
## Run with --window=wardshiki.


func run() -> void:
	var st: CharacterStats = miko.stats
	var caster_node: SpellCaster = world.get_node("Caster")
	var sd: Dictionary = world._load_json("res://data/shikigami.json")
	var md: Dictionary = world._load_json("res://data/monsters.json")
	var ward := Shikigami.summon(world, "ShikigamiDefender", sd["ShikigamiDefender"], miko, st, caster_node, miko.position)
	var sl: Slime = Slime.spawn(world, md.slime, false, miko.position + Vector2(3.0, 0.5) * world.px, 1.0)
	sl.angry_until = Creature.now() + 999.0
	var mv := MutatedVillager.spawn(world, md.mutatedVillager, miko.position + Vector2(-3.0, 0.8) * world.px)
	mv.raid_to = miko.position
	var hp0: float = st.hp
	var ward_hp0: float = ward.hp
	var warded := false
	var shot := false
	var stood := Vector2.ZERO
	for i in int(Shots.arg("wardframes", "1100")):
		await get_tree().process_frame
		if not is_instance_valid(ward):
			print("Ward shiki: struck down at frame ", i)
			break
		warded = warded or ward.bubble != null
		if ward.holding and stood == Vector2.ZERO:
			stood = ward.position
		if i % 180 == 0:
			print("Ward shiki ", floori(i / 60.0), ": slime on it ", is_instance_valid(sl) and sl.taunted_by == ward, ", mutant on it ", is_instance_valid(mv) and mv.taunted_by == ward, ", ward up ", ward.bubble != null, ", holding ", ward.holding, ", its HP ", roundi(ward.hp), "/", roundi(ward_hp0), ", her HP ", roundi(st.hp), "/", roundi(hp0))
		if not shot and ward.bubble != null and i > 120:
			shot = true
			get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_ward.png")
	if is_instance_valid(ward):
		print("Ward shiki: warded ", warded, ", moved while holding ", snappedf(ward.position.distance_to(stood) / world.px, 0.1), " units")
		miko.place(miko.position + Vector2(9.0, 0) * world.px)
		for i in 240:
			await get_tree().process_frame
		if is_instance_valid(ward):
			print("Ward shiki: she went 9 units off; it's ", snappedf(ward.position.distance_to(miko.position) / world.px, 0.1), " units from her, holding ", ward.holding)
