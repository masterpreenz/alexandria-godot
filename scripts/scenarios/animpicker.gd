extends Scenario
## The animation tuner's look and animation drop-downs: opened, both lists printed in their order, one look picked from
## the list, with shots. Run with --window=animpicker.


func _secs(s: float) -> void:
	var until := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame


func run() -> void:
	await _secs(0.5)
	var tuner: AnimTuner = g.get_node("Hud/AnimTuner")
	tuner.open()
	await _secs(0.5)
	var drops: Array = tuner.find_children("*", "OptionButton", true, false)
	print("Picker: drop-downs ", drops.size())
	for o: OptionButton in drops:
		var names := []
		for i in o.item_count:
			names.append(o.get_item_text(i))
		print("Picker: [", o.get_item_text(o.selected), "] of ", names)
	shot("closed")
	var looks: OptionButton = drops[0]
	looks.show_popup()
	await _secs(0.4)
	shot("open")
	looks.get_popup().hide()
	looks.select(looks.item_count - 1)
	looks.item_selected.emit(looks.item_count - 1)
	await _secs(0.5)
	var after: OptionButton = tuner.find_children("*", "OptionButton", true, false)[0]
	print("Picker: picked the last, now look ", tuner.look, ", shown [", after.get_item_text(after.selected), "]")
	shot("picked")
	tuner.close()
