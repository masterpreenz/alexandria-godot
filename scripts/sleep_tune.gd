class_name SleepTune
## How sleepers lie, adjusted by hand: by which way the bed faces, an X, Y (px) and R (degrees) on top of where the bed
## puts them (data/sleep_tune.json: "sw" for a bed whose foot is down-left, "se" down-right -> [x, y, r]), applied to
## every villager who lies down (Villager's lie_in_bed), whoever they are: they're all one size of body. On an "se"
## bed the sleeper's art is mirrored, and X and R are mirrored with it. (The numbers were set in the game with a
## little panel, since taken out: edit the file.)

const PATH := "res://data/sleep_tune.json"

static var _data := {}
static var _loaded := false


## The adjustment on a bed facing [param right] (its foot down-right) or not: [x, y (px), r (degrees)].
static func of(right: bool) -> Array:
	if not _loaded:
		_loaded = true
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH)) if FileAccess.file_exists(PATH) else null
		_data = d if d is Dictionary else {}
	var v: Variant = _data.get("se" if right else "sw")
	return v if v is Array and (v as Array).size() == 3 else [0.0, 0.0, 0.0]
