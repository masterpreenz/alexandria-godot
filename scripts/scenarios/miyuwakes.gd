extends Scenario
## Miyu awake after her rescue: a "?" over her, talking to her plays her scene (her thanks, and asking to come along),
## and as it ends she's in Sera's party. Then, far out in the wilds, "Go home" puts her straight back in the village.
## Run with --window=miyuwakes.


func run() -> void:
	for i in 30:
		await get_tree().process_frame
	var ch := Chronicle.active
	var miyu: Villager = null
	for v in Villager.all:
		if is_instance_valid(v) and str(v.person.get("unique", "")) == "miyu":
			miyu = v
	if miyu == null:
		# (the bundled save has no Miyu yet: someone stands in for her)
		miyu = Villager.all[1]
		miyu.person["unique"] = "miyu"
		miyu.person["name"] = "Miyu"
		miyu.person["restUntil"] = -1.0
		var tr: Array = miyu.person.get("traits", []).duplicate()
		tr.append("unique")
		miyu.person["traits"] = tr
	ch.events = ch.events.filter(func(e): return not str(e.what) in ["party:miyu", "party_join:miyu", "scene:miyu_wakes"])
	if Party.active.members.has("miyu"):
		Party.active.members.erase("miyu")
	if not ch.happened("miyu_home"):
		ch.record("miyu_home")
	miko.place(miyu.position + Vector2(1.0, 0.6) * world.px)
	for i in 30:
		await get_tree().process_frame
	var scene := Scenes.for_speaker(miyu.person)
	print("Miyu wakes: scene waiting '", scene.get("id", ""), "', her emote '", miyu._rumor_emote(), "', state ", miyu.state)
	var talk: Talk = Talk.active
	talk.open(miyu)
	for i in 10:
		await get_tree().process_frame
	shot("talk")
	talk._play(scene, (scene.lines as Array).size())
	for i in 20:
		await get_tree().process_frame
	print("Miyu wakes: in the party ", Party.active.members.has("miyu"), ", willing ", Party.willing(miyu.person), ", talk open ", talk.visible)
	# Far out: sent home.
	var out := world.village.centre() + Vector2(-60.0, 40.0) * world.px
	miko.place(out)
	miyu.position = out + Vector2(1.0, 0.5) * world.px
	for i in 20:
		await get_tree().process_frame
	print("Miyu wakes: out in the wilds, in the village ", world.village.contains(miyu.position, Party.HOME_NEAR))
	Party.active.leave("miyu")
	for i in 5:
		await get_tree().process_frame
	print("Miyu wakes: sent home, in the village now ", world.village.contains(miyu.position, 1.0), ", in the party ", Party.active.members.has("miyu"))
