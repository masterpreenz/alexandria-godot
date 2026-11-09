class_name Village
extends RefCounted
## The village's extent (from Unity's Village): founded once its banner stands; a square of tiles round the banner's
## (bigger at each tier), and the blocks added on, in tiles from the banner's tile. What it covers, as the mist, the
## spawners and the villagers ask it. (Its stash, items and people come with phase 4.)

var world: World
var radii: Array = [8, 11, 15, 20]
var tier := 0
var blocks: Array[Rect2i] = []


func _init(w: World) -> void:
	world = w


## Loads the saved village section (its tier and blocks; the banner is a prop).
func from_json(json: String) -> void:
	var d: Dictionary = JSON.parse_string(json)
	tier = int(d.get("tier", 0))
	blocks.clear()
	for b in d.get("blocks", []):
		blocks.append(Rect2i(int(b.x), int(b.y), int(b.w), int(b.h)))


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
