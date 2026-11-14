class_name Fires
extends Node
## The fires (from Unity's Bonfire, FireLighter and Cooking): bonfires and torches. Each burning one has soft flames
## rising off it (a white-yellow heart, orange and red blobs shrinking away, sparks drifting up) and a warm, wavering
## light on the ground. A fire burns for a night: placed or lit in the evening it burns until the next 6:00, by day
## only an hour (kept going while someone cooks at it). One that's gone out can be lit again with E for a little wood
## and stone. Beside a lit bonfire, E cooks: raw meat into a meal, else a potato into a baked potato, else slime jelly
## into candied jelly, Miko tossing it in a pan; holding E keeps cooking; moving or E again stops. When each fire
## burns till is saved (world.fires).

const LIGHT_RANGE := 1.2
const RECIPES := [["Food", "Meal", "raw meat"], ["Potato", "BakedPotato", "potatoes"], ["Jelly", "Candy", "slime jelly"], ["Fish", "GrilledFish", "fish"]]

static var _soft: Texture2D
static var _glow_tex: Texture2D

var world: World
var miko: Miko
var d: Dictionary                 ## farm.json
var fires: Array = []             ## [{pos, type, s, node, key, parts: [CPUParticles2D], light}]
var lit_until := {}               ## Vector2i key -> game hour it burns till
static var start_out := {}        ## fires that stand cold when they're first seen (a template's: the ruined village's), by cell
var _saved: Array = []            ## the save's fires, matched to the fires as they're found
var _looked_at := -1
var _clock := 0.0
var _warned_day := -1             ## the day winter's coming was last told
var prompt: Label
var _pressed := false
# Cooking.
var cooking := false
var _cook_clock := 0.0
var _cook_fire: Dictionary = {}
var _sizzle: AudioStreamPlayer


func setup(w: World, who: Miko, data: Dictionary, hud: Node) -> void:
	world = w
	miko = who
	d = data
	prompt = Label.new()
	prompt.add_theme_font_size_override("font_size", 20)
	prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	prompt.add_theme_constant_override("outline_size", 6)
	if UiKit.body_font:
		prompt.add_theme_font_override("font", UiKit.body_font)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	prompt.offset_top = -150
	prompt.offset_bottom = -120
	prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	prompt.visible = false
	hud.add_child(prompt)
	WorldPrompts.register(prompt)
	_sizzle = AudioStreamPlayer.new()
	var c: Dictionary = d.get("cooking", {})
	var path: Variant = c.get("sizzle")
	if path is String and ResourceLoader.exists(path):
		_sizzle.stream = Sfx.stream(path)
		_sizzle.volume_db = linear_to_db(maxf(0.0001, float(c.get("volume", 0.6))))
	add_child(_sizzle)
	_sizzle.finished.connect(func(): if cooking: _sizzle.play())


## The saved burn times (Unity's world.fires: {fires: [{x, y, until}]}, in units).
func from_json(json: String) -> void:
	var data: Variant = JSON.parse_string(json)
	_saved = data.get("fires", []) if data is Dictionary else []
	_looked_at = -1


func _hours() -> float:
	return world.clock.hours if world.clock != null else Time.get_ticks_msec() / 1000.0 / 30.0


func _key(at: Vector2) -> Vector2i:
	return Vector2i(roundi(at.x / world.px * 8.0), roundi(-at.y / world.px * 8.0))


func lit(f: Dictionary) -> bool:
	return _hours() < float(lit_until.get(f.key, -1.0))


## Evening and night (17:30 to 6:00): when fires are lit to burn till morning.
func _evening() -> bool:
	var h := world.clock.hour() if world.clock != null else 12.0
	return h >= 17.5 or h < 6.0


const WINTER_BURN := 6.0          ## game hours a fire lit by day burns in winter (kept going for warmth)

## Whether it's winter (the fires are kept lit all day then, for warmth).
func winter() -> bool:
	return world.clock != null and world.clock.season() == GameClock.Season.WINTER


## Whether the villagers see to this fire: it's in the village, or out of it on ground a cleansing crystal keeps clear
## (a torch on the road out, a camp by a crystal).
func tended(f: Dictionary) -> bool:
	if Cellars.room_has(world.floors.cell_at(f.pos)):
		return false   # (down in the cellar: hers to light)
	if world.village.contains(f.pos, 2.0):
		return true
	for at in world.props_named("CleansingCrystal"):
		var off: Vector2 = f.pos - at
		if Vector2(off.x, off.y * 2.0).length() <= Crystals.WARD_RADIUS * world.px:
			return true
	return false


## How much wood the fires take a winter's day: each fireplace lit for the night, each bonfire and torch lit again as
## it burns down by day ([constant WINTER_BURN] hours) and once more at dusk.
func winter_wood_a_day() -> int:
	var wood := 0
	for f in fires:
		if not tended(f):
			continue
		var by_day := 0 if bool(f.s.get("hearth", false)) else ceili(11.5 / WINTER_BURN)
		wood += int(f.s.woodToLight) * (1 + by_day)
	return wood


# Winter two days off, and again the day before: the village is told to lay wood in (how much the fires will burn
# through it, what's in storage, and the houses with no fireplace).
func _winter_warning() -> void:
	var c := world.clock
	if c == null or not world.village.founded() or c.season() == GameClock.Season.WINTER:
		return
	if c.season() != GameClock.Season.AUTUMN or c.day() == _warned_day:
		return
	var days_left := c.days_per_season - c.day_of_season() + 1
	if days_left > 2:
		return
	_warned_day = c.day()
	var need := winter_wood_a_day() * c.days_per_season
	var have := world.village.stored("Wood")
	var bare := 0
	if world.roofs != null:
		for roof in world.roofs.roofs:
			var has := false
			for f in fires:
				if bool(f.s.get("hearth", false)) and roof.cells.has(world.floors.cell_at(f.pos)):
					has = true
			if not has:
				bare += 1
	var when := "tomorrow" if days_left <= 1 else "in %d days" % days_left
	var text := "Winter comes %s: the fires will burn about %d wood through it (%d in storage)" % [when, need, have]
	if have < need:
		text += ". Stock up"
	if bare > 0:
		text += ". %d %s no fireplace" % [bare, "house has" if bare == 1 else "houses have"]
	VillageLog.problem("winter-coming", text, VillageLog.Kind.DANGER if have < need or bare > 0 else VillageLog.Kind.WARNING)


## Whether a fire burns in the room made of [param cells] (RoofMap's room: a house).
func warm_room(cells: Dictionary) -> bool:
	for f in fires:
		if lit(f) and cells.has(world.floors.cell_at(f.pos)):
			return true
	return false


## Whether there's a burning fire within [param reach] px of [param at].
func warm(at: Vector2, reach: float) -> bool:
	for f in fires:
		if lit(f) and f.pos.distance_to(at) <= reach:
			return true
	return false


## Sets it burning: through the night when lit in the evening; by day an hour, for cooking (in winter, a good while:
## it burns down and wants lighting again).
func light(f: Dictionary) -> void:
	var now := _hours()
	var morning := floorf(now / 24.0) * 24.0 + 6.0
	if now >= morning:
		morning += 24.0
	lit_until[f.key] = morning if _evening() else now + (WINTER_BURN if winter() else 1.0)


## Someone is cooking at it: it doesn't go out under them.
func keep_burning(f: Dictionary) -> void:
	if float(lit_until.get(f.key, -1.0)) < _hours() + 0.5:
		lit_until[f.key] = _hours() + 0.5


func _look() -> void:
	# The fires still standing as they were keep their flames and light (dressing them all again at every change
	# anywhere made every fire flicker out and back); only new ones are dressed, and gone ones cleared away.
	var old := {}
	for f in fires:
		old[f.node] = f
	fires.clear()
	for type in d.get("fires", {}):
		for e in world.props.drawn_named(type):
			var kept: Variant = old.get(e.node)
			if kept != null and is_instance_valid(e.node) and str(kept.type) == type:
				old.erase(e.node)
				fires.append(kept)
				continue
			var f := {"pos": e.pos, "type": type, "s": d.fires[type], "node": e.node, "key": _key(e.pos), "parts": [], "light": null, "shown": true,
				"turn": int(e.e.get("turn", 0))}
			_dress(f)
			fires.append(f)
	for f in old.values():
		for p in f.parts:
			if is_instance_valid(p): p.queue_free()
		if is_instance_valid(f.light): f.light.queue_free()
	# The save's burn times go to the fires standing where they were (within half a unit).
	for sv in _saved:
		var at := Vector2(float(sv.x), -float(sv.y)) * world.px
		for f in fires:
			if f.pos.distance_to(at) < 0.5 * world.px:
				lit_until[f.key] = float(sv.until)
				break
	_saved = []
	# Placed (not loaded): lit, for the night to come.
	for f in fires:
		if not lit_until.has(f.key):
			if start_out.has(world.floors.cell_at(f.pos)):
				lit_until[f.key] = -1.0
			else:
				light(f)


# The flames, sparks and light on a fire's prop.
func _dress(f: Dictionary) -> void:
	var s: Dictionary = f.s
	var holder: Node2D = f.node
	var base: Vector2 = (holder.get_child(0) as Node2D).position if holder.get_child_count() > 0 else Vector2.ZERO
	var off := _offset(f)
	var at := base + Vector2(off[0], -float(off[1])) * world.px
	var k := float(s.fireSize)
	var px := world.px
	# A fireplace's fire burns in its firebox, a little to one side by the way it faces.
	var art := holder.get_child(0) as Sprite2D if holder.get_child_count() > 0 else null
	var front_path := ""
	if art != null and art.texture != null and bool(s.get("hearth", false)):
		front_path = art.texture.resource_path.get_basename() + "_front.png"
		at.x += (0.086 if front_path.contains("SE") else -0.06) * px * (-1.0 if art.scale.x < 0.0 else 1.0)
	f.parts.append(_flames(holder, at, 70.0, [0.45, 0.75], [0.85 * k, 1.25 * k], [0.17 * k, 0.27 * k], 0.1 * k, 90, 0.2,
		[[0.0, Color(1, 0.62, 0.2, 0)], [0.1, Color(1, 0.55, 0.16, 0.95)], [0.55, Color(0.92, 0.28, 0.08, 0.75)], [1.0, Color(0.45, 0.08, 0.04, 0)]], false))
	f.parts.append(_flames(holder, at, 40.0, [0.3, 0.5], [0.5 * k, 0.8 * k], [0.12 * k, 0.2 * k], 0.07 * k, 50, 0.25,
		[[0.0, Color(1, 1, 0.8, 0)], [0.12, Color(1, 0.95, 0.6, 1)], [0.6, Color(1, 0.78, 0.3, 0.6)], [1.0, Color(1, 0.5, 0.15, 0)]], true))
	f.parts.append(_flames(holder, at, 6.0, [0.9, 1.7], [0.5 * k, 1.0 * k], [0.03 * k, 0.055 * k], 0.1 * k, 30, 0.6,
		[[0.0, Color(1, 0.9, 0.5, 1)], [0.7, Color(1, 0.5, 0.2, 0.8)], [1.0, Color(1, 0.3, 0.1, 0)]], true))
	var l := PointLight2D.new()
	l.texture = _glow()
	l.color = Color(s.lightColor[0], s.lightColor[1], s.lightColor[2])
	l.texture_scale = float(s.lightRadius) * 2.0 * px / float(_glow().get_width())
	# (Directly in the world: a light among the y-sorted props lights nothing.)
	l.position = holder.position + base + Vector2(0, -0.3 * px)
	l.energy = float(s.lightIntensity)
	world.add_child(l)
	f.light = l
	# Its top half (the mantel, its shield and the stack: the art again, cut off under the mantel) over the flames:
	# the fire burns in front of the hearth below and behind what's above it.
	var old := holder.get_node_or_null("Front")
	if old != null:
		old.free()
	if front_path != "" and ResourceLoader.exists(front_path):
		var front := Sprite2D.new()
		front.name = "Front"
		front.texture = load(front_path)
		front.centered = art.centered
		front.offset = art.offset
		front.position = art.position
		front.scale = art.scale
		front.material = art.material
		holder.add_child(front)


func _flames(holder: Node2D, at: Vector2, rate: float, life: Array, speed: Array, size: Array, radius: float, most: int,
		size_end: float, keys: Array, additive: bool) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	var px := world.px
	p.amount = mini(most, maxi(4, int(rate * float(life[1]))))
	p.lifetime = float(life[1])
	p.lifetime_randomness = 1.0 - float(life[0]) / float(life[1])
	p.local_coords = false
	p.position = at
	p.texture = _soft_dot()
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius * px
	p.direction = Vector2(0, -1)
	p.spread = 4.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = float(speed[0]) * px
	p.initial_velocity_max = float(speed[1]) * px
	var tex := float(_soft_dot().get_width())
	p.scale_amount_min = float(size[0]) * px / tex
	p.scale_amount_max = float(size[1]) * px / tex
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, size_end))
	p.scale_amount_curve = curve
	p.angle_min = 0.0
	p.angle_max = 360.0
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(keys.map(func(x): return float(x[0])))
	g.colors = PackedColorArray(keys.map(func(x): return x[1]))
	p.color_ramp = g
	if additive:
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		p.material = m
	holder.add_child(p)
	return p


# A soft round dot, bright in the middle and fading to nothing at the rim.
static func _soft_dot() -> Texture2D:
	if _soft != null:
		return _soft
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var dd := Vector2(x + 0.5 - n / 2.0, y + 0.5 - n / 2.0).length() / (n / 2.0)
			var a := clampf(1.0 - dd, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a * a * (3.0 - 2.0 * a)))
	_soft = ImageTexture.create_from_image(img)
	return _soft


static func _glow() -> Texture2D:
	if _glow_tex != null:
		return _glow_tex
	var g := GradientTexture2D.new()
	g.width = 256
	g.height = 256
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5)
	g.fill_to = Vector2(1.0, 0.5)
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.15, 0.5, 1.0])
	grad.colors = PackedColorArray([Color(1, 1, 1, 1), Color(0.8, 0.8, 0.8, 1), Color(0.3, 0.3, 0.3, 1), Color(0, 0, 0, 1)])
	g.gradient = grad
	_glow_tex = g
	return g


func nearest(at: Vector2, reach: float, want_lit: bool, cook: bool) -> Dictionary:
	var best := {}
	var best_d := reach
	for f in fires:
		if lit(f) != want_lit or (cook and (bool(f.s.torch) or bool(f.s.get("hearth", false)))):
			continue
		var dd: float = f.pos.distance_to(at)
		if dd <= best_d:
			best_d = dd
			best = f
	return best


## Whether a fire to light or cook at is in reach (E is the fire's then, not the miner's).
func claims(at: Vector2) -> bool:
	return not nearest(at, LIGHT_RANGE * world.px, false, false).is_empty() \
		or not nearest(at, float(d.get("cooking", {}).get("range", 1.3)) * world.px, true, true).is_empty()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E:
		_pressed = true


func _process(delta: float) -> void:
	var __t := Time.get_ticks_usec()
	_process_timed(delta)
	Perf.add(&"fires.process", __t)


func _process_timed(delta: float) -> void:
	var pressed := _pressed or WorldPrompts.take(prompt)
	_pressed = false
	if world.props.version != _looked_at:
		_looked_at = world.props.version
		_look()
	_clock += delta
	_winter_warning()
	# Godot darkens a light along with the night's tint (Unity's 2D lights add on top of it): undo that, so a fire
	# lights the dark as much as it did there.
	var night := 1.0
	var daylight := get_tree().current_scene.get_node_or_null("Daylight") as CanvasModulate
	if daylight != null:
		night = clampf(maxf(daylight.color.r, maxf(daylight.color.g, daylight.color.b)), 0.2, 1.0)
	# Out: no flames, no light (the prop stays). Lit again: they come back.
	for f in fires:
		var on := lit(f)
		if on != f.shown:
			f.shown = on
			for p in f.parts:
				p.emitting = on
			f.light.visible = on
		if on:
			f.light.energy = float(f.s.lightIntensity) * (0.85 + 0.1 * sin(_clock * 7.3 + f.pos.x) + 0.06 * sin(_clock * 17.1)) * 1.4 / sqrt(night)
	if cooking:
		_cook(pressed, delta)
		return
	if miko.locked:
		_say("")
		return
	# Cooking at a lit bonfire.
	var c: Dictionary = d.get("cooking", {})
	var fire := nearest(miko.position, float(c.get("range", 1.3)) * world.px, true, true)
	if not fire.is_empty():
		WorldPrompts.at(prompt, flame_point(fire))
		var have := []
		for r in RECIPES:
			if world.village.have(miko.bag, miko, r[0]) > 0:
				have.append("%d %s" % [world.village.have(miko.bag, miko, r[0]), r[2]])
		_say("Press E to cook  ·  " + ", ".join(have) if not have.is_empty() else "Need raw meat, potatoes or slime jelly to cook")
		if pressed and not have.is_empty():
			_begin(fire)
		return
	# Lighting one that's gone out.
	var unlit := nearest(miko.position, LIGHT_RANGE * world.px, false, false)
	if unlit.is_empty():
		_say("")
		return
	WorldPrompts.at(prompt, flame_point(unlit))
	var wood := int(unlit.s.woodToLight)
	var stone := int(unlit.s.stoneToLight)
	var cost := "%d wood, %d stone" % [wood, stone] if stone > 0 else "%d wood" % wood
	var can := world.village.have(miko.bag, miko, "Wood") >= wood and world.village.have(miko.bag, miko, "Stone") >= stone
	_say("Press E to light  ·  " + cost if can else "Needs %s to light" % cost)
	if can and pressed:
		world.village.take(miko.bag, miko, "Wood", wood)
		if stone > 0:
			world.village.take(miko.bag, miko, "Stone", stone)
		light(unlit)
		FloatingText.spawn(world, "Lit", unlit.pos + Vector2(0, -0.8 * world.px), Color(1, 0.75, 0.4))


func _frames() -> Array:
	var c: Dictionary = d.cooking
	var up: Array = miko.anim("cookUp", c.cookUp)
	return up if miko.facing_up and up.size() >= 16 else miko.anim("cookDown", c.cookDown)


func _begin(fire: Dictionary) -> void:
	_cook_fire = fire
	var to: Vector2 = fire.pos - miko.position
	miko.facing_up = to.y < 0.0
	miko.facing_right = to.x > 0.0
	cooking = true
	_cook_clock = 0.0
	miko.locked = true
	# The sizzle runs while she cooks: looped, picking up where it left off last time (so no two sound the same).
	if _sizzle.stream != null:
		_sizzle.pitch_scale = randf_range(0.95, 1.05)
		Sfx.keep_going(_sizzle, true)


func _cook(pressed: bool, delta: float) -> void:
	var moving := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down").length() > 0.2 \
		or Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_D)
	if moving or pressed:
		_stop()
		return
	keep_burning(_cook_fire)
	_cook_clock += delta
	var frames := _frames()
	# Her cooking skill quickens it: 6% a level.
	var f := int(_cook_clock * float(d.cooking.fps) * LifeSkills.factor(LifeSkills.Skill.COOKING, 0.06) * CharacterStats.percent(miko.stats.stat("cookSpeed") if miko.stats != null else 0.0))
	var holding := Input.is_key_pressed(KEY_E)
	WorldPrompts.at(prompt, flame_point(_cook_fire))
	_say("Cooking…  (hold E to keep cooking)" if holding else "Cooking…")
	if f < frames.size():
		miko.pose = int(frames[f])
		miko.pose_mirror = miko.facing_right  # drawn facing left
		return
	# Done: the first thing there is to cook, cooked.
	for r in RECIPES:
		if world.village.take_spare(miko.bag, miko, r[0], 1):   # (not the seed kept for planting)
			# Good Cook: now and then it stretches to two.
			var dishes := 2 if miko.stats != null and randf() < miko.stats.stat("cookBonus") / 100.0 else 1
			world.village.give(miko.bag, miko, r[1], dishes, miko.position)
			LifeSkills.practise(LifeSkills.Skill.COOKING, miko)
			FloatingText.spawn(world, "+%d %s" % [dishes, UiKit.resource_name(r[1])], miko.position + Vector2(0, -1.6 * world.px), Color(0.96, 0.68, 0.32))
			break
	# Still holding E with more to cook: straight on to the next one.
	if holding and RECIPES.any(func(r): return world.village.have(miko.bag, miko, r[0]) > 0):
		_cook_clock = 0.0
		return
	_stop()


func _stop() -> void:
	cooking = false
	Sfx.keep_going(_sizzle, false)
	miko.pose = -1
	miko.locked = false
	_say("")


## Where a fire's flame is (a torch's high on its post, a bonfire's low): what its prompts point at.
func flame_point(f: Dictionary) -> Vector2:
	var off := _offset(f)
	return f.pos + Vector2(0, -(float(off[1]) + 0.35) * world.px)


# Where the flame sits on its prop (cells: across, up): by the way it's turned, for one whose flame moves with that (a
# street lamp's lantern hangs to one side).
static func _offset(f: Dictionary) -> Array:
	var by: Array = f.s.get("fireOffsetByTurn", [])
	if not by.is_empty():
		return by[int(f.get("turn", 0)) % by.size()]
	return f.s.get("fireOffset", [0, 0])


func _say(text: String) -> void:
	prompt.text = text
	prompt.visible = text != ""


## Every fire's burn time, for the save (Unity's world.fires).
func to_json() -> String:
	var list := []
	for f in fires:
		if lit_until.has(f.key):
			list.append({"x": f.pos.x / world.px, "y": -f.pos.y / world.px, "until": lit_until[f.key]})
	return JSON.stringify({"fires": list})
