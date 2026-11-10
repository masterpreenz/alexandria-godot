class_name Damageable
extends Node2D
## Something in the world that can be hit (from Unity's Damageable): a monster, a training dummy, a corrupted tree. It
## has HP and a side; damage shows as a number rising off it, and an enemy shows an HP bar for a while after it's hit.
## A dummy never falls (it heals back a moment after the last hit); anything else goes when its HP runs out.

signal died
signal damaged(amount: float)

enum Team { ALLY, ENEMY }

static var all: Array[Damageable] = []

var team := Team.ENEMY
var max_hp := 100.0
var hp := 100.0
var radius := 0.35 * 128.0    ## px: how far from its feet it can be hit (its body on the ground)
var height := 128.0           ## px: where damage numbers rise from, above the feet
var dummy := false
var hit_by_player := false
var shields := {}             ## source -> shield soaking damage first (a shield ward's)
var world: World
var _last_hit := -99.0
var _bar_until := -1.0


func setup(w: World, side: int, hp_max: float, body_radius: float, body_height: float) -> void:
	world = w
	@warning_ignore("int_as_enum_without_cast")
	team = side
	max_hp = maxf(1.0, hp_max)
	hp = max_hp
	radius = body_radius
	height = body_height


func _enter_tree() -> void:
	all.append(self)
	World.keep_lit(self)   # its HP bar bright at night too


func _exit_tree() -> void:
	all.erase(self)


func alive() -> bool:
	return hp > 0.0


## How far [param p] is from its body's edge on the ground (the iso ground is half as tall).
func ground_distance(p: Vector2) -> float:
	var d := p - global_position
	return maxf(0.0, Vector2(d.x, d.y * 2.0).length() - radius)


## Takes [param amount] damage, showing the number; [param by_player]: Miko dealt it.
## Takes [param amount]; [param crit]: a critical hit, its number big, yellow ringed in red.
func hurt(amount: float, by_player := false, crit := false) -> void:
	if not alive() or amount <= 0.0:
		return
	if by_player:
		hit_by_player = true
	_last_hit = Time.get_ticks_msec() / 1000.0
	for k in shields.keys():
		var take := minf(shields[k], amount)
		shields[k] -= take
		amount -= take
		if shields[k] <= 0.01:
			shields.erase(k)
	if amount <= 0.0:
		return
	if crit:
		FloatingText.spawn(world, str(roundi(amount)), global_position + Vector2(0, -height - 0.1 * world.px), Color(1.0, 0.9, 0.2), 34, 1.4, Color(0.85, 0.08, 0.05))
	else:
		FloatingText.spawn(world, str(roundi(amount)), global_position + Vector2(0, -height), Color(1, 0.82, 0.35))
	hp = maxf(1.0, hp - amount) if dummy else maxf(0.0, hp - amount)
	damaged.emit(amount)
	if team == Team.ENEMY and hp > 0.0:
		_bar_until = _last_hit + 3.0
		queue_redraw()
	if hp <= 0.0:
		died.emit()
		queue_free()


func set_shield(source, amount: float) -> void:
	if amount <= 0.0:
		shields.erase(source)
	else:
		shields[source] = amount


func shield_from(source) -> float:
	return float(shields.get(source, 0.0))


func heal(amount: float) -> void:
	if alive() and amount > 0.0:
		hp = minf(max_hp, hp + amount)
		queue_redraw()


## Hurts everyone on [param side] within [param area] (px, across the ground) of [param at].
static func hit_around(at: Vector2, area: float, amount: float, side: int, by_player := false) -> int:
	var n := 0
	for d in all.duplicate():
		if is_instance_valid(d) and d.team == side and d.alive() and d.ground_distance(at) <= area:
			d.hurt(amount, by_player)
			n += 1
	return n


## The nearest of [param side] within [param reach] of [param at], or null.
static func nearest(at: Vector2, reach: float, side: int) -> Damageable:
	var best: Damageable = null
	var best_d := reach
	for d in all:
		if d.team != side or not d.alive():
			continue
		var g := d.ground_distance(at)
		if g < best_d:
			best_d = g
			best = d
	return best


func _process(delta: float) -> void:
	var __t := Time.get_ticks_usec()
	_process_timed(delta)
	Perf.add(&"damageable.process", __t)


func _process_timed(_delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if dummy and hp < max_hp and now - _last_hit > 3.0:
		hp = max_hp
	if _bar_until > 0.0 and now > _bar_until:
		_bar_until = -1.0
		queue_redraw()


# The HP bar over an enemy for a while after it's hit.
func _draw() -> void:
	if _bar_until < 0.0:
		return
	var w := 64.0
	var at := Vector2(-w / 2.0, -height - 22.0)
	draw_rect(Rect2(at, Vector2(w, 8)), Color(0.1, 0.06, 0.05, 0.85))
	draw_rect(Rect2(at + Vector2(1, 1), Vector2((w - 2) * hp / max_hp, 6)), Color(0.85, 0.2, 0.18))
