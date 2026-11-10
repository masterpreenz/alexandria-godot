class_name Upkeep
extends Node2D
## Houses wear out. Each house (a roofed room) has a condition, 100 new: it falls slowly all the time, faster in rain,
## storms and snow. The villagers who build repair a worn one (Villager's repairs: wood and stone from storage, more
## for a bigger house). Below [constant LEAKY] the roof leaks (whoever sleeps there rests worse); at 0 it's no
## shelter at all. A bar over a house shows its condition once it wants repair; the village log warns of a bad one.
## Kept by where the house stands (its lowest cell), and saved (world.upkeep).

const WEAR_AN_HOUR := 0.5         ## condition lost each game hour in fair weather
const WEATHER := {GameClock.Weather.RAIN: 2.0, GameClock.Weather.STORM: 3.0, GameClock.Weather.SNOW: 2.0}
const WORN := 70.0                ## under this the villagers repair it, and its bar shows
const LEAKY := 50.0
const BAD := 30.0                 ## the village log warns
const A_REPAIR := 40.0            ## condition a go at it gives back

static var active: Upkeep

var world: World
var condition := {}               ## Vector2i (the house's lowest cell) -> 0..100
var _last_hours := -1.0
var _next_draw := 0.0


func setup(w: World) -> void:
	world = w
	active = self
	z_as_relative = false
	z_index = 3991
	World.keep_lit(self)
	w.add_child(self)


## A house's key: its lowest cell (by x, then y).
static func key_of(cells: Dictionary) -> Vector2i:
	var best := Vector2i(1 << 30, 1 << 30)
	for c in cells:
		if c.x < best.x or (c.x == best.x and c.y < best.y):
			best = c
	return best


## The houses now: [{key, cells, middle (px), condition}].
func houses() -> Array:
	var out := []
	if world.roofs == null:
		return out
	for roof in world.roofs.roofs:
		var cells: Dictionary = roof.cells
		if cells.is_empty():
			continue
		var k := key_of(cells)
		var mid := Vector2.ZERO
		for c in cells:
			mid += world.floors.cell_centre(c)
		out.append({"key": k, "cells": cells, "middle": mid / cells.size(), "condition": float(condition.get(k, 100.0))})
	return out


## The condition of the house [param p] (px) is in; 100 when it's in none.
func condition_at(p: Vector2) -> float:
	var room: Variant = world.roofs.room_on(p) if world.roofs != null else null
	return float(condition.get(key_of(room), 100.0)) if room != null else 100.0


## What a go at repairing a house of [param cells] takes: [wood, stone].
static func cost(cells: Dictionary) -> Array:
	var n := maxi(1, ceili(cells.size() / 2.0))
	return [n, n]


## A repair done on the house keyed [param k]: its condition after.
func repair(k: Vector2i) -> float:
	condition[k] = minf(100.0, float(condition.get(k, 100.0)) + A_REPAIR)
	queue_redraw()
	return float(condition[k])


func _process(_delta: float) -> void:
	var c := world.clock
	if c == null:
		return
	var passed := 0.0 if _last_hours < 0.0 else clampf(c.hours - _last_hours, 0.0, 24.0)
	_last_hours = c.hours
	var now := Time.get_ticks_msec() / 1000.0
	if passed <= 0.0 and now < _next_draw:
		return
	var wear := passed * WEAR_AN_HOUR * float(WEATHER.get(c.weather(), 1.0))
	var seen := {}
	var worst := 100.0
	for h in houses():
		seen[h.key] = true
		condition[h.key] = clampf(float(h.condition) - wear, 0.0, 100.0)
		worst = minf(worst, float(condition[h.key]))
	# Houses pulled down are forgotten.
	for k in condition.keys():
		if not seen.has(k):
			condition.erase(k)
	if worst < BAD and world.village.founded():
		VillageLog.problem("upkeep", "A house is falling into disrepair (%d%%): it needs wood and stone, and someone to build" % roundi(worst),
			VillageLog.Kind.DANGER if worst <= 0.0 else VillageLog.Kind.WARNING)
	if now >= _next_draw:
		_next_draw = now + 0.5
		queue_redraw()


# A bar over each house that wants repair.
func _draw() -> void:
	for h in houses():
		var left := float(h.condition)
		if left >= WORN:
			continue
		var w := 84.0
		var at: Vector2 = (h.middle as Vector2) + Vector2(-w / 2.0, -1.3 * world.px)
		var share := left / 100.0
		var fill := Color(0.92, 0.3, 0.2).lerp(Color(0.95, 0.75, 0.3), clampf((share - 0.25) / 0.45, 0.0, 1.0))
		draw_rect(Rect2(at, Vector2(w, 9)), Color(0.1, 0.06, 0.05, 0.85))
		draw_rect(Rect2(at + Vector2(1, 1), Vector2((w - 2) * share, 7)), fill)
		var f := HudStyle.font("bold")
		if f != null:
			var text := "House %d%%" % roundi(left)
			draw_string_outline(f, at + Vector2(0, -4), text, HORIZONTAL_ALIGNMENT_CENTER, w, 12, 4, Color(0, 0, 0, 0.8))
			draw_string(f, at + Vector2(0, -4), text, HORIZONTAL_ALIGNMENT_CENTER, w, 12, Color(1, 0.93, 0.8))


func to_json() -> String:
	var list := []
	for k in condition:
		list.append({"x": k.x, "y": k.y, "c": snappedf(float(condition[k]), 0.1)})
	return JSON.stringify({"houses": list})


func from_json(json: String) -> void:
	var d: Variant = JSON.parse_string(json)
	condition.clear()
	if d is Dictionary:
		for h in d.get("houses", []):
			condition[Vector2i(int(h.x), int(h.y))] = clampf(float(h.c), 0.0, 100.0)
