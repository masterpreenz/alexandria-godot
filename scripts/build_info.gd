class_name BuildInfo
## Which version this is, for the line at the bottom of the screen (data/version.json): the stage, then
## major.minor.fixes. Every build that adds something raises minor (and sets fixes back to 0); a build of fixes only
## raises fixes. tools/bump_version.py does either.

static var _text := ""


## "ALPHA 0.2.0"
static func text() -> String:
	if _text == "":
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/version.json")) if FileAccess.file_exists("res://data/version.json") else null
		var info: Dictionary = d if d is Dictionary else {}
		_text = "%s %d.%d.%d" % [str(info.get("stage", "Alpha")).to_upper(), int(info.get("major", 0)), int(info.get("minor", 0)), int(info.get("fixes", 0))]
	return _text
