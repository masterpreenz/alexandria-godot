class_name Chronicle
extends Node
## The chronicle: the game's timeline. Everything of note that's happened, in order, each with when (the clock's
## hours): a rumor became known to someone, was heard, reached a step, came to something, was left too long. Other
## systems record to it ([method record]) and ask it ([method happened], [method days_since]): it's how one thing
## happening, or not happening, leads to another. Saved with the game.
##
## What's recorded is a short name, "kind:what" (as "heard:forest_clearing", "done:forest_clearing",
## "step:forest_clearing/clear"): the same names rumors.json's conditions use.

signal recorded(what: String)

static var active: Chronicle

var world: World
var events: Array = []            ## [{h: hours, what: String, data: Dictionary}], oldest first


func setup(w: World) -> void:
	world = w
	active = self


func now() -> float:
	return world.clock.hours if world.clock != null else 0.0


## Writes down that [param what] has happened, now.
func record(what: String, data: Dictionary = {}) -> void:
	events.append({"h": now(), "what": what, "data": data})
	recorded.emit(what)


## When [param what] first happened (the clock's hours), or -1 if it hasn't.
func when(what: String) -> float:
	for e in events:
		if e.what == what:
			return float(e.h)
	return -1.0


func happened(what: String) -> bool:
	return when(what) >= 0.0


## Days since [param what] first happened, or -1 if it hasn't.
func days_since(what: String) -> float:
	var h := when(what)
	return (now() - h) / 24.0 if h >= 0.0 else -1.0


## The date of [param h] (the clock's hours), as "Summer, day 5".
func date(h: float) -> String:
	var c := world.clock
	if c == null:
		return ""
	var day := floori(h / 24.0)
	var per := maxi(1, c.days_per_season)
	@warning_ignore("integer_division")
	return "%s, day %d" % [GameClock.SEASON_NAMES[(c.start_season + day / per) % 4], day % per + 1]


func to_json() -> String:
	return JSON.stringify({"events": events})


func from_json(json: String) -> void:
	var d: Variant = JSON.parse_string(json)
	if d is Dictionary and d.get("events") is Array:
		events = d.events
