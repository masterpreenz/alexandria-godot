class_name TreePlanter
extends Node
## Planting trees (from Unity's TreePlanter): T plants a seed on open grass just ahead of Miko, which grows (a sapling,
## a young tree, a mature one: see [Gatherable]) into a tree to chop. Felled trees drop seeds. Near a growing tree a
## label says how long until it grows up. Planted trees are kept in the save (world.planted).

const AHEAD := 0.55      ## units ahead of her
const ROOM := 0.75       ## units a tree needs from other trees and rocks

var world: World
var miko: Miko
var kinds: Array = []    ## the trees a seed can grow into (spots from gather.json)
var tree_wood := 5
var label: Label
var _t := false


func setup(w: World, who: Miko, hud: Node) -> void:
	world = w
	miko = who
	var gd: Dictionary = w._load_json("res://data/gather.json") if FileAccess.file_exists("res://data/gather.json") else {}
	tree_wood = int(gd.get("miner", {}).get("treeWood", 5))
	# One of each kind of tree on the map (by its picture), the plainest of each.
	var seen := {}
	for s in gd.get("spots", []):
		if int(s.tool) == 1 and not seen.has(int(s.s)):
			seen[int(s.s)] = true
			kinds.append(s)
	label = HudStyle.label("", 13, "bold", Color(0.75, 0.95, 0.6))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.visible = false
	hud.add_child(label)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_T:
		_t = true


func _process(delta: float) -> void:
	var __t := Time.get_ticks_usec()
	_process_timed(delta)
	Perf.add(&"tree_planter.process", __t)


func _process_timed(_delta: float) -> void:
	var pressed := _t
	_t = false
	_show_growth()
	if pressed and not miko.locked and not BuildMode.is_open() and not CharacterPanel.up():
		try_plant()


func _facing() -> Vector2:
	var v := miko.velocity
	if v.length_squared() > 1.0:
		return v.normalized()
	return Vector2(1.0 if miko.facing_right else -1.0, -1.0 if miko.facing_up else 1.0).normalized()


## Plants a seed ahead of her if there's one and room; says why not otherwise.
func try_plant() -> bool:
	var f := _facing()
	var at := miko.position + Vector2(f.x, f.y * 0.5) * AHEAD * world.px
	if miko.bag.count("Seed") < 1:
		_say("No seeds", at)
		return false
	var why := why_not(at)
	if why != "":
		_say(why, at)
		return false
	plant_at(at)
	miko.bag.spend("Seed", 1)
	var left := miko.bag.count("Seed")
	_say("Planted a seed (%d left)" % left, at)
	return true


## Plants a sapling on the tile at [param at] (no seed taken).
func plant_at(at: Vector2, hours := -1.0) -> Gatherable:
	if kinds.is_empty():
		return null
	var cell := world.floors.cell_at(at)
	var spot := world.floors.cell_centre(cell) + Vector2(randf_range(-0.12, 0.12), randf_range(-0.06, 0.06)) * world.px
	return Gatherable.plant(world, kinds.pick_random(), spot, tree_wood, world.clock.hours if hours < 0.0 else hours)


## Why a tree can't go at [param at], or "": grass only, room from other trees and rocks, nothing solid there.
func why_not(at: Vector2) -> String:
	var f := world.floors
	var cell := f.cell_at(at)
	if not f.in_bounds(cell) or f.get_floor(cell) != f.base_floor or f.get_laid(cell) != "" or world.water_depth(f.cell_centre(cell)) > 0.0:
		return "Trees only grow on grass"
	if world.props.get_prop(cell, PropMap.Slot.TALL) != "":
		return "Too close to another tree"
	var centre := f.cell_centre(cell)
	for g in Gatherable.all:
		if is_instance_valid(g) and g.left + g.stone > 0 and g.foot.distance_to(centre) < ROOM * world.px:
			return "Too close to another tree" if g.axe else "Too close to a rock"
	if world.village.contains(centre) and world.roofs != null and world.roofs.covers(centre):
		return "Something's in the way"
	# Walls, water banks, buildings: anything solid there.
	var q := PhysicsPointQueryParameters2D.new()
	q.position = centre
	q.collision_mask = 1
	for hit in world.get_world_2d().direct_space_state.intersect_point(q, 4):
		var c: Object = hit.get("collider")
		if c is StaticBody2D and not (c.get_parent() is Gatherable):
			return "Something's in the way"
	return ""


func _say(text: String, at: Vector2) -> void:
	FloatingText.spawn(world, text, at + Vector2(0, -0.6 * world.px), Color(0.75, 0.95, 0.6))


# Near a tree still growing, how long until it grows up.
func _show_growth() -> void:
	var near: Gatherable = null
	var best := 1.1 * world.px
	for g in Gatherable.all:
		if not is_instance_valid(g) or g.planted_at < 0.0 or g.hours_to_next() <= 0.0 or g._fall >= 0.0:
			continue
		var d := g.foot.distance_to(miko.position)
		if d < best:
			best = d
			near = g
	label.visible = near != null
	if near == null:
		return
	var hours := maxi(1, ceili(near.hours_to_next()))
	label.text = ("Sapling  ·  young tree in %dh" % hours) if near.sapling() else ("Young tree  ·  fully grown in %dh" % hours)
	label.reset_size()
	var xf := get_viewport().get_canvas_transform()
	var top := xf * (near.foot + Vector2(0, -near.tree_height() * 0.6 - 0.4 * world.px))
	label.position = top - Vector2(label.size.x / 2.0, label.size.y)


## The planted trees, as the save keeps them (units, y up; when each was planted, in game hours; its kind).
func to_json() -> String:
	var list := []
	for g in Gatherable.all:
		if is_instance_valid(g) and g.planted_at >= 0.0 and g._fall < 0.0 and (g.left > 0 or g.sapling()):
			list.append({"x": g.foot.x / world.px, "y": -g.foot.y / world.px, "plantedAt": g.planted_at, "s": int(g.data.s)})
	return JSON.stringify({"trees": list})


func from_json(json: String) -> void:
	var d: Variant = JSON.parse_string(json)
	if not d is Dictionary:
		return
	for t in d.get("trees", []):
		var kind := {}
		for k in kinds:
			if int(k.s) == int(t.get("s", -1)):
				kind = k
		if kind.is_empty():
			kind = kinds[0] if not kinds.is_empty() else {}
		if kind.is_empty():
			continue
		Gatherable.plant(world, kind, Vector2(float(t.x) * world.px, -float(t.y) * world.px), tree_wood, float(t.plantedAt))
