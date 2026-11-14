extends Scenario
## The painted portraits: Sera's on her card, Miyu's on her party card, in a talk with her and in the party window.
## Run with --window=portraits.


func _secs(s: float) -> void:
	var until := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame


func run() -> void:
	await _secs(1.0)
	var miyu: Villager = Villager.all[1]
	miyu.person["unique"] = "miyu"
	miyu.person["name"] = "Miyu"
	miyu.person["look"] = 5
	var tl: Array = miyu.person.get("traits", []).duplicate()
	tl.append("unique")
	miyu.person["traits"] = tl
	var lk: Dictionary = people._look_for(miyu.person)
	miyu.look = lk
	miyu.s = lk.settings
	Party.active.join("miyu")
	miyu._follow_start(Villager.now())
	miyu.position = miko.position + Vector2(-0.9, 0.4) * world.px
	await _secs(1.0)
	print("Portraits: Sera's ", Playable.active.portrait().resource_path, ", Miyu's card ", Party.active.face(miyu.person).resource_path)
	shot("cards")
	Talk.active.open(miyu)
	await _secs(1.0)
	shot("talk")
	Talk.active.close()
	await _secs(0.3)
	PartyWindow.active.open()
	await _secs(0.8)
	shot("party")
	PartyWindow.active.close()
	await _secs(0.3)
	miyu.state = Villager.State.STAND
	miyu.state_until = Villager.now() + 60.0
	miyu.position = miko.position + Vector2(-8.0, 4.0) * world.px
	await _secs(0.8)
	print("Portraits: on the maps, Sera's ", Party.active.pose({}).resource_path, ", Miyu's ", Party.active.pose(miyu.person).resource_path)
	shot("minimap")
