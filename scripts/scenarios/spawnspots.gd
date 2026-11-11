extends Scenario
## Random spots round the rivers: how many the spawners would take that are in or at the water.
## Run with --window=spawnspots.


func run() -> void:
	var ws: WorldSounds = world.get_node("WorldSounds")
	var taken := 0
	var wet := 0
	for i in 20000:
		var r: Dictionary = ws._rivers[i % ws._rivers.size()]
		var smp: Array = r.samples[randi() % r.samples.size()]
		var spot_at := world.floors.corner(Vector2(smp[0], smp[1])) + Vector2(randf_range(-4, 4), randf_range(-2, 2)) * world.px
		if Wilds.open(world, spot_at, 0.5):
			taken += 1
			var near_water := world.wet(spot_at)
			for k in 8:
				var ang := k * TAU / 8.0
				if world.wet(spot_at + Vector2(cos(ang), sin(ang) * 0.5) * 0.5 * world.px):
					near_water = true
			if near_water:
				wet += 1
	print("Spawn spots by rivers: ", taken, " taken, ", wet, " of them in or at the water")
