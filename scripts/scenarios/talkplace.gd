extends Scenario
## Where the talk box goes: over the one talked to, its tail down to their head; with no room over them (near the top of
## the screen), beside them, the tail from its side, never across the replies. Run with --window=talkplace.


func _secs(s: float) -> void:
	var until := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame


func run() -> void:
	await _secs(1.0)
	var v: Villager = null
	for x in Villager.all:
		if is_instance_valid(x) and x.state != Villager.State.ASLEEP and x.visible:
			v = x
			break
	var t := Talk.active
	for case in [["middle", Vector2(0.6, 0.3)], ["high", Vector2(0.6, 1.9)]]:
		v.state = Villager.State.STAND
		v.state_until = Villager.now() + 60.0
		miko.place(v.position + (case[1] as Vector2) * world.px)
		await _secs(0.6)
		t.open(v)
		await _secs(0.8)
		var head := get_viewport().get_canvas_transform() * t._head_of(v)
		var box := Rect2(t.position, t.size)
		print("Talk box (", case[0], "): head ", head.round(), ", box ", box.position.round(), " ", box.size.round(), ", head inside the box ", box.grow(-2).has_point(head), ", tail from ", t._tail.from.round(), " along ", t._tail.across)
		shot(case[0])
		t.close()
		await _secs(0.3)
