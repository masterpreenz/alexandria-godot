extends Scenario
## Two dummies 1.2 units apart: one staff swing between them, then one fireball at the first; who's hit.
## Run with --window=aoe.


func run() -> void:
	var hits := {}
	var dums := []
	for k in 2:
		var dm := Damageable.new()
		dm.position = miko.position + Vector2(0.9, -0.3 + 0.6 * k) * world.px
		world.things.add_child(dm)
		dm.setup(world, Damageable.Team.ENEMY, 5000.0, 0.3 * world.px, 1.0 * world.px)
		dm.dummy = true
		hits[k] = []
		dm.damaged.connect(func(a): (hits[k] as Array).append(roundi(a)))
		dums.append(dm)
	print("Aoe: dummies ", snappedf(dums[0].position.distance_to(dums[1].position) / world.px, 0.01), " units apart on screen")
	var ml: Melee = g.find_child("Melee", true, false)
	ml._toward = Vector2.RIGHT
	ml._strike()
	print("Aoe: one staff swing hit ", hits)
	hits[0] = []
	hits[1] = []
	for k in 2:
		dums[k].position = miko.position + Vector2(3.0 + 1.3 * k, 0) * world.px
	var cn: SpellCaster = world.get_node("Caster")
	cn.cast_at("Fireball", dums[0].position)
	for i in 120:
		await get_tree().process_frame
		if i == 40:
			get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_boom.png")
	print("Aoe: one fireball at the first hit ", hits)
