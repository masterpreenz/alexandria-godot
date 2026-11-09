class_name Farming
extends Node
## Farm plots and crops (from Unity's FarmPlot, Crops and FarmInteractor). A plot is a tilled patch one tile across
## growing a crop: potatoes, carrots, cabbages, wheat or cotton. Bare until something's planted (E), it sprouts, grows
## over its crop's game hours and is then ripe, to be harvested with E (crops grown from seed give some seed back; her
## farming skill sometimes gives one more). R sets the plot's whole field (the plots joined to it) to one crop, in
## turn: the village's rotation, then each crop. Bare soil lies flat on the ground; sprouts and ripe plants stand up.
## The first potatoes come from old overgrown patches in the wild (ripe when first found). What each plot grows is
## saved (world.farms).

const RANGE := 0.7
const CROPS := {
	"Potato": {"seed": "Potato", "hours": 48.0, "yield": [3, 5], "seedBack": [0, 0], "plural": "potatoes"},
	"Carrot": {"seed": "Carrot", "hours": 36.0, "yield": [3, 5], "seedBack": [0, 0], "plural": "carrots"},
	"Cabbage": {"seed": "CabbageSeed", "hours": 60.0, "yield": [1, 2], "seedBack": [1, 2], "plural": "cabbages"},
	"Wheat": {"seed": "WheatSeed", "hours": 48.0, "yield": [3, 5], "seedBack": [1, 2], "plural": "wheat"},
	"Cotton": {"seed": "CottonSeed", "hours": 60.0, "yield": [2, 4], "seedBack": [1, 2], "plural": "cotton"},
}
const ORDER := ["Potato", "Carrot", "Cabbage", "Wheat", "Cotton"]

var world: World
var miko: Miko
var d: Dictionary                 ## farm.json
var plots: Array = []             ## [{pos, type, s, node, key, flat (Sprite2D on the ground)}]
var states := {}                  ## Vector2i key -> {sown, sownAt, crop ("" potatoes), setTo ("" the rotation)}
var rotation: Array = ["Potato"]
var _next := 0
var _saved: Array = []
var _looked_at := -1
var _resources: Array = []        ## Unity's Resource enum, in order (the save keeps crops as its index + 1)
var prompt: Label
var _keys := {}


func setup(w: World, who: Miko, data: Dictionary, hud: Node) -> void:
	world = w
	miko = who
	d = data
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
	return 2 if _hours() - float(st.sownAt) >= _grow(p) else 1


func hours_left(p: Dictionary) -> float:
	return maxf(0.0, _grow(p) - (_hours() - float(_state(p).sownAt))) if stage(p) == 1 else 0.0


func _look() -> void:
	for p in plots:
		if is_instance_valid(p.flat): p.flat.queue_free()
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
				"last": _crop_name(int(sv.get("last", 0)))}
	_saved = []
	# An old wild patch is ripe when first found.
	for p in plots:
		if bool(p.s.startsRipe) and not states.has(p.key):
			states[p.key] = {"sown": true, "sownAt": _hours() - float(p.s.growHours) * 2.0, "crop": "", "setTo": ""}


func _art(p: Dictionary, st: int) -> int:
	var c := crop(p)
	if c != "Potato" and st >= 1:
		var id := int(d.get("cropArt", {}).get("%s_%d" % [c, st], -1))
		if id >= 0:
			return id
	var stages: Array = p.s.stages
	return int(stages[st]) if st < stages.size() else -1


# Shows each plot's stage: bare soil flat on the ground, sprouts and ripe plants standing on the prop.
func _show(p: Dictionary) -> void:
	var st := stage(p)
	var id := _art(p, st)
	if st == p.shown and id == p.art:
		return
	p.shown = st
	p.art = id
	var holder: Node2D = p.node
	if not is_instance_valid(holder) or holder.get_child_count() == 0:
		return
	var sprite: Sprite2D = holder.get_child(0)
	var flat: Sprite2D = p.flat.get_child(0)
	var scale: float = p.scale
	if st == 0:
		sprite.visible = false
		flat.visible = id >= 0
		if id >= 0:
			world.show_frame(flat, id, Vector2.ONE * scale)
	else:
		flat.visible = false
		sprite.visible = id >= 0
		if id >= 0:
			world.show_frame(sprite, id, Vector2.ONE * scale)


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
		_set_field(p)
	var st := _state(p)
	var set_to: String = "field: " + CROPS[st.setTo].plural if st.setTo != "" else "field: village rotation"
	match stage(p):
		0:
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
	if st.setTo == "" and st.get("last", "") == "" and _sown_in_field(p) == "":
		var i := rotation.find(c)
		if i >= 0:
			_next = (i + 1) % rotation.size()
	st.sown = true
	st.sownAt = _hours()
	st.crop = c
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
	states[p.key] = {"sown": false, "sownAt": 0.0, "crop": "", "setTo": _state(p).setTo, "last": c}
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
	for r in ["Carrot", "CabbageSeed", "WheatSeed", "CottonSeed"]:
		world.village.put_in_stash(r, 4)
	VillageLog.event("seeds", "A passing farmer left seeds in storage: 4 carrots, and cabbage, wheat and cotton seeds")


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
	if st.setTo != "":
		return [has_seed.call(CROPS[st.setTo].seed), st.setTo]
	var growing := _sown_in_field(p)
	if growing != "":
		return [has_seed.call(CROPS[growing].seed), growing]
	var last: String = st.get("last", "")
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


# What the rest of [param p]'s field (those under the rotation too) is growing this season, or "".
func _sown_in_field(p: Dictionary) -> String:
	for q in field_of(p):
		var qs := _state(q)
		if q != p and qs.sown and qs.setTo == "":
			return crop(q)
	return ""


func _harvest(p: Dictionary) -> void:
	var c := crop(p)
	var info: Dictionary = CROPS[c]
	var y: Array = p.s.yield if c == "Potato" else info.yield
	var n := randi_range(int(y[0]), int(y[1]))
	var seeds := randi_range(int(info.seedBack[0]), int(info.seedBack[1])) if int(info.seedBack[1]) > 0 else 0
	states[p.key] = {"sown": false, "sownAt": 0.0, "crop": "", "setTo": _state(p).setTo, "last": c}
	_till(p)
	# Her farming skill: a 6% chance a level (past the first) of one more.
	if randf() < 0.06 * (LifeSkills.get_level(LifeSkills.Skill.FARMING) - 1):
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
	FloatingText.spawn(world, "Field (%d): %s only" % [field.size(), CROPS[nxt].plural] if nxt != "" else "Field (%d): village rotation" % field.size(),
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
			"last": _crop_index(st.get("last", ""))})
	return JSON.stringify({"plots": list})
