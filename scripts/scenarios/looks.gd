extends Scenario
## Miyu's own look (5) and look 2 free for the village's women: Miyu arriving wears 5, newcomers can come in 2, and an
## older save's Miyu in 2 is put in 5. Run with --window=looks.


func run() -> void:
	for i in 20:
		await get_tree().process_frame
	var vs: Villagers = get_tree().current_scene.find_child("Villagers", true, false)
	var had := vs.people.map(func(q): return int(q.look))
	var came := []
	for i in 6:
		came.append(int(vs._newcomer().look))
	print("Looks: the village's looks ", had, ", six newcomers came in ", came)
	var old := {"name": "Miyu", "look": 2, "unique": "miyu", "level": 3}
	vs._fix(old)
	print("Looks: an older save's Miyu now look ", old.look, ", Miyu's in data ", Uniques.all().miyu.look, ", looks ", vs.d.looks.size(), ", look 5 is hers ", vs.d.looks[5].settings.get("uniqueTo", ""))
