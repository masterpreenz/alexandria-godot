extends Scenario
## Miyu asleep in a bed, lying both ways (face down and seen from behind), head on the pillow. Run with --window=miyusleep.


func run() -> void:
	for i in 30:
		await get_tree().process_frame
	var v: Villager = null
	for x in Villager.all:
		if is_instance_valid(x) and not x.home.is_empty():
			v = x
			break
	v.person["look"] = 5
	v.look = v.people._look_for(v.person)
	v.s = v.look.settings
	v.set_physics_process(false)
	v.set_process(false)
	miko.place(v.home.pos + Vector2(1.2, 0.6) * world.px)
	for i in 20:
		await get_tree().process_frame
	for up in [false, true]:
		v._go_to_sleep()
		v.facing_up = up
		v._show(int((v.s.sleepUp if up else v.s.sleepDown)[-1]))
		v.lie_in_bed()
		for i in 5:
			await get_tree().process_frame
		v.facing_up = up
		v._show(int((v.s.sleepUp if up else v.s.sleepDown)[-1]))
		v.lie_in_bed()
		await get_tree().process_frame
		shot("up" if up else "down")
		print("Miyu sleep: ", "up" if up else "down", " at ", v.position - v.home.pos, " turned ", snappedf(rad_to_deg(v.art.rotation), 0.1))
