class_name Scenes
## Story scenes (data/scenes.json): a conversation that plays, once, when Sera talks to the one it belongs to and what
## it waits on has happened (in the Chronicle). When it's over it writes its own events there, so what follows can go
## by it. Talk plays them.

const FILE := "res://data/scenes.json"

static var _all: Array = []
static var _loaded := false


static func all() -> Array:
	if not _loaded:
		_loaded = true
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(FILE))
		_all = d.get("scenes", []) if d is Dictionary else []
	return _all


## The scene waiting for person [param p] to start it, or {}.
static func for_speaker(p: Dictionary) -> Dictionary:
	var ch := Chronicle.active
	if ch == null or not p.has("unique"):
		return {}
	for s in all():
		if str(s.speaker) != str(p.unique) or ch.happened("scene:" + str(s.id)):
			continue
		var w: Dictionary = s.get("when", {})
		if (w.get("after", []) as Array).all(func(e): return ch.happened(str(e))) and not (w.get("unless", []) as Array).any(func(e): return ch.happened(str(e))):
			return s
	return {}


## A scene played through: noted, and what it records written.
static func done(s: Dictionary) -> void:
	var ch := Chronicle.active
	if ch == null or ch.happened("scene:" + str(s.id)):
		return
	ch.record("scene:" + str(s.id))
	for e in s.get("records", []):
		ch.record(str(e))
