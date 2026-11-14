extends Scenario
## Sera on the minimap after playing someone else: her own standing pose, not the one last played. Plays Miyu, then
## Sera again, and compares the pose the maps draw for her with her own art. Run with --window=mappose.


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _is_sera(tex: Texture2D) -> bool:
	var at := tex as AtlasTexture
	var id := int(Playable.active._lead_data.frames.idleDownLeft[0])
	var info: Dictionary = world.sprites[id]
	return at != null and Rect2(int(info.rect[0]), int(info.rect[1]), int(info.rect[2]), int(info.rect[3])).encloses(at.region) and at.atlas == world._texture(info.tex)


func run() -> void:
	await _frames(30)
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
	await _frames(20)
	print("Map pose: as Sera, hers ", _is_sera(Playable.active.pose()))
	var ok := Playable.active.switch_to(miyu)
	await _frames(30)
	var sera_v: Villager = null
	for v in Villager.all:
		if is_instance_valid(v) and str(v.person.get("unique", "")) == Playable.LEAD:
			sera_v = v
	print("Map pose: Miyu played ", ok, "; Sera the villager drawn as Sera ", _is_sera(Party.active.pose(sera_v.person)) if sera_v != null else "?")
	ok = Playable.active.switch_to(sera_v)
	await _frames(30)
	print("Map pose: back to Sera ", ok, "; the minimap shows her own ", _is_sera(Playable.active.pose()))
	shot("minimap")
