class_name Village
extends RefCounted
## The village (from Unity's Village): founded once its banner stands; a square of tiles round the banner's (bigger at
## each tier), and the blocks added on, in tiles from the banner's tile. What it covers, as the mist, the spawners and
## the villagers ask it.
##
## Its storage: what's put in the chests in the village (the stash), each chest holding [method base_cap] of each
## resource (twice that in a storage house, a room with chests and no beds) and some item slots. In the village, Miko
## can use what's stored as if it were in her bag ([method have], [method take]); what she gets that her bag can't
## take goes to storage ([method accept]); what villagers bring in goes there too ([method deposit]).

signal changed

const ITEM_SLOTS_PER_CHEST := 8
const SHELTER_REST := 1.25
const SHELTER_COMFORT := 0.15

var world: World
var radii: Array = [8, 11, 15, 20]
var tier := 0
var blocks: Array[Rect2i] = []
var stash := {}             ## resource -> how many are stored
var items: Array = []       ## stored gear (item names)
var crystal_names: Array = []  ## [{x, y, name}]: what each teleport crystal is called


func _init(w: World) -> void:
	world = w


## Loads the saved village section (its tier and blocks; the banner is a prop).
func from_json(json: String) -> void:
	var d: Dictionary = JSON.parse_string(json)
	tier = int(d.get("tier", 0))
	blocks.clear()
	for b in d.get("blocks", []):
		blocks.append(Rect2i(int(b.x), int(b.y), int(b.w), int(b.h)))
	stash.clear()
	for a in d.get("stash", []):
		if int(a.amount) > 0:
			stash[a.resource] = int(a.amount)
	items = d.get("items", []).duplicate()
	crystal_names = d.get("crystalNames", [])
	changed.emit()


func to_json() -> String:
	var list := []
	for r in Bag.RESOURCES:
		list.append({"resource": r, "amount": int(stash.get(r, 0))})
	var bl := []
	for b in blocks:
		bl.append({"x": b.position.x, "y": b.position.y, "w": b.size.x, "h": b.size.y})
	return JSON.stringify({"tier": tier, "stash": list, "items": items, "crystalNames": crystal_names, "blocks": bl})


# ---- Storage ----

## What a bag (and each chest) holds of [param r] at most.
static func base_cap(r: String) -> int:
	match r:
		"Gold": return 1000
		"Wood", "Stone": return 100
	return 40


## The chests standing in the village.
func chests() -> Array:
	return world.props_named("Chest").filter(func(at): return contains(at))


## How many chests' worth a chest at [param at] counts for: two in a storage house.
func _multiplier(at: Vector2) -> int:
	return 2 if room_kind_at(at) == "Storage" else 1


## How much of [param r] the village's chests hold at most.
func stash_cap(r: String) -> int:
	var total := 0
	for at in chests():
		total += base_cap(r) * _multiplier(at)
	return total


func item_slots() -> int:
	var total := 0
	for at in chests():
		total += ITEM_SLOTS_PER_CHEST * _multiplier(at)
	return total


func stored(r: String) -> int:
	return int(stash.get(r, 0))


## Whether [param who] (Miko) is in the village, where she can use what's stored.
func in_reach(who: Node2D) -> bool:
	return who != null and contains(who.position)


## What she has of [param r]: her bag's, and storage's while she's in the village.
func have(bag: Bag, who: Node2D, r: String) -> int:
	return (bag.count(r) if bag != null else 0) + (stored(r) if in_reach(who) else 0)


## Takes [param amount] of [param r] from her bag first, the rest from storage (in the village); false (nothing taken)
## if there isn't that much.
func take(bag: Bag, who: Node2D, r: String, amount: int) -> bool:
	if amount <= 0:
		return true
	if have(bag, who, r) < amount:
		return false
	var from_bag := mini(amount, bag.count(r) if bag != null else 0)
	if from_bag > 0:
		bag.spend(r, from_bag)
	if amount > from_bag:
		take_from_stash(r, amount - from_bag)
	return true


func take_from_stash(r: String, amount: int) -> bool:
	if amount <= 0:
		return true
	if stored(r) < amount:
		return false
	stash[r] = stored(r) - amount
	changed.emit()
	return true


## Puts [param amount] of [param r] straight into storage (a gift, a villager's haul past the cap is up to the caller).
func put_in_stash(r: String, amount: int) -> void:
	if amount > 0:
		stash[r] = stored(r) + amount
		changed.emit()


## Gives her [param amount] of [param r]: into her bag as far as its limit (and a slot), the rest into storage when
## she's in the village; how many were taken.
func accept(bag: Bag, who: Node2D, r: String, amount: int) -> int:
	if bag == null or amount <= 0:
		return 0
	var to_bag := clampi(base_cap(r) - bag.count(r), 0, amount) if bag.has_room_for(r) else 0
	if to_bag > 0:
		bag.add(r, to_bag)
	var rest := amount - to_bag
	var to_stash := clampi(stash_cap(r) - stored(r), 0, rest) if in_reach(who) else 0
	if to_stash > 0:
		stash[r] = stored(r) + to_stash
		changed.emit()
		FloatingText.spawn(world, "+%d %s to storage" % [to_stash, UiKit.resource_name(r)], who.position + Vector2(0, -1.9 * world.px), Color(0.75, 0.85, 1.0))
	return to_bag + to_stash


## Gives her [param amount] of [param r]; what she can't take falls at [param at].
func give(bag: Bag, who: Node2D, r: String, amount: int, at: Vector2) -> void:
	var left := amount - accept(bag, who, r, amount)
	if left > 0:
		Pickup.drop(world, r, left, at)


## A villager's haul into storage, up to its cap; the rest falls at [param at]. How many went in.
func deposit(r: String, amount: int, at: Vector2) -> int:
	if amount <= 0:
		return 0
	var n := clampi(stash_cap(r) - stored(r), 0, amount) if founded() else 0
	if n > 0:
		stash[r] = stored(r) + n
		changed.emit()
	if amount > n:
		Pickup.drop(world, r, amount - n, at)
	return n


## Moves up to [param amount] of [param r] from her bag into storage; how many went.
func store(bag: Bag, r: String, amount: int) -> int:
	var n := mini(amount, mini(bag.count(r), maxi(0, stash_cap(r) - stored(r))))
	if n <= 0:
		return 0
	bag.spend(r, n)
	stash[r] = stored(r) + n
	changed.emit()
	return n


## Moves up to [param amount] of [param r] from storage into her bag; how many came.
func withdraw(bag: Bag, r: String, amount: int) -> int:
	var n := mini(amount, mini(stored(r), maxi(0, base_cap(r) - bag.count(r))))
	if n <= 0 or not bag.add(r, n):
		return 0
	stash[r] = stored(r) - n
	changed.emit()
	return n


# ---- Rooms ----

## What kind of room [param p] is in: "Storage" (chests, no beds), "Shelter" (beds, no chests), "House" (both), or "".
func room_kind_at(p: Vector2) -> String:
	if world.roofs == null:
		return ""
	var cells: Variant = world.roofs.room_on(p)
	if cells == null:
		return ""
	var chests_in := 0
	var beds_in := 0
	for at in world.props_named("Chest"):
		if cells.has(world.floors.cell_at(at)): chests_in += 1
	for type in ["Bedroll", "LeafBed", "WoodenBed"]:
		for at in world.props_named(type):
			if cells.has(world.floors.cell_at(at)): beds_in += 1
	if chests_in > 0 and beds_in == 0: return "Storage"
	if beds_in > 0 and chests_in == 0: return "Shelter"
	return "House" if chests_in + beds_in > 0 else ""


## Founded: its banner stands somewhere.
func founded() -> bool:
	return not world.props_named("TownBanner").is_empty()


## Where its banner stands (the middle of the village), or the map's middle before it's founded.
func centre() -> Vector2:
	var banners: Array = world.props_named("TownBanner")
	return banners[0] if not banners.is_empty() else Vector2.ZERO


## Half the square's side, in tiles (the banner's own tile counts half): its edge from the middle.
func half_size() -> float:
	_update()
	return float(radii[clampi(tier, 0, radii.size() - 1)]) + 0.5 if _founded else 0.0


var _cache_version := -1
var _founded := false
var _centre_cell := Vector2.ZERO

# The banner looked up once each time the props change, not for every spot asked about.
func _update() -> void:
	if world.props.version == _cache_version:
		return
	_cache_version = world.props.version
	_founded = founded()
	_centre_cell = world.floors.fractional_cell(centre())


## Whether [param p] is inside the village, or within [param margin] tiles of it.
func contains(p: Vector2, margin := 0.0) -> bool:
	_update()
	if not _founded:
		return false
	var d := world.floors.fractional_cell(p) - _centre_cell
	if maxf(absf(d.x), absf(d.y)) <= half_size() + margin:
		return true
	for r in blocks:
		if d.x >= r.position.x - 0.5 - margin and d.x <= r.end.x - 0.5 + margin \
				and d.y >= r.position.y - 0.5 - margin and d.y <= r.end.y - 0.5 + margin:
			return true
	return false


## A box (px) round everything the village covers, [param margin] tiles out.
func bounds(margin := 0.0) -> Rect2:
	var c := world.floors.fractional_cell(centre())
	var h := half_size() + margin
	var corners := [Vector2(-h, -h), Vector2(h, -h), Vector2(-h, h), Vector2(h, h)]
	for r in blocks:
		for k in [Vector2(r.position.x - 0.5 - margin, r.position.y - 0.5 - margin), Vector2(r.end.x - 0.5 + margin, r.end.y - 0.5 + margin),
				Vector2(r.position.x - 0.5 - margin, r.end.y - 0.5 + margin), Vector2(r.end.x - 0.5 + margin, r.position.y - 0.5 - margin)]:
			corners.append(k)
	var box := Rect2(world.floors.corner(c + corners[0]), Vector2.ZERO)
	for k in corners:
		box = box.expand(world.floors.corner(c + k))
	return box


## What its shape is, as a string: changes when it does.
func shape_key() -> String:
	if not founded():
		return "-"
	var c := centre()
	var s := "%.0f,%.0f,%d" % [c.x, c.y, tier]
	for b in blocks:
		s += "|%d,%d,%d,%d" % [b.position.x, b.position.y, b.size.x, b.size.y]
	return s
