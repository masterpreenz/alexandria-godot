class_name Telegraph
extends Node2D
## Where a charge or a leap is about to go, shown on the ground before it comes (a boar's charge, a mutated wolf's
## leap, any to come): a strip from the attacker out to where it will end, pale red, filling dark red from the
## attacker's end as the moment nears (full: it goes). Laid flat on the ground, under everyone. The attacker keeps it
## pointed (point) and sets how full it is (fill), and frees it when it's away.

const PALE := Color(1.0, 0.35, 0.3, 0.3)
const RIM := Color(1.0, 0.4, 0.35, 0.8)
const DARK := Color(0.85, 0.05, 0.05, 0.7)

static var live: Array[Telegraph] = []   ## every strip on the ground now (companions look for one under them)

var world: World
var from := Vector2.ZERO          ## where it starts (px): the attacker's feet
var dir := Vector2.RIGHT          ## which way, on screen
var length := 0.0                 ## how far, on screen (px)
var width := 0.0                  ## how wide, across the ground (px, as a unit's width)
var fill := 0.0                   ## 0 just shown, 1 about to go


## A new strip [param width_units] wide (in units, across the ground), on the ground of [param w].
static func make(w: World, width_units: float) -> Telegraph:
	var t := Telegraph.new()
	t.world = w
	t.name = "Telegraph"
	t.width = width_units * w.px
	t.z_as_relative = false
	t.visibility_layer |= LightMap.UNLIT_LAYER   # (as bright at night: not dimmed by the dark)
	w.add_ground_layer(t, -9964)   # (over the village's border and build mode's grid, under everyone standing)
	return t


func _enter_tree() -> void:
	live.append(self)


func _exit_tree() -> void:
	live.erase(self)


## Points it from [param at] towards [param to] (px), at most [param most] px long.
func point(at: Vector2, to: Vector2, most: float) -> void:
	from = at
	var d := to - at
	dir = d.normalized() if d.length_squared() > 1.0 else dir
	length = minf(d.length(), most)
	queue_redraw()


## Where it ends (px).
func end() -> Vector2:
	return from + dir * length


## Whether [param p] (px) is on the strip.
func covers(p: Vector2) -> bool:
	var g := _ground(p - from)
	var gd := _ground(dir * length)
	var along := g.dot(gd.normalized())
	if along < -width * 0.3 or along > gd.length() + width * 0.3:
		return false
	return absf(g.dot(Vector2(-gd.y, gd.x).normalized())) <= width * 0.5


func set_fill(f: float) -> void:
	fill = clampf(f, 0.0, 1.0)
	queue_redraw()


# On-screen px to ground px (the ground's depth is drawn at half height).
static func _ground(v: Vector2) -> Vector2:
	return Vector2(v.x, v.y * 2.0)


static func _screen(v: Vector2) -> Vector2:
	return Vector2(v.x, v.y * 0.5)


# The strip's four corners (on screen) from the attacker's end out to [param share] of its length.
func _corners(share: float) -> PackedVector2Array:
	var gd := _ground(dir * length)
	var across := Vector2(-gd.y, gd.x).normalized() * width * 0.5
	var out := gd * share
	return PackedVector2Array([from + _screen(across), from + _screen(across + out), from + _screen(-across + out), from + _screen(-across)])


func _draw() -> void:
	if length < 1.0:
		return
	var whole := _corners(1.0)
	draw_colored_polygon(whole, PALE)
	if fill > 0.01:
		draw_colored_polygon(_corners(fill), DARK)
	var rim := whole.duplicate()
	rim.append(whole[0])
	draw_polyline(rim, RIM, 0.025 * world.px, true)
