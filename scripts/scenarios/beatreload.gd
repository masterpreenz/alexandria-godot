extends Scenario
## A game saved part way through "Clear the road" and loaded: the beat's slimes come again (they aren't in the save),
## so it can still be finished. Run with --window=beatreload --slot=new.


func _slimes() -> int:
	return Creature.all.filter(func(c): return is_instance_valid(c) and c is Slime and c.hit.alive()).size()


func run() -> void:
	var st: Story = g.get_node("Story")
	for i in 20:
		await get_tree().process_frame
	while str(st._beats()[st.beat].id) != "slimes":
		st._begin(st.beat + 1, false)
		await get_tree().process_frame
	await get_tree().process_frame
	var before := _slimes()
	# As a load finds it: no monsters about, the story where it was.
	for c in Creature.all.duplicate():
		if is_instance_valid(c):
			c.queue_free()
	await get_tree().process_frame
	var saved := st.to_json()
	st.from_json(saved)
	for i in 5:
		await get_tree().process_frame
	print("Beat reload: beat ", st._beats()[st.beat].id, "; slimes before ", before, ", after loading ", _slimes())
	for c in Creature.all.duplicate():
		if is_instance_valid(c) and c is Slime:
			c.hit.hurt(9999.0, true)
	for i in 20:
		await get_tree().process_frame
	print("Beat reload: once they're killed, beat ", st._beats()[st.beat].id)
