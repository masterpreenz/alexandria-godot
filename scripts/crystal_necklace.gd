class_name CrystalNecklace
extends Node
## The crystal necklace (made at the tool workbench from mist crystals and fibre), while Miko wears it: a soft crystal
## light round her like a lantern, going where she goes, and a small clearing in the mist about her (the normal mist
## only; Mist.set_personal). It wears out as it's worn (combat.json's durability, in seconds worn), its light dimming
## towards the end; when it's used up it breaks and is gone.

const SLOT := "Trinket"   ## worn as a trinket (its own slot), not in place of a necklace
const WARN_AT := 0.15           ## of its life left: "the crystal is dimming"

var miko: Miko
var world: World
var _light: PointLight2D
var _shown := 0.0               ## the light's strength, easing on and off (0..1)
var _warned := ""               ## the necklace already warned about


func setup(w: World, who: Miko) -> void:
	world = w
	miko = who
	_light = PointLight2D.new()
	_light.texture = Fires._glow()
	_light.enabled = false
	# (Directly in the world, as the fires' lights: a light among the y-sorted things lights nothing.)
	world.add_child(_light)


func _process(delta: float) -> void:
	var __t := Time.get_ticks_usec()
	_process_timed(delta)
	Perf.add(&"crystal_necklace.process", __t)


func _process_timed(delta: float) -> void:
	if miko == null or miko.stats == null:
		return
	var item := miko.stats.worn_in(SLOT)
	var d: Dictionary = miko.stats.item_stats.get(item, {})
	var on := item != "" and d.has("light")
	var at := miko.drawn_position()
	_shown = move_toward(_shown, 1.0 if on else 0.0, delta * 2.5)
	if world.mist != null:
		world.mist.set_personal(at, float(d.get("clearRadius", 0.0)) * world.px if on else 0.0)
	if _shown <= 0.0:
		_light.enabled = false
		return
	if on:
		var l: Dictionary = d.light
		var c: Array = l.color
		_light.color = Color(c[0], c[1], c[2])
		_light.texture_scale = float(l.radius) * 2.0 * world.px / float(_light.texture.get_width())
		# A small light, like a candle carried: it flickers a little, shows in the dark and hardly at all by day (the
		# fires' undoing of the night's tint, the other way round), and dims as it wears thin, to half at the end.
		var dl := miko.stats.durability_left(item)
		var left := 1.0 if dl < 0.0 else dl   # (one that never wears out: full)
		var t := Time.get_ticks_msec() / 1000.0
		var flicker := 0.92 + 0.05 * sin(t * 9.1) + 0.03 * sin(t * 23.7 + 1.3)
		var day := 1.0
		var daylight := get_tree().current_scene.get_node_or_null("Daylight") as CanvasModulate
		if daylight != null:
			day = clampf(maxf(daylight.color.r, maxf(daylight.color.g, daylight.color.b)), 0.2, 1.0)
		var dark := clampf((1.0 - day) / 0.55, 0.12, 1.0)
		_light.energy = float(l.energy) * lerpf(0.5, 1.0, left) * flicker * dark * _shown
		_wear(item, delta, left)
	else:
		_light.energy *= _shown
	_light.enabled = true
	_light.position = at + Vector2(0, -0.55 * world.px)   # at her chest, where it hangs


func _wear(item: String, delta: float, left: float) -> void:
	if left > 0.0 and left <= WARN_AT and _warned != item:
		_warned = item
		_say("The necklace's crystal is dimming", Color(0.7, 0.85, 1.0))
	if miko.stats.wear_out(item, delta):
		miko.stats.break_worn(miko.bag, SLOT)
		_warned = ""
		_say("The crystal necklace broke", Color(1.0, 0.7, 0.6))
		Puffs.burst(world, miko.position + Vector2(0, -0.5 * world.px), 0.5, 8)


func _say(text: String, c: Color) -> void:
	FloatingText.spawn(world, text, miko.position + Vector2(0, -1.8 * world.px), c)
