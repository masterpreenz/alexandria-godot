extends Scenario
## "Play as Miyu" without her being in the party, and while she's at work: offered, and the switch works; refused
## while she's fighting. Run with --window=playanyone.


func run() -> void:
	for i in 30:
		await get_tree().process_frame
	var miyu: Villager = Villager.all[1]
	miyu.person["unique"] = "miyu"
	miyu.person["name"] = "Miyu"
	var trait_list: Array = miyu.person.get("traits", []).duplicate()
	trait_list.append("unique")
	miyu.person["traits"] = trait_list
	Party.active.members.erase("miyu")
	miyu.person["hasBed"] = false
	miyu.position = world.village.centre() + Vector2(1.0, 0.5) * world.px
	miko.place(world.village.centre())
	miyu.state = Villager.State.WORK
	var pl := Playable.active
	print("Play anyone: not in the party, no bed, working: why not '", pl.why_not(miyu), "'")
	miyu.state = Villager.State.FIGHT
	print("Play anyone: fighting: why not '", pl.why_not(miyu), "'")
	miyu.state = Villager.State.STAND
	pl.switch_to(miyu)
	for i in 20:
		await get_tree().process_frame
	var sera: Villager = null
	for v in Villager.all:
		if is_instance_valid(v) and str(v.person.get("unique", "")) == "sera":
			sera = v
	print("Play anyone: playing ", pl.who, ", party ", Party.active.members, ", Sera's here ", sera != null, " state ", Villager.State.keys()[sera.state] if sera != null else "-")
	for i in 120:
		await get_tree().process_frame
	print("Play anyone: 2 s on, Sera ", Villager.State.keys()[sera.state] if sera != null else "-", ", in the party ", Party.active.members.has("sera"))
