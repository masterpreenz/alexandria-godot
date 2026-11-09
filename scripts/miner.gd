class_name Miner
extends Node
## Lets Miko gather (from Unity's Miner): near a rock "Press E to mine" (or a tree, "Press E to chop") shows; E starts
## swinging the pickaxe (or axe) at it, each strike knocking chunks off it to pick up, until it runs out, she moves, or
## E is pressed again. Her tools swing slower than her other animations: heavy work. A felled tree sometimes drops a
## seed. Doors nearby take E first.

var world: World
var miko: Miko
var data: Dictionary
var target: Gatherable
var _last_frame := -1
var _started_frame := -1
var _pickaxe: AudioStream
var _axe: AudioStream
var prompt: Label


func setup(w: World, who: Miko, d: Dictionary, hud: CanvasLayer) -> void:
	world = w
	miko = who
	data = d
	Gatherable.log_drop = int(d.logDrop)
	if d.treeFall != "":
		Gatherable.fall_sound = load(d.treeFall)
	Gatherable.fall_volume = d.treeFallVolume
	if d.pickaxe != "": _pickaxe = load(d.pickaxe)
	if d.axe != "": _axe = load(d.axe)
	prompt = Label.new()
	prompt.add_theme_font_size_override("font_size", 20)
	prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	prompt.add_theme_constant_override("outline_size", 6)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	prompt.offset_top = -120
	prompt.offset_bottom = -90
	prompt.offset_left = -300
	prompt.offset_right = 300
	prompt.visible = false
	hud.add_child(prompt)


func is_mining() -> bool:
	return target != null


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E:
		_pressed = true


var _pressed := false


func _process(_delta: float) -> void:
	var pressed := _pressed and Engine.get_process_frames() != _started_frame
	_pressed = false
	var door_near := world.walls != null and not world.walls.nearest_door(miko.position, 0.6 * world.px).is_empty()
	if is_mining():
		if miko.moving or pressed or target.depleted():
			_stop()
			return
		var frame := miko.action_frame()
		var axe := target.axe
		var loop := maxi(1, (data.chopDown if axe else data.mineDown).size())
		for f in range(_last_frame + 1, frame + 1):
			for s in (data.chopStrikeFrames if axe else data.strikeFrames):
				if f % loop == int(s):
					_hit()
		_last_frame = frame
		_show("%s  ·  %d left   (move or E to stop)" % ["Chopping" if axe else "Mining", target.remaining()])
		return
	# A rabbit or a pen in reach takes E (RabbitHands) before a tree or rock does.
	var hands: RabbitHands = miko.get_node_or_null("RabbitHands")
	var rabbit_near := hands != null and hands.claims(miko.position)
	# So does a fire to light or cook at, or a farm plot.
	for n in ["Fires", "Farming"]:
		var other: Node = miko.get_node_or_null(n)
		if other != null and other.claims(miko.position):
			rabbit_near = true
	var near: Gatherable = null if door_near or rabbit_near else Gatherable.nearest(miko.position, float(data.range))
	if near == null:
		_show("")
		return
	_show("Press E to chop" if near.axe else "Press E to mine")
	if pressed:
		_begin(near)


func _begin(spot: Gatherable) -> void:
	target = spot
	_last_frame = -1
	_started_frame = Engine.get_process_frames()
	var axe := spot.axe
	var fps: float = float(data.chopFps) * float(data.chopPace) if axe else float(data.fps) * float(data.minePace)
	miko.play_action(data.chopDown if axe else data.mineDown, data.chopUp if axe else data.mineUp, fps, spot.foot - miko.position)


func _stop() -> void:
	target = null
	miko.end_action()
	_show("")


func _hit() -> void:
	if target == null:
		return
	Sfx.play(world, _axe if target.axe else _pickaxe, target.foot, float(data.volume), float(data.pitchJitter))
	var got := target.strike()
	if got <= 0:
		return
	# Chunks fly off the rock (logs off the tree), to be picked up.
	var log_drop := int(data.logDrop)
	var wood := target.resource == "Wood" and log_drop >= 0
	var sprite := log_drop if wood else (int(target.data.chunk) if int(target.data.chunk) >= 0 else int(data.stoneChunk))
	for i in got:
		Pickup.launch(world, target.resource, 1, sprite, target.chunk_point(), 1.0 if wood else float(target.data.chunkScale))
	# A felled tree sometimes drops a seed (no seed art yet: a log stands in until the item icons come over).
	if target.axe and target.depleted() and randf() < float(data.seedChance):
		Pickup.launch(world, "Seed", 1, sprite, target.foot + Vector2(0, -0.3 * world.px), 0.6)


func _show(text: String) -> void:
	prompt.text = text
	prompt.visible = text != ""
