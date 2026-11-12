extends Scenario
## Saves are written as plain JSON (readable), and an old sealed save still opens.
## Run with --window=plainsave.


func run() -> void:
	for i in 20:
		await get_tree().process_frame
	var sg: SaveGame = g.get_node_or_null("SaveGame")
	var slot := "plaintest"
	# (the game won't save while a test runs, so the save's written straight through the save system)
	var ok := SaveSystem.write(slot, sg.summarise(), sg.capture()) == ""
	var bytes := FileAccess.get_file_as_bytes(SaveSystem.path_of(slot))
	var head := bytes.slice(0, 40).get_string_from_utf8()
	var back := SaveSystem.read(slot)
	print("Plain save: written ", ok, "; starts '", head.replace("\n", " ").left(30), "'; reads back with ", (back.get("sections", []) as Array).size(), " sections")
	SaveSystem.delete(slot)
	# An old sealed one (the user's auto save, if it's still sealed) opens.
	if SaveSystem.exists(SaveSystem.AUTO):
		var raw := FileAccess.get_file_as_bytes(SaveSystem.path_of(SaveSystem.AUTO))
		print("Plain save: the auto save sealed ", raw.slice(0, 8).get_string_from_ascii() == SaveSystem.MAGIC, ", opens with ", (SaveSystem.read(SaveSystem.AUTO).get("sections", []) as Array).size(), " sections")
