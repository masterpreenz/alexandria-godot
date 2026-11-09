class_name Doors
extends Node
## Doors and Miko (from Unity's DoorInteractor): a door swings open by itself as she comes up to it, and shuts again
## once she's moved off (only the doors it opened for her: one a villager opened, or one kept open, it leaves be). A
## door left standing open with no one near it for a few seconds swings shut (at bedtime even ones kept open). At a
## house's door, O sets the house to keep its doors open (or not), opening (or closing) them all.

static var open_sound: AudioStream
static var close_sound: AudioStream
static var volume := 0.8
static var _world: World

var world: World
var miko: Miko
var s: Dictionary
var opened := {}                   ## door key -> Edge: opened for her
var alone := {}                    ## door key -> since when it's stood open with no one near
var doors: Array = []              ## every door's starting edge
var prompt: Label
var _next_check := 0.0
var _o := false


func setup(w: World, who: Miko, settings: Dictionary, hud: Node) -> void:
	world = w
	_world = w
	miko = who
	s = settings
	volume = float(s.get("volume", 0.8))
	for k in ["openSound", "closeSound"]:
		var path: Variant = s.get(k)
		if path is String and ResourceLoader.exists(path):
			if k == "openSound": open_sound = load(path)
			else: close_sound = load(path)
	prompt = HudStyle.label("", 16, "bold")
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	prompt.offset_top = -180
	prompt.offset_bottom = -150
	prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	prompt.visible = false
	hud.add_child(prompt)


## A door's sound at [param at] (opening or shutting).
static func sound(open: bool, at: Vector2) -> void:
	var clip := open_sound if open else close_sound
	if clip != null and _world != null:
		Sfx.play(_world, clip, at, volume)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_O:
		_o = true


func _toggle(door: WallMap.Edge, open: bool) -> void:
	world.walls.toggle(door)
	sound(open, world.walls.edge_middle(door))


func _villager_near(mid: Vector2, within: float) -> bool:
	for v in Villager.all:
		if v.visible and v.position.distance_to(mid) < within * world.px:
			return true
	return false


func _process(_delta: float) -> void:
	var walls := world.walls
	if walls == null:
		return
	var o := _o
	_o = false
	_keep_open_prompt(o)
	var t := Villager.now()
	if t < _next_check:
		return
	_next_check = t + 0.1
	doors.clear()
	for k in walls.walls:
		var type: String = walls.walls[k]
		if walls.types[type].toggle != "":
			doors.append(WallMap.Edge.new(Vector2i(k.x, k.y), k.z == 1))
	var px := world.px
	var bedtime := Villager.sleep_hours(world)
	# A door left standing open (not kept open) with no one near it for a few seconds swings shut.
	for door in doors:
		var key: Vector3i = door.key()
		var mid := walls.edge_middle(door)
		if not walls.is_open(door) or (walls.kept_open(door) and not bedtime) or miko.position.distance_to(mid) < 1.2 * px or _villager_near(mid, 1.2):
			alone.erase(key)
			continue
		if not alone.has(key):
			alone[key] = t
			continue
		if t - float(alone[key]) < 3.0:
			continue
		alone.erase(key)
		opened.erase(key)
		_toggle(door, false)
	# Opening as she comes up to one; shutting what it opened for her once she's off.
	for door in doors:
		var key: Vector3i = door.key()
		var open := walls.is_open(door)
		var mid := walls.edge_middle(door)
		var near := miko.position.distance_to(mid) < (1.1 if open else float(s.get("range", 0.6)) + 0.3) * px
		if near and not open:
			_toggle(door, true)
			opened[key] = door
		elif not near and open and opened.has(key):
			opened.erase(key)
			# Kept open (by day), or someone in the doorway: left as it is.
			if (walls.kept_open(door) and not bedtime) or _villager_near(mid, 0.7):
				continue
			_toggle(door, false)
		elif not open:
			opened.erase(key)


# At a house's door: O keeps all its doors open, or lets them close again.
func _keep_open_prompt(pressed: bool) -> void:
	var walls := world.walls
	if world.roofs == null or miko.locked:
		prompt.visible = false
		return
	var best: WallMap.Edge = null
	var best_d := (float(s.get("range", 0.6)) + 0.5) * world.px
	for door in doors:
		var d := miko.position.distance_to(walls.edge_middle(door))
		if d < best_d:
			best_d = d
			best = door
	if best == null:
		prompt.visible = false
		return
	var a := best.vertex - (Vector2i(1, 0) if best.along_y else Vector2i(0, 1))
	var room: Variant = world.roofs.room_on(world.floors.cell_centre(a))
	if room == null:
		room = world.roofs.room_on(world.floors.cell_centre(best.vertex))
	if room == null:
		prompt.visible = false
		return
	var kept := walls.kept_open(best)
	prompt.visible = true
	prompt.text = "O  " + ("Let the doors close" if kept else "Keep the doors open")
	if not pressed:
		return
	for door in VillagerRoute.doors_of(walls, room):
		walls.set_kept_open(door, not kept)
		var mid := walls.edge_middle(door)
		if not kept and not walls.is_open(door):
			_toggle(door, true)
		elif kept and walls.is_open(door) and not opened.has(door.key()) and not _villager_near(mid, 0.7):
			_toggle(door, false)
	FloatingText.spawn(world, "The doors will close" if kept else "Doors kept open", miko.position + Vector2(0, -1.2 * world.px), HudStyle.color("text"))
