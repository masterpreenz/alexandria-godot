class_name Bag
extends RefCounted
## What Miko carries, by resource (the start of Unity's Inventory: slots, gear and the soft caps come with the bag UI).

signal changed

var counts := {}


func add(resource: String, amount: int) -> void:
	counts[resource] = int(counts.get(resource, 0)) + amount
	changed.emit()


func count(resource: String) -> int:
	return int(counts.get(resource, 0))


## The saved bag (Unity's player.bag section): its resources.
func from_json(json: String) -> void:
	var d: Dictionary = JSON.parse_string(json)
	counts.clear()
	for r in d.get("resources", []):
		counts[r.resource] = int(r.amount)
	changed.emit()
