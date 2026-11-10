class_name Ledger
extends Node
## Whether the village is using more than it brings in: what's in storage is noted each game hour (food of every kind
## together, wood, stone), and over the last day's notes the change tells. Running down, with only a few days of it
## left at that rate, the village log warns: food first and loudest.

const HOURS := 24                 ## how far back it looks
const LEAST := 8                  ## hours of notes before it says anything
const DAYS_LEFT := 3.0            ## a warning when what's stored lasts less than this at the rate it's going
const KINDS := ["Food", "Wood", "Stone"]

var world: World
var notes: Array = []             ## [{hour, Food, Wood, Stone}], oldest first
var _hour := -1


func setup(w: World) -> void:
	world = w


## What's in storage of [param kind]: "Food" is everything the villagers eat, raw or cooked.
func stored(kind: String) -> int:
	if kind != "Food":
		return world.village.stored(kind)
	var n := 0
	for f in Villager.FOODS:
		n += world.village.stored(f[0])
	return n


## The change in [param kind] a day, by the notes (less than 0: running down); 0 with too few notes.
func a_day(kind: String) -> float:
	if notes.size() < 2:
		return 0.0
	var first: Dictionary = notes[0]
	var last: Dictionary = notes[-1]
	var hours := float(last.hour) - float(first.hour)
	if hours < LEAST:
		return 0.0
	return (float(last[kind]) - float(first[kind])) / hours * 24.0


func _process(_delta: float) -> void:
	var c := world.clock
	if c == null or not world.village.founded():
		return
	var hour := floori(c.hours)
	if hour == _hour:
		return
	# (the clock put back, or a long jump: start again)
	if hour < _hour or hour > _hour + 6:
		notes.clear()
	_hour = hour
	var note := {"hour": hour}
	for k: String in KINDS:
		note[k] = stored(k)
	notes.append(note)
	while notes.size() > HOURS + 1:
		notes.pop_front()
	_tell()


func _tell() -> void:
	for k: String in KINDS:
		var rate := a_day(k)
		var have := stored(k)
		if rate >= -0.5:
			continue
		var days := have / -rate
		if days >= DAYS_LEFT:
			continue
		var what := "food" if k == "Food" else k.to_lower()
		var left := "about a day" if days < 1.5 else "about %d days" % roundi(days)
		if have <= 0:
			continue   # (none at all: other messages say so)
		VillageLog.problem("running-down:" + k, "The village is using more %s than it brings in: %d less a day, %s of it left (%d)" % [what, roundi(-rate), left, have],
			VillageLog.Kind.DANGER if k == "Food" else VillageLog.Kind.WARNING)
