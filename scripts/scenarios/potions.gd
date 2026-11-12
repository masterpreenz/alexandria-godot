extends Scenario
## A new game starts with 2 HP and 2 mana potions; drinking one gives back HP (60) or mana (50), not past the most.
## Fireball's and the Attack Shikigami's damage as set. Run with --window=potions --slot=new.


func run() -> void:
	for i in 20:
		await get_tree().process_frame
	var nd: Needs = miko.get_node("Needs")
	var hp0 := miko.bag.count("HpPotion")
	var mp0 := miko.bag.count("ManaPotion")
	miko.stats.hp = 20.0
	miko.stats.mana = 5.0
	nd.eat("HpPotion")
	nd.eat("ManaPotion")
	print("Potions: had ", hp0, " HP and ", mp0, " mana; after one of each HP ", roundi(miko.stats.hp), ", mana ", roundi(miko.stats.mana), "; left ", miko.bag.count("HpPotion"), " and ", miko.bag.count("ManaPotion"))
	var c: Dictionary = world._load_json("res://data/combat.json")
	print("Potions: Fireball damage ", c.spells.Fireball.damage, ", Attack Shikigami power ", world._load_json("res://data/shikigami.json").ShikigamiAttacker.power)
