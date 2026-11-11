class_name LifeSkills
## Miko's life skills (from Unity's LifeSkills / PlayerSkills): Lumbering, Mining, Strength, Farming, Cooking, Building,
## Stamina and Fishing, each from 1 up to [constant MOST]. Practising one (chopping, mining, running, ...) adds to it; 8 times
## its level and it goes up a level. Each level makes what it's for a little better ([method factor]).

enum Skill { LUMBERING, MINING, STRENGTH, FARMING, COOKING, BUILDING, STAMINA, FISHING }

const MOST := 12
const NAMES := ["Lumbering", "Mining", "Strength", "Farming", "Cooking", "Building", "Stamina", "Fishing"]

static var level: Array = [1, 1, 1, 1, 1, 1, 1, 1]
static var xp: Array = [0, 0, 0, 0, 0, 0, 0, 0]


## The saved skills (Unity's player.skills: {level: [...], xp: [...]}); an empty set starts every skill at 1.
static func from_json(json: String) -> void:
	var d: Variant = JSON.parse_string(json)
	level = [1, 1, 1, 1, 1, 1, 1, 1]
	xp = [0, 0, 0, 0, 0, 0, 0, 0]
	if d is Dictionary:
		var l: Array = d.get("level", [])
		var x: Array = d.get("xp", [])
		for i in mini(l.size(), level.size()):
			level[i] = clampi(int(l[i]), 1, MOST)
		for i in mini(x.size(), xp.size()):
			xp[i] = maxi(0, int(x[i]))


static func to_json() -> String:
	return JSON.stringify({"level": level, "xp": xp})


static func get_level(s: int) -> int:
	return int(level[s])


## 1, plus [param per_level] for each level past the first.
static func factor(s: int, per_level: float) -> float:
	return 1.0 + per_level * (maxi(1, get_level(s)) - 1)


## Practises [param s]: up a level after enough, saying so over [param who].
static func practise(s: int, who: Node2D = null, amount := 1) -> void:
	if level[s] >= MOST:
		return
	xp[s] += amount
	if xp[s] < 8 * maxi(1, level[s]):
		return
	xp[s] = 0
	level[s] += 1
	if who != null and who.get("world") != null:
		var w: World = who.world
		FloatingText.spawn(w, "%s up to %d!" % [NAMES[s], level[s]], who.position + Vector2(0, -2.0 * w.px), Color(1, 0.86, 0.45))
