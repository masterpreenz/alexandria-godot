class_name HitFx
extends Node
## Flinching from a hit (as Miko does, Unity's HitReaction): the body blinks red twice, fading, and jolts side to side,
## settling. For villagers, monsters and corrupted trees: added beside their art and wading (whose jolt it sets; without
## one, the colour only), [method play] on a hit.

const LENGTH := 0.4
const COLOR := Color(1.0, 0.42, 0.38)
const JOLT := 0.08                ## units, side to side

var art: CanvasItem
var wading: Wading
var px := 128.0
var _since := -1.0
var thud: World                   ## set (the world) for a hit to be heard too (allies: a monster's blow has no sound of its own)


## The sound of a blow landing at [param at]: [param kind] one of Sfx.GROUPS ("blunt" on a wall or barricade,
## "scratch" a monster's claws on Miko, a villager or a shikigami), a take picked at random.
static func sound(w: World, at: Vector2, kind := "blunt") -> void:
	var clip := Sfx.one_of(kind)
	if clip != null and w != null:
		Sfx.play(w, clip, at, 0.45, 0.14)


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
	if thud != null and is_instance_valid(art):
		sound(thud, art.global_position, "scratch")


## The jolt now (px, side to side), for a body that places itself (no wading to carry it); 0 when not flinching.
func jolt_x() -> float:
	if _since < 0.0:
		return 0.0
	var t := _since / LENGTH
	return sin(t * PI * 6.0) * JOLT * (1.0 - t) * px


## Whether it's flinching now (its red over any other tint).
func active() -> bool:
	return _since >= 0.0


# Gone mid-blink (its owner freed): the body back to its own colour.
func _exit_tree() -> void:
	if _since >= 0.0 and is_instance_valid(art):
		art.self_modulate = Color.WHITE


func _process(delta: float) -> void:
	if _since < 0.0 or not is_instance_valid(art):
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
