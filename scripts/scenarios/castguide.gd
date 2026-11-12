extends Scenario
## The guide's "Clear the road" beat: casting a skill (Fireball) lights up its part, as striking does.
## Run with --window=castguide --slot=new.


func run() -> void:
	var st: Story = g.get_node("Story")
	for i in 20:
		await get_tree().process_frame
	for i in 14:
		miko.place(miko.position + Vector2(0, -0.8) * world.px)
		await get_tree().process_frame
	for i in 10:
		await get_tree().process_frame
	for c in Creature.all.duplicate():
		if is_instance_valid(c) and c is Slime and c.hit.alive():
			c.hit.hurt(9999.0, true)
	for i in 20:
		await get_tree().process_frame
	var caster: SpellCaster = world.get_node("Caster")
	caster.cast_at("Fireball", miko.position + Vector2(3, 0) * world.px)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 3000 and not st._did.has("cast"):
		await get_tree().process_frame
	print("Cast guide: beat ", st._beats()[st.beat].id, ", done ", st._did.keys(), "; text ", st._hint.text)
	get_viewport().get_texture().get_image().save_png(Shots.arg("shot").get_basename() + "_cast.png")
