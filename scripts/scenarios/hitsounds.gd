extends Scenario
## The combat sounds by kind (Sfx.GROUPS): each kind's takes load, and picks come at random, never one twice running.
## Run with --window=hitsounds.


func run() -> void:
	for kind in Sfx.GROUPS:
		var picks := []
		var repeats := 0
		var last := -1
		for i in 12:
			var clip := Sfx.one_of(kind)
			var take := int(Sfx._last_take[kind])
			if take == last:
				repeats += 1
			last = take
			picks.append(take if clip != null else -1)
		print("Hit sounds: ", kind, " takes ", picks, ", twice running ", repeats)
