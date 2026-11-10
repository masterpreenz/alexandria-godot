class_name HitFx
extends Node
## Flinching from a hit (as Miko does, Unity's HitReaction): the body blinks red twice, fading, and jolts side to side,
## settling. For villagers and monsters: added beside their art and wading (whose jolt it sets), [method play] on a hit.

const LENGTH := 0.32
const COLOR := Color(1.0, 0.42, 0.38)
const JOLT := 0.06                ## units, side to side

var art: CanvasItem
var wading: Wading
var px := 128.0
var _since := -1.0


static func add_to(owner_node: Node, body: CanvasItem, wade: Wading, world_px: float) -> HitFx:
	var fx := HitFx.new()
	fx.name = "HitFx"
	fx.art = body
	fx.wading = wade
	fx.px = world_px
	owner_node.add_child(fx)
	return fx


func play() -> void:
	_since = 0.0


## Whether it's flinching now (its red over any other tint).
func active() -> bool:
	return _since >= 0.0


func _process(delta: float) -> void:
	if _since < 0.0 or art == null:
		return
	_since += delta
	var t := _since / LENGTH
	if t >= 1.0:
		_since = -1.0
		art.self_modulate = Color.WHITE
		if wading != null:
			wading.extra.x = 0.0
		return
	var blink := absf(sin(t * PI * 2.0)) * (1.0 - t * 0.5)
	art.self_modulate = Color.WHITE.lerp(COLOR, blink)
	if wading != null:
		wading.extra.x = sin(t * PI * 6.0) * JOLT * (1.0 - t) * px
