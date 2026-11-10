class_name SleepTune
## How sleepers lie, adjusted by hand: for each look and pose, an X, Y (px) and R (degrees) on top of where the bed
## puts them (data/sleep_tune.json: "look:pose" -> [x, y, r]), applied to every villager who lies down (Villager's
## lie_in_bed). X and R are as seen with the sleeper's feet to the left: on a bed turned the other way they're
## mirrored with the art. (The numbers were set in the game with a little panel, since taken out: edit the file.)

const PATH := "res://data/sleep_tune.json"

static var _data := {}
static var _loaded := false


## The adjustment for [param look]'s [param pose] ("sleepDown", "sleepUp"): [x, y (px), r (degrees)].
static func of(look: int, pose: String) -> Array:
	if not _loaded:
		_loaded = true
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH)) if FileAccess.file_exists(PATH) else null
		_data = d if d is Dictionary else {}
	var v: Variant = _data.get("%d:%s" % [look, pose])
	return v if v is Array and (v as Array).size() == 3 else [0.0, 0.0, 0.0]
