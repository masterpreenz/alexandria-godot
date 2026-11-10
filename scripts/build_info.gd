class_name BuildInfo
## Which build this is, for the line at the bottom of the screen: the stage and version (data/version.json) and a
## build id, the commit it was made from (read from the project's .git when run from the project; an exported game
## uses the one stamped in version.json, which tools/stamp_build.py writes).

static var _text := ""


## "ALPHA 0.1  ·  build 8c98985"
static func text() -> String:
	if _text == "":
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/version.json")) if FileAccess.file_exists("res://data/version.json") else null
		var info: Dictionary = d if d is Dictionary else {}
		var build := _commit()
		if build == "":
			build = str(info.get("build", "dev"))
		_text = "%s %s  ·  build %s" % [str(info.get("stage", "Alpha")).to_upper(), str(info.get("version", "0.1")), build]
	return _text


# The commit checked out (its first 7 letters), or "" when there's no .git to read.
static func _commit() -> String:
	var head := "res://.git/HEAD"
	if not FileAccess.file_exists(head):
		return ""
	var line := FileAccess.get_file_as_string(head).strip_edges()
	if not line.begins_with("ref: "):
		return line.left(7)
	var ref := line.trim_prefix("ref: ")
	if FileAccess.file_exists("res://.git/" + ref):
		return FileAccess.get_file_as_string("res://.git/" + ref).strip_edges().left(7)
	# (packed away: "<hash> <ref>" lines)
	if FileAccess.file_exists("res://.git/packed-refs"):
		for l in FileAccess.get_file_as_string("res://.git/packed-refs").split("\n"):
			if l.ends_with(" " + ref):
				return l.left(7)
	return ""
