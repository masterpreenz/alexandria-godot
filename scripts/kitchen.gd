class_name Kitchen
## How much of each thing the village keeps in storage (from Unity's Kitchen): villagers cook, gather and make things
## until each reaches its target, then move on to other work. The targets are set in the jobs window (phase 5) and
## saved (village.kitchen, with the crop rotation). Kept by key: a resource's name, or "item:" and an item's.

const STEP := 5
const MOST := 300
const MATERIALS := ["Wood", "Stone"]
const RECIPES := [["Food", "Meal"], ["Potato", "BakedPotato"], ["Jelly", "Candy"], ["Fish", "GrilledFish"]]  ## the fire's dishes: raw, cooked

static var targets := {}
static var seeds_given := false


static func from_json(json: String) -> void:
	targets.clear()
	var d: Variant = JSON.parse_string(json)
	if not d is Dictionary:
		return
	seeds_given = bool(d.get("seedsGiven", false))
	for e in d.get("targets", []):
		if str(e.get("food", "")) != "":
			targets[e.food] = clampi(int(e.keep), 0, MOST)


# What's kept when nothing's been set: wood and stone 60, the fire's dishes 20 (candy 10), tools 3 sets and 2 bags,
# the cooking bench's dishes 10, anything else made at a workbench none.
static func _default(key: String) -> int:
	match key:
		"Wood", "Stone": return 60
		"Candy": return 10
		"Fish": return 12
		"item:Tools": return 3
		"item:Sachet": return 2
		"Bread", "SmokedFish", "FishSoup", "FishStew": return 10
	for r in RECIPES:
		if key == r[1]:
			return 20
	return 0


static func target(key: String) -> int:
	return int(targets.get(key, _default(key)))


static func set_target(key: String, n: int) -> void:
	targets[key] = clampi(n, 0, MOST)


## The targets as Unity's village.kitchen, with the crop rotation (kept by the farms).
static func to_json(rotation: Array) -> String:
	var list := []
	for k in targets:
		list.append({"food": k, "keep": int(targets[k])})
	return JSON.stringify({"targets": list, "rotation": rotation, "seedsGiven": seeds_given})


## Whether storage already holds enough of [param r].
static func stocked(v: Village, r: String) -> bool:
	return v.stored(r) >= target(r)


## The dish to cook next: the cooked kind furthest below its target (as a share of it) that storage has the raw food
## for; [] when everything's stocked or there's nothing raw. [raw, cooked].
static func next(v: Village) -> Array:
	var best := []
	var worst := 1.0
	for r in RECIPES:
		var want := target(r[1])
		if want <= 0 or v.spare(r[0]) <= 0:   # (what's kept for planting isn't cooked)
			continue
		var have := v.stored(r[1])
		if have >= want:
			continue
		var share := have / float(want)
		if best.is_empty() or share < worst:
			worst = share
			best = r
	return best
