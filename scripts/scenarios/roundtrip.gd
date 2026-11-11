extends Scenario
## The "roundtrip" scenario.
## Run with --window=roundtrip.


func run() -> void:
	var now := (g.get_node("SaveGame") as SaveGame).capture()
	var start := SaveSystem.start_sections(world)
	for k in start:
		if not now.has(k): print("Round trip: missing ", k)
		elif JSON.parse_string(now[k]) != JSON.parse_string(start[k]): print("Round trip: differs ", k, "
  was ", str(start[k]).left(300), "
  now ", str(now[k]).left(300))
		else: print("Round trip: same ", k)
