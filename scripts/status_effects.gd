class_name StatusEffects
extends Node2D
## What lingers on a monster after a spell has hit it: frostbite (ice: slowed, and the cold biting at it a while) or a
## burn (fire: the flames eating at it a while). Which spells leave what goes by their element (combat.json's
## "statuses"), so a new element only needs its entry there. Each lasting effect is held once (hit again, it's topped
## up: the longer time, the harder bite and the deeper slow kept, never piled up); frozen ground adds a second, harder
## frostbite of its own while the monster stands on it. Shown on the monster as a tint over its art (Creature's
## paint_flash) and motes about it (frost glinting, flames licking up); the bites come every half second, their numbers
## in the effect's colour, without the flinch a blow brings.

const TICK := 0.5                ## seconds between bites

static var _kinds := {}          ## name -> settings (combat.json "statuses")

var target: Damageable
var by_player := false            ## Sera (or her side) put it on: what it bites counts as hers
var effects := {}                ## key -> {kind, until, dps, slow}
var _next_tick := 0.0
var _motes := {}                 ## kind -> CPUParticles2D
var _age := 0.0


## Every lasting effect's settings, by name (combat.json's "statuses").
static func kinds() -> Dictionary:
	if _kinds.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/combat.json"))
		if d is Dictionary:
			_kinds = (d as Dictionary).get("statuses", {})
		_kinds.erase("_about")
	return _kinds


## The lasting effect a spell of [param element] leaves ("" for none).
static func kind_for(element: String) -> String:
	var all_kinds := kinds()
	for k in all_kinds:
		if str(all_kinds[k].get("element", "")) == element:
			return k
	return ""


## Leaves on [param d] what [param spell] (just hit it for [param amount]) leaves by its element: frostbite for ice, a
## burn for fire. Its bite is a share of the hit; the caster's talents can make it last longer and bite harder (the
## spell's statusTime and statusBite, SpellEffects.tuned).
static func from_spell(d: Damageable, spell: Dictionary, amount: float, from_sera := true) -> void:
	var kind := kind_for(str(spell.get("element", "")))
	if kind == "":
		return
	var k: Dictionary = kinds()[kind]
	var secs := float(k.seconds) * float(spell.get("statusTime", 1.0))
	var bite := amount * float(k.perSecond) * float(spell.get("statusBite", 1.0))
	apply(d, kind, secs, bite, float(k.get("slow", 0.0)), StringName(kind), from_sera)


## Puts [param kind] on [param d] for [param seconds], biting [param dps] a second and slowing it [param slow]% (if it
## has the effect under [param key] already, that's topped up instead). Frozen ground uses its own key, so its harder
## frostbite comes on top of a spell's.
static func apply(d: Damageable, kind: String, seconds: float, dps: float, slow: float, key := &"", from_sera := true) -> void:
	if d == null or not is_instance_valid(d) or not d.alive() or d.team != Damageable.Team.ENEMY:
		return
	var s := d.get_node_or_null("Status") as StatusEffects
	if s == null:
		s = StatusEffects.new()
		s.name = "Status"
		s.target = d
		d.add_child(s)
	s.by_player = s.by_player or from_sera
	s._put(kind, seconds, dps, slow, key if key != &"" else StringName(kind))


## How fast [param d] moves now: 1 as it should, less while frostbitten.
static func speed_of(d: Damageable) -> float:
	var s := _on(d)
	if s == null:
		return 1.0
	var slow := 0.0
	var t := _now()
	for e in s.effects.values():
		if t < float(e.until):
			slow = maxf(slow, float(e.slow))
	return 1.0 - clampf(slow, 0.0, 90.0) / 100.0


## The tint over [param d]'s art: white without an effect, icy blue while frostbitten, a flickering orange burning.
static func tint_of(d: Damageable) -> Color:
	var s := _on(d)
	if s == null or s.effects.is_empty():
		return Color.WHITE
	var t := _now()
	var c := Color.WHITE
	for kind in s.kinds_on():
		var tc := _color(kinds().get(kind, {}).get("tint", [1, 1, 1, 1]))
		if bool(kinds().get(kind, {}).get("flicker", false)):
			tc = Color.WHITE.lerp(tc, 0.7 + 0.3 * sin(t * 23.0) * sin(t * 7.0))
		c *= tc
	return c


## Whether [param d] has [param kind] on it now.
static func has_effect(d: Damageable, kind: String) -> bool:
	var s := _on(d)
	return s != null and s.kinds_on().has(kind)


static func _on(d: Damageable) -> StatusEffects:
	if d == null or not is_instance_valid(d):
		return null
	return d.get_node_or_null("Status") as StatusEffects


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


static func _color(c: Array) -> Color:
	return Color(c[0], c[1], c[2], c[3] if c.size() > 3 else 1.0)


## The effects on it now, by kind.
func kinds_on() -> Array:
	var out := []
	var t := _now()
	for e in effects.values():
		if t < float(e.until) and not out.has(e.kind):
			out.append(e.kind)
	return out


func _put(kind: String, seconds: float, dps: float, slow: float, key: StringName) -> void:
	var t := _now()
	var e: Dictionary = effects.get(key, {})
	if e.is_empty() or t >= float(e.until):
		e = {"kind": kind, "until": t + seconds, "dps": dps, "slow": slow}
		if effects.is_empty():
			_next_tick = t + TICK
	else:
		e.until = maxf(float(e.until), t + seconds)
		e.dps = maxf(float(e.dps), dps)
		e.slow = maxf(float(e.slow), slow)
	effects[key] = e
	_show(kind)


func _process(delta: float) -> void:
	var __t := Time.get_ticks_usec()
	_process_timed(delta)
	Perf.add(&"status_effects.process", __t)


func _process_timed(delta: float) -> void:
	_age += delta
	if target == null or not is_instance_valid(target) or not target.alive():
		return
	var t := _now()
	if t >= _next_tick and not effects.is_empty():
		_next_tick = t + TICK
		# A bite from each kind on it, one number each.
		var bites := {}
		for e in effects.values():
			if t < float(e.until) + 0.05:
				bites[e.kind] = float(bites.get(e.kind, 0.0)) + float(e.dps) * TICK
		for kind in bites:
			if target.alive() and bites[kind] > 0.0:
				target.wear(bites[kind], by_player, _color(kinds().get(kind, {}).get("number", [1, 1, 1, 1])))
		if not is_instance_valid(target) or not target.alive():
			return
	# Worn off.
	for key in effects.keys():
		if t >= float(effects[key].until):
			effects.erase(key)
	var on := kinds_on()
	for kind in _motes:
		(_motes[kind] as CPUParticles2D).emitting = on.has(kind)
	queue_redraw()


func _draw() -> void:
	if not kinds_on().has("Frostbite"):
		return
	# A rim of frost on the ground round its feet, glinting.
	var r := target.radius * 1.3
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.5))
	draw_circle(Vector2.ZERO, r, Color(0.75, 0.9, 1.0, 0.35))
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, Color(0.85, 0.96, 1.0, 0.8), 2.5, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for i in 5:
		var a := i * TAU / 5.0 + 0.4
		var at := Vector2(cos(a) * r * 0.85, sin(a) * r * 0.42)
		var h := 9.0 + 4.0 * sin(_age * 3.0 + i * 1.7)
		draw_colored_polygon(PackedVector2Array([at + Vector2(-3.5, 0), at + Vector2(0, -h), at + Vector2(3.5, 0), at + Vector2(0, 2)]), Color(0.82, 0.95, 1.0, 0.85))


# Motes about it for [param kind]: frost glinting and drifting down, or flames licking up.
func _show(kind: String) -> void:
	if _motes.has(kind):
		(_motes[kind] as CPUParticles2D).emitting = true
		return
	var k: Dictionary = kinds().get(kind, {})
	var c := _color(k.get("tint", [1, 1, 1, 1]))
	var h := target.height if target != null else 96.0
	var m := CPUParticles2D.new()
	m.amount = 22
	m.lifetime = 0.8
	m.local_coords = false
	m.texture = Waterfall._dot(16, 1.0)
	m.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	m.emission_rect_extents = Vector2(maxf(14.0, target.radius * 0.8), h * 0.35)
	m.position = Vector2(0, -h * 0.45)
	m.spread = 25.0
	m.gravity = Vector2.ZERO
	var g := Gradient.new()
	if bool(k.get("flicker", false)):
		m.direction = Vector2(0, -1)
		m.initial_velocity_min = 40.0
		m.initial_velocity_max = 90.0
		m.scale_amount_min = 1.0
		m.scale_amount_max = 1.8
		g.set_color(0, Color(1.0, 0.9, 0.5, 0.95))
		g.set_color(1, Color(0.9, 0.2, 0.05, 0.0))
		g.add_point(0.4, Color(1.0, 0.5, 0.15, 0.85))
	else:
		m.direction = Vector2(0, 1)
		m.initial_velocity_min = 8.0
		m.initial_velocity_max = 25.0
		m.scale_amount_min = 0.5
		m.scale_amount_max = 1.0
		g.set_color(0, Color(1.0, 1.0, 1.0, 0.95))
		g.set_color(1, Color(c, 0.0))
	m.color_ramp = g
	World.keep_lit(m)
	add_child(m)
	m.emitting = true
	_motes[kind] = m
