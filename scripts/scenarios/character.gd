extends Scenario
## The "character" scenario.
## Run with --window=character.


func run() -> void:
	var cp: CharacterPanel = g.get_node("Hud/CharacterPanel")
	cp.toggle()
	# --sizes: the panel's size with each kind of thing picked in turn (it shouldn't change).
	if Shots.arg("sizes") != "":
		var sizes := []
		for nm in ["", "Wood", "Sachet", "CrystalNecklace", "ShrineCharm"]:
			if nm == "Wood" or nm == "":
				cp.selected = -1 if nm == "" else miko.bag.stack_slot.get("Wood", -1)
			else:
				var slot_at := miko.bag.free_slot()
				miko.bag.items[slot_at] = nm
				cp.selected = slot_at
			cp._dirty = true
			for i in 3:
				await get_tree().process_frame
			var root: Control = cp.get_child(0) if cp.get_child_count() > 0 else cp
			sizes.append([nm, root.size])
		print("Panel sizes: ", sizes)
