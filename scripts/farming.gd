class_name Farming
extends Node
## Farm plots and crops (from Unity's FarmPlot, Crops and FarmInteractor). A plot is a tilled patch one tile across
## growing a crop: potatoes, carrots, wheat or cotton. Bare until something's planted (E), it sprouts, grows
## over its crop's game hours and is then ripe, to be harvested with E (crops grown from seed give some seed back; her
## farming skill sometimes gives one more).
##
## Plots joined to one another make a farm group (a field), and a field grows one crop: what's set for it (R, in turn:
## the village's rotation, then each crop), its plots all the same. It's planted, grows and is harvested as one: a plot
## harvested stays bare until the rest of its field is in, and then the whole field is planted again (the next crop in
## the rotation, unless it's set to one).
##
## Winter: nothing can be planted, and frost kills whatever is still growing when it comes (ripe crops can still be
## harvested). The field goes on to the next crop in spring. Bare soil lies flat on the ground; sprouts and ripe plants stand up.
## The first potatoes come from old overgrown patches in the wild (ripe when first found). What each plot grows is
## saved (world.farms).
##
## Crops want looking after while they grow. Watered (sowing waters it, and rain), a plot stays wet for a day; dry, it
## grows at half speed. Now and then pests get into a growing crop and it stops growing until they're cleared. Miko does
## either with E; villagers on farm duty see to them too. Nothing is ever lost: a neglected crop only comes in later.

const RANGE := 0.7
const CROPS := {
	"Potato": {"seed": "Potato", "hours": 48.0, "yield": [3, 5], "seedBack": [0, 0], "plural": "potatoes"},
	"Carrot": {"seed": "Carrot", "hours": 36.0, "yield": [3, 5], "seedBack": [0, 0], "plural": "carrots"},
	"Wheat": {"seed": "WheatSeed", "hours": 48.0, "yield": [3, 5], "seedBack": [1, 2], "plural": "wheat"},
	"Cotton": {"seed": "CottonSeed", "hours": 60.0, "yield": [2, 4], "seedBack": [1, 2], "plural": "cotton"},
}
const ORDER := ["Potato", "Carrot", "Wheat", "Cotton"]   ## (no cabbages for now)
const WET_FOR := 24.0            ## game hours a watering lasts
const DRY_RATE := 0.5            ## how fast a dry crop grows
const PEST_PER_HOUR := 0.015     ## the chance a growing crop gets pests, each game hour (about one in three crops a 24 h)
const WATER_SOUND := "res://assets/Sounds/watering_sound.mp3"
const PEST_SHEET := "res://assets/Resources/Emotes/Emote_pests.png"

var world: World
var miko: Miko
var d: Dictionary                 ## farm.json
var plots: Array = []             ## [{pos, type, s, node, key, flat (Sprite2D on the ground)}]
var states := {}                  ## Vector2i key -> {sown, sownAt, crop ("" potatoes), setTo ("" the rotation)}
var rotation: Array = ["Potato"]
var _next := 0
var _saved: Array = []
var _looked_at := -1
var panel: FieldPanel           ## the field's control panel (R)
var _tended_at := -INF           # the game hour the crops were last grown to
var _resources: Array = []        ## Unity's Resource enum, in order (the save keeps crops as its index + 1)
var prompt: Label
var _keys := {}


func setup(w: World, who: Miko, data: Dictionary, hud: Node) -> void:
	world = w
	miko = who
	d = data
	panel = FieldPanel.new()
	panel.name = "FieldPanel"
	hud.add_child(panel)
	panel.setup(self)
	_resources = UiKit.data.resources.keys()
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


## The saved plots (Unity's world.farms: {plots: [{x, y, sown, sownAt, crop, setTo}]}, and last: the crop harvested
## there last, for the rotation).
func from_json(json: String) -> void:
	var data: Variant = JSON.parse_string(json)
	_saved = data.get("plots", []) if data is Dictionary else []
	_looked_at = -1


## The village's crop rotation (Unity's village.kitchen rotation).
func rotation_from_json(json: String) -> void:
	var data: Variant = JSON.parse_string(json)
	if data is Dictionary:
		var r: Array = data.get("rotation", []).filter(func(x): return CROPS.has(x))
		if not r.is_empty():
			rotation = r


func _crop_name(i: int) -> String:
	return _resources[i - 1] if i > 0 and i - 1 < _resources.size() else ""


func _crop_index(nm: String) -> int:
	return _resources.find(nm) + 1 if nm != "" else 0


func _hours() -> float:
	return world.clock.hours if world.clock != null else Time.get_ticks_msec() / 1000.0 / 30.0


## A farm plot picked up (build mode's Move): what's growing in it comes away with it ({} for none).
func lift_plot(at: Vector2) -> Dictionary:
	var k := _key(at)
	var st: Dictionary = states.get(k, {})
	states.erase(k)
	return st


## A farm plot set down at [param at]: what was growing in it goes on there.
func set_plot(at: Vector2, st: Dictionary) -> void:
	if not st.is_empty():
		states[_key(at)] = st
	_looked_at = -1


func _key(at: Vector2) -> Vector2i:
	return Vector2i(roundi(at.x / world.px * 8.0), roundi(-at.y / world.px * 8.0))


func _state(p: Dictionary) -> Dictionary:
	if not states.has(p.key):
		states[p.key] = {"sown": false, "sownAt": 0.0, "crop": "", "setTo": "", "last": ""}
	return states[p.key]


func crop(p: Dictionary) -> String:
	var c: String = _state(p).crop
	return c if c != "" else "Potato"


func _grow(p: Dictionary) -> float:
	return float(p.s.growHours) if crop(p) == "Potato" else float(CROPS[crop(p)].hours)


## 0 bare, 1 growing, 2 ripe.
func stage(p: Dictionary) -> int:
	var st := _state(p)
	if not st.sown:
		return 0
	return 2 if _grown(p) >= _grow(p) else 1


func hours_left(p: Dictionary) -> float:
	return maxf(0.0, _grow(p) - _grown(p)) if stage(p) == 1 else 0.0


# Hours of growing it's had (an old save's plot: since it was sown).
func _grown(p: Dictionary) -> float:
	var st := _state(p)
	return float(st.get("grown", _hours() - float(st.sownAt)))


## Whether a growing crop wants watering.
func dry(p: Dictionary) -> bool:
	return stage(p) == 1 and _hours() - float(_state(p).get("wateredAt", -INF)) >= WET_FOR


## Whether pests are in a growing crop.
func pests(p: Dictionary) -> bool:
	return stage(p) == 1 and bool(_state(p).get("pest", false))


## Waters a plot (wet for a day), with the sound of it.
func water(p: Dictionary, sound := true) -> void:
	for q in field_of(p):   # the whole field at once
		_state(q).wateredAt = _hours()
	if sound:
		splash(p)


## The sound of watering at a plot; how long it lasts.
func splash(p: Dictionary) -> float:
	var clip := Sfx.stream(WATER_SOUND)
	if clip == null:
		return 0.0
	Sfx.play(world, clip, p.pos, 0.6, 0.08)
	return clip.get_length()


## Clears the pests out of a plot's whole field.
func clear_pests(p: Dictionary) -> void:
	for q in field_of(p):
		_state(q).pest = false


# Growing crops grow by the game hours gone by: at full speed watered, half dry, not at all with pests in them; pests
# get in now and then; rain waters everything.
func _tend(dh: float) -> void:
	var raining := world.clock != null and world.clock.weather() in [GameClock.Weather.RAIN, GameClock.Weather.STORM]
	var frost := winter()
	var killed := 0
	for p in plots:
		var st := _state(p)
		if not st.sown:
			continue
		# Winter's frost: what's still growing dies (the field goes on to its next crop in spring).
		if frost and stage(p) == 1:
			states[p.key] = {"sown": false, "sownAt": 0.0, "crop": "", "setTo": st.setTo, "last": crop(p), "waiting": false}
			killed += 1
			continue
		if raining:
			st.wateredAt = _hours()
		if stage(p) != 1 or dh <= 0.0:
			continue
		if not st.has("grown"):
			st.grown = _grown(p)
		var rate := 0.0 if st.get("pest", false) else (DRY_RATE if dry(p) else 1.0)
		st.grown = float(st.grown) + dh * rate
	# Pests get into a field, not a plot: one roll a field, and then into all of its growing plots.
	if dh > 0.0 and not frost:
		var seen := {}
		for p in plots:
			if seen.has(p.key) or stage(p) != 1:
				continue
			var field := field_of(p)
			for q in field:
				seen[q.key] = true
			if field.any(func(q): return _state(q).get("pest", false)):
				continue
			if randf() < 1.0 - pow(1.0 - PEST_PER_HOUR, dh):
				for q in field:
					if stage(q) == 1:
						_state(q).pest = true
	if killed > 0:
		VillageLog.event("frost", "Winter's frost killed %d growing plot%s: plant again in spring" % [killed, "" if killed == 1 else "s"])


func _look() -> void:
	for p in plots:
		if is_instance_valid(p.flat): p.flat.queue_free()
		if is_instance_valid(p.get("mark")): p.mark.queue_free()
	plots.clear()
	for type in d.get("plots", {}):
		for e in world.props.drawn_named(type):
			var p := {"pos": e.pos, "type": type, "s": d.plots[type], "node": e.node, "key": _key(e.pos), "flat": null, "shown": -1, "art": -1,
				"scale": PropMap._scale(float(e.e.scale))}
			# Bare soil lies flat on the ground, under everything standing: drawn there instead of by the prop.
			var flat := Sprite2D.new()
			var holder := Node2D.new()
			holder.position = e.pos
			holder.add_child(flat)
			world.add_ground_layer(holder, float(p.s.flatOrder))
			p.flat = holder
			plots.append(p)
	# The save's plots go to the plots standing where they were (within a third of a unit).
	for sv in _saved:
		var at := Vector2(float(sv.x), -float(sv.y)) * world.px
		var best := {}
		var best_d := 0.35 * world.px
		for p in plots:
			var dd: float = p.pos.distance_to(at)
			if dd < best_d:
				best_d = dd
				best = p
		if not best.is_empty():
			states[best.key] = {"sown": bool(sv.sown), "sownAt": float(sv.sownAt), "crop": _crop_name(int(sv.crop)), "setTo": _crop_name(int(sv.setTo)),
				"last": _crop_name(int(sv.get("last", 0))), "grown": float(sv.get("grown", _hours() - float(sv.sownAt))),
				"wateredAt": float(sv.get("wateredAt", _hours())), "pest": bool(sv.get("pest", false)),
				"waiting": bool(sv.get("waiting", false))}
			# A crop no longer grown (cabbages, for now): the plot bare again, and any field setting for it the rotation.
			var stb: Dictionary = states[best.key]
			for k in ["crop", "setTo", "last"]:
				if stb[k] != "" and not CROPS.has(stb[k]):
					if k == "crop":
						stb.sown = false
					stb[k] = ""
	_saved = []
	# An old wild patch is ripe when first found.
	for p in plots:
		if bool(p.s.startsRipe) and not states.has(p.key):
			states[p.key] = {"sown": true, "sownAt": _hours() - float(p.s.growHours) * 2.0, "crop": "", "setTo": "",
				"grown": float(p.s.growHours) * 2.0, "wateredAt": _hours(), "pest": false}
	_even_fields()


func _art(p: Dictionary, st: int) -> int:
	var c := crop(p)
	if c != "Potato" and st >= 1:
		var id := int(d.get("cropArt", {}).get("%s_%d" % [c, st], -1))
		if id >= 0:
			return id
	var stages: Array = p.s.stages
	return int(stages[st]) if st < stages.size() else -1


# Shows each plot: its soil lying flat on the ground (wet: dark, watered; dry: pale), and the crop standing on it (the
# same plants at one size, growing then ripe). A crop with no art of its own over the soil yet shows its old picture
# (soil and all) instead.
func _show(p: Dictionary) -> void:
	var st := stage(p)
	var overlay := _overlay(p, st)
	var full := _art(p, st) if st >= 1 and overlay < 0 else -1
	var soils: Dictionary = d.get("soil", {})
	var soil := _art(p, 0)
	if not soils.is_empty():
		soil = int(soils.wet if st >= 1 and not dry(p) else soils.dry)
	_show_care(p, full >= 0)
	var key := [soil, overlay, full]
	if p.get("drawn") == key:
		return
	p.drawn = key
	var holder: Node2D = p.node
	if not is_instance_valid(holder) or holder.get_child_count() == 0:
		return
	var sprite: Sprite2D = holder.get_child(0)
	var flat: Sprite2D = p.flat.get_child(0)
	var scale: float = p.scale
	flat.visible = full < 0 and soil >= 0
	if flat.visible:
		world.show_frame(flat, soil, Vector2.ONE * scale)
	var top := overlay if overlay >= 0 else full
	sprite.visible = top >= 0
	if top >= 0:
		world.show_frame(sprite, top, Vector2.ONE * scale)


# The crop's own art over the soil at [param st] (1 growing, 2 ripe), or -1.
func _overlay(p: Dictionary, st: int) -> int:
	if st < 1:
		return -1
	return int(d.get("cropOverlay", {}).get("%s_%d" % [crop(p), st], -1))


static var _pest_tex: Texture2D

# A dry crop looks a little parched (its soil pale); one with pests in it has a small bubble over it (the pest emote) until cleared.
func _show_care(p: Dictionary, old_art: bool) -> void:
	var holder: Node2D = p.node
	if not is_instance_valid(holder) or holder.get_child_count() == 0:
		return
	# (A crop on its own soil shows dryness by the soil; an old whole picture, by a tint.)
	(holder.get_child(0) as Sprite2D).self_modulate = Color(1.0, 0.93, 0.78) if old_art and dry(p) else Color.WHITE
	var has_pests := pests(p)
	var mark: Sprite2D = p.get("mark")
	if mark == null:
		if not has_pests or not ResourceLoader.exists(PEST_SHEET):
			return
		if _pest_tex == null:
			_pest_tex = load(PEST_SHEET)
		mark = Sprite2D.new()
		mark.texture = _pest_tex
		mark.region_enabled = true
		mark.z_as_relative = false
		mark.z_index = 3998
		holder.add_child(mark)
		p.mark = mark
	mark.visible = has_pests
	if not has_pests:
		return
	@warning_ignore("integer_division")
	var fw := _pest_tex.get_width() / 8
	var t := Time.get_ticks_msec() / 1000.0
	mark.region_rect = Rect2(int(t / 0.16) % 8 * fw, 0, fw, _pest_tex.get_height())
	mark.scale = Vector2.ONE * 0.5 * world.px / float(fw)
	mark.modulate = world.daylight_undo()
	mark.position = p.pos - holder.global_position + Vector2(0, -0.75 * world.px + sin(t * 2.4) * 0.04 * world.px)


func nearest(at: Vector2, reach: float) -> Dictionary:
	var best := {}
	var best_d := reach
	for p in plots:
		var dd: float = p.pos.distance_to(at)
		if dd < best_d:
			best_d = dd
			best = p
	return best


## Whether a plot is in reach (E is the farm's then, not the miner's).
func claims(at: Vector2) -> bool:
	return not nearest(at, RANGE * world.px).is_empty()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_E: _keys["e"] = true
		elif event.keycode == KEY_R: _keys["r"] = true


func _process(delta: float) -> void:
	var __t := Time.get_ticks_usec()
	_process_timed(delta)
	Perf.add(&"farming.process", __t)


func _process_timed(_delta: float) -> void:
	var keys := _keys
	_keys = {}
	if world.props.version != _looked_at:
		_looked_at = world.props.version
		_look()
	var now := _hours()
	if _tended_at > -INF:
		_tend(clampf(now - _tended_at, 0.0, 240.0))
	_tended_at = now
	for p in plots:
		_show(p)
	var fires: Fires = miko.get_node_or_null("Fires")
	var p := {} if miko.locked or (fires != null and fires.cooking) else nearest(miko.position, RANGE * world.px)
	if p.is_empty():
		_say("")
		return
	WorldPrompts.at(prompt, p.pos + Vector2(0, -0.7 * world.px))   # the arrow to the plot, not to her
	_give_starter()
	if keys.has("r"):
		if panel.visible:
			panel.close()
		else:
			panel.open(p)
	if panel.visible:
		_say("")   # the panel says it all
		return
	var set_to := "field"   # (R opens the field's panel)
	match stage(p):
		0:
			if winter():
				_say("Winter  ·  nothing can be planted until spring  ·  R field")
				return
			if not plantable(p):
				_say("Harvested  ·  waiting for the rest of the field (%d still growing)  ·  R %s" % [still_growing(p), set_to])
				return
			var pick := _pick(p)
			var c: String = pick[1]
			var got_seed: String = CROPS[c].seed
			var have := world.village.have(miko.bag, miko, got_seed)
			_say("E plant %s  ·  %d %s  ·  R %s" % [CROPS[c].plural, have, UiKit.resource_name(got_seed).to_lower(), set_to] if pick[0]
				else "Bare plot  ·  needs %s to plant  ·  R %s" % [UiKit.resource_name(got_seed).to_lower(), set_to])
			if keys.has("e") and pick[0] and world.village.take(miko.bag, miko, got_seed, 1):
				sow(p, c)
				_till(p)
				FloatingText.spawn(world, "Planted " + CROPS[c].plural, p.pos + Vector2(0, -0.6 * world.px), Color(0.62, 0.86, 0.5))
				LifeSkills.practise(LifeSkills.Skill.FARMING, miko)
		1:
			var h := hours_left(p)
			var nm: String = CROPS[crop(p)].plural.capitalize()
			if pests(p):
				_say("Pests in the %s  ·  not growing  ·  E clear the field" % CROPS[crop(p)].plural)
				if keys.has("e"):
					clear_pests(p)
					_till(p)
					FloatingText.spawn(world, "Pests cleared", p.pos + Vector2(0, -0.6 * world.px), Color(0.62, 0.86, 0.5))
					LifeSkills.practise(LifeSkills.Skill.FARMING, miko)
			elif dry(p):
				_say("%s dry  ·  growing at half speed  ·  E water the field" % nm)
				if keys.has("e"):
					water(p)
					FloatingText.spawn(world, "Watered", p.pos + Vector2(0, -0.6 * world.px), Color(0.55, 0.78, 1.0))
					LifeSkills.practise(LifeSkills.Skill.FARMING, miko)
			else:
				_say(("%s growing  ·  %d h to go" % [nm, ceili(h)] if h >= 1.0 else "%s growing  ·  nearly ready" % nm) + "  ·  R " + set_to)
		_:
			_say("Press E to harvest the " + CROPS[crop(p)].plural)
			if keys.has("e"):
				_harvest(p)


# ---- For the villagers ----

## The crop for a bare plot, with seed for it in storage: [ok, crop].
func pick_from_storage(p: Dictionary) -> Array:
	var v := world.village
	return _field_crop(p, func(seed_name: String) -> bool: return v.stored(seed_name) > 0)


## Sows a bare plot with [param c] (the seed is the caller's to take).
func sow(p: Dictionary, c: String) -> bool:
	if stage(p) != 0:
		return false
	var st := _state(p)
	# The first plot of a new field under the village rotation: the next new field gets the next crop.
	if st.setTo == "" and _field_last(p) == "" and _sown_in_field(p) == "":
		var i := rotation.find(c)
		if i >= 0:
			_next = (i + 1) % rotation.size()
	st.sown = true
	st.sownAt = _hours()
	st.crop = c
	st.grown = 0.0
	st.wateredAt = _hours()   # sowing waters it
	st.pest = false
	return true


## Harvests a ripe plot: [crop, how many, seeds back] ([crop, 0, 0] if it wasn't ripe).
func harvest(p: Dictionary) -> Array:
	var c := crop(p)
	if stage(p) != 2:
		return [c, 0, 0]
	var info: Dictionary = CROPS[c]
	var y: Array = p.s.yield if c == "Potato" else info.yield
	var n := randi_range(int(y[0]), int(y[1]))
	var seeds := randi_range(int(info.seedBack[0]), int(info.seedBack[1])) if int(info.seedBack[1]) > 0 else 0
	states[p.key] = {"sown": false, "sownAt": 0.0, "crop": "", "setTo": _state(p).setTo, "last": c, "waiting": true}
	return [c, n, seeds]


## The sound of working the soil at a plot; how long it lasts.
func till(p: Dictionary) -> float:
	_till(p)
	var path: Variant = p.s.get("tillSound")
	return (Sfx.stream(path) as AudioStream).get_length() if path is String and ResourceLoader.exists(path) else 0.0


# The first seeds: some for each new crop in storage, once (a passing farmer's gift), so there's something to plant.
func _give_starter() -> void:
	if Kitchen.seeds_given or not world.village.founded():
		return
	Kitchen.seeds_given = true
	for r in ["Carrot", "WheatSeed", "CottonSeed"]:
		world.village.put_in_stash(r, 4)
	VillageLog.event("seeds", "A passing farmer left seeds in storage: 4 carrots, and wheat and cotton seeds")


# The crop for a bare plot: its field's, if set (when there's seed for it); else the next in the rotation there's
# seed for. [ok, crop].
func _pick(p: Dictionary) -> Array:
	return _field_crop(p, func(seed_name: String) -> bool: return world.village.have(miko.bag, miko, seed_name) > 0)


# The crop a bare plot gets, field by field (the plots joined to it grow one crop together): [seed to hand (by
# [param has_seed]), crop]. A field set to one crop (R) grows that. Under the village rotation: what the rest of the
# field is growing; else, harvested here before, the crop after that one in the rotation (so a field planted together
# moves on together); else, a new field, the rotation's next.
func _field_crop(p: Dictionary, has_seed: Callable) -> Array:
	var st := _state(p)
	# What the rest of the field is growing (one crop a field), else what it's set to, else the rotation.
	var growing := _sown_in_field(p)
	if growing != "":
		return [has_seed.call(CROPS[growing].seed), growing]
	if st.setTo != "":
		return [has_seed.call(CROPS[st.setTo].seed), st.setTo]
	var last := _field_last(p)
	if last != "" and rotation.has(last):
		var after: String = rotation[(rotation.find(last) + 1) % rotation.size()]
		return [has_seed.call(CROPS[after].seed), after]
	for i in rotation.size():
		var c: String = rotation[(_next + i) % rotation.size()]
		if has_seed.call(CROPS[c].seed):
			return [true, c]
	return [false, rotation[_next % rotation.size()]]


## The plots joined to [param p] (its field, [param p] among them): plots next to one another, and on from those.
func field_of(p: Dictionary) -> Array:
	var field: Array = [p]
	var i := 0
	while i < field.size():
		for q in plots:
			if not field.has(q) and q.pos.distance_to(field[i].pos) < 0.8 * world.px:
				field.append(q)
		i += 1
	return field


# What the rest of [param p]'s field is growing this season, or "".
func _sown_in_field(p: Dictionary) -> String:
	for q in field_of(p):
		if q != p and _state(q).sown:
			return crop(q)
	return ""


# The crop the field last grew (any of its plots), or "".
func _field_last(p: Dictionary) -> String:
	for q in field_of(p):
		var last: String = _state(q).get("last", "")
		if last != "":
			return last
	return ""


## Whether a bare plot may be planted: not while plots of its field are still waiting for the rest to be harvested.
## Once the whole field is in (nothing growing), the field starts over.
func plantable(p: Dictionary) -> bool:
	if stage(p) != 0 or winter():
		return false
	var field := field_of(p)
	var waiting := 0
	for q in field:
		if _state(q).sown:
			if waiting > 0:
				return false
		elif _state(q).get("waiting", false):
			waiting += 1
	if waiting == 0:
		return true
	for q in field:
		if _state(q).sown:
			return false
	# All of it harvested: the field starts over.
	for q in field:
		_state(q).waiting = false
	return true


## Whether it's winter (nothing planted; frost kills what's growing).
func winter() -> bool:
	return world.clock != null and world.clock.season() == GameClock.Season.WINTER


## Game hours until winter starts (0 in winter), and in winter, until spring.
func hours_to_winter() -> float:
	return _hours_to_season(GameClock.Season.WINTER)


func hours_to_spring() -> float:
	return _hours_to_season(GameClock.Season.SPRING)


func _hours_to_season(target: int) -> float:
	var c: GameClock = world.clock
	if c == null:
		return INF
	var dps := maxi(1, c.days_per_season)
	var seasons := posmod(target - c.season(), 4)
	if seasons == 0:
		return 0.0
	# To the end of this season, then whole seasons.
	var days_left := dps - c.day_of_season() + (seasons - 1) * dps
	return float(days_left) * 24.0 + (24.0 - c.hour())


## How many of [param p]'s field are still growing (what a waiting plot waits for).
func still_growing(p: Dictionary) -> int:
	return field_of(p).filter(func(q): return _state(q).sown).size()


# One setting and one crop a field: where joined plots disagree (a plot newly laid beside a field, two fields joined,
# an old save), the most of them win.
func _even_fields() -> void:
	var seen := {}
	for p in plots:
		if seen.has(p.key):
			continue
		var field := field_of(p)
		var votes := {}
		for q in field:
			seen[q.key] = true
			var v: String = _state(q).setTo
			votes[v] = int(votes.get(v, 0)) + 1
		var best := ""
		for v in votes:
			if int(votes[v]) > int(votes.get(best, -1)):
				best = v
		for q in field:
			_state(q).setTo = best
		# Plots already growing other crops than most of the field (from before fields kept to one): the field's crop,
		# carrying on where they were.
		var crops := {}
		for q in field:
			if _state(q).sown:
				crops[crop(q)] = int(crops.get(crop(q), 0)) + 1
		if crops.size() > 1:
			var main := ""
			for c in crops:
				if main == "" or int(crops[c]) > int(crops[main]):
					main = c
			for q in field:
				if _state(q).sown:
					_state(q).crop = main
					q.erase("drawn")


func _harvest(p: Dictionary) -> void:
	var c := crop(p)
	var info: Dictionary = CROPS[c]
	var y: Array = p.s.yield if c == "Potato" else info.yield
	var n := randi_range(int(y[0]), int(y[1]))
	var seeds := randi_range(int(info.seedBack[0]), int(info.seedBack[1])) if int(info.seedBack[1]) > 0 else 0
	states[p.key] = {"sown": false, "sownAt": 0.0, "crop": "", "setTo": _state(p).setTo, "last": c, "waiting": true}
	_till(p)
	# Her farming skill: a 6% chance a level (past the first) of one more.
	if randf() < 0.06 * (LifeSkills.get_level(LifeSkills.Skill.FARMING) - 1):
		n += 1
	# Careful Picking, Green Thumb: a chance of one more again.
	if miko.stats != null and randf() < miko.stats.stat("harvestBonus") / 100.0:
		n += 1
	LifeSkills.practise(LifeSkills.Skill.FARMING, miko)
	world.village.give(miko.bag, miko, c, n, p.pos)
	var text := "+%d %s" % [n, info.plural.capitalize()]
	if seeds > 0:
		world.village.give(miko.bag, miko, info.seed, seeds, p.pos)
		text += ", +%d seeds" % seeds
	FloatingText.spawn(world, text, miko.position + Vector2(0, -1.6 * world.px), Color(0.9, 0.74, 0.45))


# R: the whole field (the plots joined to this one) to the next crop in turn (the village rotation first).
func _set_field(p: Dictionary) -> void:
	var order: Array = [""] + ORDER
	var nxt: String = order[(order.find(_state(p).setTo) + 1) % order.size()]
	var field := field_of(p)
	for q in field:
		_state(q).setTo = nxt
	FloatingText.spawn(world, "Field of %d: %s" % [field.size(), CROPS[nxt].plural] if nxt != "" else "Field of %d: village rotation" % field.size(),
		p.pos + Vector2(0, -0.9 * world.px), Color(0.9, 0.85, 0.6))


func _till(p: Dictionary) -> void:
	var path: Variant = p.s.get("tillSound")
	if path is String and ResourceLoader.exists(path):
		Sfx.play(world, Sfx.stream(path), p.pos, float(p.s.tillVolume), 0.08)


func _say(text: String) -> void:
	prompt.text = text
	prompt.visible = text != ""


## Every plot's state, for the save (Unity's world.farms).
func to_json() -> String:
	var list := []
	for p in plots:
		var st := _state(p)
		list.append({"x": p.pos.x / world.px, "y": -p.pos.y / world.px, "sown": st.sown, "sownAt": st.sownAt, "crop": _crop_index(st.crop), "setTo": _crop_index(st.setTo),
			"last": _crop_index(st.get("last", "")), "grown": _grown(p), "wateredAt": float(st.get("wateredAt", _hours())),
			"pest": bool(st.get("pest", false)), "waiting": bool(st.get("waiting", false))})
	return JSON.stringify({"plots": list})
