extends Scenario
## What's limited, how many stand, and what the ghost says in the village's middle.
## Run with --window=limits.


func run() -> void:
	var bm := BuildMode.active
	for it in bm.items:
		if bm.limit_of(it) >= 0:
			print("Limits: ", it.display, ": ", world.props_named(str(it.name)).size(), " of ", bm.limit_of(it), " (by level ", it.limit, "), village grown ", world.village.growths(), "; placing one: '", bm.why_not(it, world.village.centre() + Vector2(3, 2) * world.px), "'")
