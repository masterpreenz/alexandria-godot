extends Scenario
## A test run writes no saves: a quick save asked for during one is refused, the save folder left as it was.


func run() -> void:
	var before := DirAccess.get_files_at(SaveSystem.FOLDER)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 4000:
		await get_tree().process_frame
	var saved := SaveGame.active.save(SaveSystem.QUICK, true)
	SaveSystem.delete(SaveSystem.AUTO)
	print("No save: testing ", SaveGame.testing(), ", quick save written ", saved, ", folder unchanged ", DirAccess.get_files_at(SaveSystem.FOLDER) == before)
