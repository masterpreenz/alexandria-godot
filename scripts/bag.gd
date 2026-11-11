class_name Bag
extends RefCounted
## What Miko carries (from Unity's Inventory): resources counted (gold, wood, stone, food...) and her slots. She has
## [constant BASE_SLOTS] of her own, and the bag she wears (a sachet...) adds its own; each piece of gear takes a
## slot, and so does each kind of resource she carries (a stack, however many), gold aside (her purse). With no room
## for a new kind it isn't taken. The slots past her own are the bag's.

signal changed

const COLUMNS := 8
const ROWS := 8
const SIZE := COLUMNS * ROWS
const BASE_SLOTS := 8
## The resources, in Unity's order (the save's stack slots are by this order).
const RESOURCES := ["Gold", "Wood", "Stone", "Seed", "Food", "Tea", "Meal", "Hide", "Crystal", "Jelly", "Candy", "Potato",
	"BakedPotato", "Rabbit", "Bottle", "HpPotion", "ManaPotion", "Carrot", "Cabbage", "Wheat", "Cotton", "CabbageSeed",
	"WheatSeed", "CottonSeed", "Flour", "Bread", "CarrotStew", "CabbageSoup", "Fiber", "Fish", "GrilledFish", "Bait"]

var counts := {}       ## resource -> how many
var items: Array = []  ## SIZE slots: an item's name, or "" (gear)
var stack_slot := {}   ## resource -> the slot its stack shows in
var worn: Array = []   ## what she's wearing (item names): a worn bag adds slots
var bonus_slots := 0   ## more slots from her talents (Hearth's pockets)
var item_data := {}    ## item name -> its data (ui.json's items)


func _init() -> void:
	items.resize(SIZE)
	items.fill("")


func count(resource: String) -> int:
	return int(counts.get(resource, 0))


## Gold is in her purse; everything else takes a slot.
static func slotted(resource: String) -> bool:
	return resource != "Gold"


## How many slots she has: her own, and her worn bag's.
func capacity() -> int:
	var extra := bonus_slots
	for n in worn:
		extra += int(item_data.get(n, {}).get("bagSlots", 0))
	return mini(SIZE, BASE_SLOTS + extra)


## The resource whose stack is in [param slot], or "".
func stack_in(slot: int) -> String:
	for r in stack_slot:
		if stack_slot[r] == slot and count(r) > 0:
			return r
	return ""


## The first slot holding nothing, or -1.
func free_slot() -> int:
	for i in capacity():
		if items[i] == "" and stack_in(i) == "":
			return i
	return -1


func has_room_for(resource: String) -> bool:
	return not slotted(resource) or count(resource) > 0 or free_slot() >= 0


## Adds [param amount] of [param resource]; false (nothing added) when it'd need a new slot and none is free.
func add(resource: String, amount: int) -> bool:
	if amount > 0 and not has_room_for(resource):
		return false
	var had := count(resource)
	counts[resource] = maxi(0, had + amount)
	if slotted(resource):
		if had <= 0 and count(resource) > 0 and (not stack_slot.has(resource) or not _slot_free_for(stack_slot[resource], resource)):
			stack_slot[resource] = free_slot()
	changed.emit()
	return true


func _slot_free_for(slot: int, resource: String) -> bool:
	if slot < 0 or slot >= capacity() or items[slot] != "":
		return false
	var there := stack_in(slot)
	return there == "" or there == resource


## Takes [param amount] of [param resource]; false (nothing taken) if there isn't that much.
func spend(resource: String, amount: int) -> bool:
	if count(resource) < amount:
		return false
	counts[resource] = count(resource) - amount
	changed.emit()
	return true


## Moves (or swaps) what's in slot [param from] to slot [param to].
func move(from: int, to: int) -> void:
	if from == to or to < 0 or to >= capacity():
		return
	var a_item: String = items[from]
	var a_stack := stack_in(from)
	var b_item: String = items[to]
	var b_stack := stack_in(to)
	items[from] = b_item
	items[to] = a_item
	if a_stack != "": stack_slot[a_stack] = to
	if b_stack != "": stack_slot[b_stack] = from
	changed.emit()


## The saved bag (Unity's player.bag: resources, slots by item name, stack slots by resource order) and what she wears.
func from_json(json: String, equipped: Array = []) -> void:
	var d: Dictionary = JSON.parse_string(json)
	counts.clear()
	for r in d.get("resources", []):
		counts[r.resource] = int(r.amount)
	var slots: Array = d.get("slots", [])
	for i in SIZE:
		items[i] = slots[i] if i < slots.size() and slots[i] != null else ""
	stack_slot.clear()
	var stacks: Array = d.get("stackSlots", [])
	for i in mini(stacks.size(), RESOURCES.size()):
		if int(stacks[i]) >= 0:
			stack_slot[RESOURCES[i]] = int(stacks[i])
	worn = equipped
	# Any stack without a slot of its own gets the next free one.
	for r in counts:
		if slotted(r) and count(r) > 0 and not stack_slot.has(r):
			stack_slot[r] = free_slot()
	changed.emit()


## The bag as Unity's player.bag: every resource's amount (in Unity's order), each slot's item, each stack's slot.
func to_json() -> String:
	var res := []
	var stacks := []
	for r in RESOURCES:
		res.append({"resource": r, "amount": count(r)})
		stacks.append(int(stack_slot.get(r, -1)) if count(r) > 0 else int(stack_slot.get(r, -1)))
	return JSON.stringify({"resources": res, "slots": items, "stackSlots": stacks})
