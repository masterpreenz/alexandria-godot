class_name Needs
extends Node
## Miko's hunger and energy, both 0 to 100 (from Unity's PlayerNeeds).
## - Hunger falls slowly all the time (half as fast asleep); eating (F) fills it, the most filling food first. At 20 or
##   below she's Hungry (HP regen halved, attack, defense and magic a little lower); at 0 she's Starving (no HP regen,
##   slower, weaker still, losing HP every few seconds, never below 1).
## - Energy falls as she goes about, faster running (slower with Stamina); tea (G) fills it, standing still a few
##   seconds rests it back slowly, sleep (Z) quickly. At 0 she's Exhausted: no running, slower, half the mana regen.
## - Z lies her down to sleep (a toggle): she stays down, breathing, a "z" now and then, the day passing faster, energy
##   and HP coming back. Beside a bed she lies on it, facing its foot, and rests better; waking from a bed leaves her
##   Well rested (more regen and speed a while, by the bed's comfort), a night on the ground Stiff.
## - The mist makes her sick the longer she's in it (worse in strong mist), weakening her; it wears off outside.
## - Some dishes give a buff for five minutes (FoodBuffs).

const MAX := 100.0
const EAT_ORDER := [["FishStew", 65.0], ["FishSoup", 60.0], ["CarrotStew", 55.0], ["CabbageSoup", 50.0], ["Meal", "mealFills"], ["BakedPotato", "bakedPotatoFills"],
	["GrilledFish", 50.0], ["Bread", 40.0], ["SmokedFish", 40.0], ["Candy", "candyFills"], ["Food", "meatFills"], ["Cabbage", 15.0], ["Carrot", 12.0], ["Potato", "potatoFills"]]
const FOOD_BUFFS := {
	"CarrotStew": {"hpRegen": 1.5, "gatherSpeed": 15.0},
	"CabbageSoup": {"defense": 3.0, "manaRegen": 1.0},
	"FishSoup": {"manaRegen": 1.5, "hpRegen": 1.0},
	"FishStew": {"attack": 3.0, "defense": 2.0},
}
const FOOD_LASTS := 300.0

enum Sleep { AWAKE, LYING_DOWN, ASLEEP, GETTING_UP }

var world: World
var miko: Miko
var stats: CharacterStats
var s: Dictionary                 ## needs.json's needs
var data: Dictionary              ## needs.json
var hunger := MAX
var energy := MAX
var mist_sickness := 0.0
var sleep := Sleep.AWAKE
var comfort := ""                 ## "Well rested", "Rested", "Stiff" or ""
var comfort_good := false
var _comfort_until := 0.0
var _sleep_clock := 0.0
var _still_for := 0.0
var _slept_for := 0.0
var _ran_for := 0.0
var _next_z := 0.0
var _next_stir := 0.0
var _stir_until := 0.0
var _stir_frame := 0
var _next_starve := 0.0
var _bubble_label: SpeechBubble  ## her own bubble over her head (thinking hungry, shouting starving)
var _bubble_at := 0.0            ## when it next shows
var _bubble_until := 0.0
var _last_state := ""
var _facing_up := false
var _bed: Dictionary = {}         ## the bed she's on: {pos, type, ...}; empty on the ground
var _lie_from := Vector2.ZERO
var _food_until := {}             ## dish -> when its buff ends
var _keys := {}
var prompt: Label


func setup(w: World, who: Miko, d: Dictionary, hud: Node) -> void:
	world = w
	miko = who
	stats = who.stats
	data = d
	s = d.needs
	prompt = Label.new()
	prompt.add_theme_font_size_override("font_size", 20)
	prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	prompt.add_theme_constant_override("outline_size", 6)
	if UiKit.body_font:
		prompt.add_theme_font_override("font", UiKit.body_font)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	prompt.offset_top = -180
	prompt.offset_bottom = -150
	prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	prompt.visible = false
	hud.add_child(prompt)
	WorldPrompts.register(prompt)


## Hunger and energy from the save (Unity's player section).
func set_levels(h: float, e: float) -> void:
	hunger = clampf(h, 0.0, MAX)
	energy = clampf(e, 0.0, MAX)


func starving() -> bool:
	return hunger <= 0.0


func hungry() -> bool:
	return hunger <= float(s.hungryBelow)


func exhausted() -> bool:
	return energy <= 0.0


func sleeping() -> bool:
	return sleep != Sleep.AWAKE


## The hunger debuff on now ("Starving", "Hungry"), or "".
func hunger_state() -> String:
	return "Starving" if starving() else ("Hungry" if hungry() else "")


## The effects on her now, for the HUD: [name (with any time left), good, what it does].
func effects() -> Array:
	var list := []
	var pct := func(share: float) -> int: return roundi(share * 100.0)
	if starving():
		list.append(["Starving", false, "No HP regen, %d%% slower, attack, defense and magic -%d%%. Lose %s HP every %ss. Eat something (F)."
			% [roundi(float(s.starveSlow)), pct.call(float(s.starvingWeaker)), str(s.starvePang), str(s.starveEvery)]])
	elif hungry():
		list.append(["Hungry", false, "HP regen -%d%%, attack, defense and magic -%d%%. Eat something (F)." % [pct.call(1.0 - float(s.hungryRegen)), pct.call(float(s.hungryWeaker))]])
	if exhausted():
		list.append(["Exhausted", false, "Can't run, 25% slower, mana regen -50%. Rest, sleep (Z) or drink tea (G)."])
	match cold():
		1: list.append(["Cold", false, "Winter: 10% slower, HP regen -25%. Stand by a burning fire or torch, or get under a roof."])
		2: list.append(["Freezing", false, "Out in the snow: 20% slower, HP regen -50%, mana regen -25%. Stand by a burning fire or torch, or get under a roof."])
	# Second Wind spent: how long till it's back.
	var wind_in := stats.wind_ready_at - Time.get_ticks_msec() / 1000.0
	if stats.stat("secondWind") > 0.0 and wind_in > 0.0:
		list.append(["Second Wind %d:%02d" % [floori(wind_in / 60.0), floori(fmod(wind_in, 60.0))], false, "Second Wind saved her from a felling blow. It can't again until this runs out."])
	var tier := world.mist.tier_at(miko.position) if world.mist != null else Mist.Tier.CLEAR
	if mist_sickness > 0.01:
		var k := minf(1.0, mist_sickness)
		var deep := clampf(mist_sickness - 1.0, 0.0, 1.0)
		var weaker := roundi(lerpf(float(s.mistWeaker), float(s.strongMistWeaker), deep) * k * 100.0)
		var regen := roundi(lerpf(float(s.mistRegen), float(s.strongMistRegen), deep) * k * 100.0)
		var slow := roundi(float(s.strongMistSlow) * deep)
		var what := "Attack, defense and magic -%d%%, HP and mana regen -%d%%" % [weaker, regen] + (", %d%% slower" % slow if slow > 0 else "") + ". "
		what += "Worse the longer she stays in the mist (faster in strong mist). Place a cleansing crystal to clear ground, or step out to recover." if tier != Mist.Tier.CLEAR else "Wearing off now she's out of the mist."
		list.append(["Mist sick %d%%" % roundi(mist_sickness * 50.0), false, what])
	if tier != Mist.Tier.CLEAR:
		var strong := tier == Mist.Tier.STRONG
		var mp := roundi(((Mist.STRONG_POWER if strong else Mist.NORMAL_POWER) - 1.0) * 100.0)
		list.append(["Strong mist" if strong else "Mist", false, "Monsters keep coming out of it, %d%% stronger, and it makes her mist sick. " % mp
			+ ("Plain crystals and the village can't clear it." if strong else "Grow the village or place a cleansing crystal to clear it.")])
	if comfort != "":
		list.append([_timed(comfort, _comfort_until), comfort_good, _describe(stats.buffs.get("comfort", {})) + (" From a night in a bed." if comfort_good else " From sleeping on the ground.")])
	for dish in _food_until:
		list.append([_timed(UiKit.resource_name(dish), _food_until[dish]), true, _describe(FOOD_BUFFS.get(dish, {})) + " From a good meal."])
	return list


func _timed(nm: String, until: float) -> String:
	var secs := maxi(0, ceili(until - _now()))
	@warning_ignore("integer_division")
	return "%s %d:%02d" % [nm, secs / 60, secs % 60]


# A stat block as a short line: "+0.5 HP regen, +1 mana regen, +5% speed".
static func _describe(b: Dictionary) -> String:
	var parts := []
	var names := {"hpRegen": "HP regen", "manaRegen": "mana regen", "moveSpeed": "% speed", "attack": "attack", "defense": "defense", "magic": "magic", "gatherSpeed": "% gathering speed"}
	for k in names:
		var v := float(b.get(k, 0.0))
		if absf(v) > 0.001:
			var n: String = names[k]
			parts.append(("+" if v >= 0.0 else "") + str(snappedf(v, 0.01)) + ("" if n.begins_with("%") else " ") + n)
	return ", ".join(parts) + "." if not parts.is_empty() else ""


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and not event.ctrl_pressed:
		match event.keycode:
			KEY_Z: _keys["z"] = true
			KEY_F: _keys["f"] = true
			KEY_G: _keys["g"] = true


func _process(delta: float) -> void:
	var __t := Time.get_ticks_usec()
	_process_timed(delta)
	Perf.add(&"needs.process", __t)


func _process_timed(dt: float) -> void:
	var keys := _keys
	_keys = {}
	var fainting: Fainting = miko.get_node_or_null("Fainting")
	var fainted := fainting != null and fainting.fainted
	if not fainted:
		if keys.has("z"):
			if sleep == Sleep.AWAKE: lie_down()
			elif sleep != Sleep.GETTING_UP: get_up()
		if sleep == Sleep.AWAKE and keys.has("f"): eat()
		if sleep == Sleep.AWAKE and keys.has("g"): drink()
	# Hunger: always going, half as fast asleep.
	hunger = maxf(0.0, hunger - MAX / float(s.hungerEmptyTime) * (0.5 if sleeping() else 1.0) * dt)
	_still_for = 0.0 if miko.moving or sleep != Sleep.AWAKE else _still_for + dt
	if sleep == Sleep.ASLEEP:
		var bonus := float(_bed.settings.restBonus) if not _bed.is_empty() else 1.0
		energy = minf(MAX, energy + float(s.sleepGain) * bonus * dt)
		_slept_for += dt
		# Sleep mends her too.
		var most := stats.stat("maxHp")
		if stats.hp < most:
			stats.heal(most * float(s.sleepHeal) * bonus * dt)
	elif sleep == Sleep.AWAKE and _still_for >= float(s.restDelay) and energy < MAX:
		energy = minf(MAX, energy + float(s.restGain) * dt)
	elif sleep == Sleep.AWAKE:
		var running := miko.moving and miko.running
		# Stamina: she tires more slowly (5% a level), and running builds it.
		var drain := MAX / float(s.energyEmptyTime) * (float(s.runDrain) if running else 1.0) / LifeSkills.factor(LifeSkills.Skill.STAMINA, 0.05)
		if running:
			_ran_for += dt
			if _ran_for >= 20.0:
				_ran_for = 0.0
				LifeSkills.practise(LifeSkills.Skill.STAMINA, miko)
		energy = maxf(0.0, energy - drain * dt)
	miko.can_run = not exhausted()
	# Starving: a pang of lost HP every few seconds (never below 1).
	var t := _now()
	if not starving():
		_next_starve = t + float(s.starveEvery)
	elif t >= _next_starve:
		_next_starve = t + float(s.starveEvery)
		if stats.hp > 1.0:
			var lost := minf(float(s.starvePang) * clampf(1.0 - stats.stat("hungerResist") / 100.0, 0.0, 1.0), stats.hp - 1.0)   # (Iron Stomach)
			stats.set_hp(stats.hp - lost)
			FloatingText.spawn(world, "-%s" % str(snappedf(lost, 0.1)), miko.position + Vector2(0, -1.2 * world.px), Color(1, 0.45, 0.35))
	# Say so when she becomes hungry or starving, and in a bubble over her head now and then while she is (more often
	# starving).
	var st := hunger_state()
	if st != "" and st != _last_state:
		_say(st, Color(1, 0.6, 0.5))
		_bubble_at = t
	_last_state = st
	_bubble(t, st)
	_penalties()
	_mist(dt)
	_sleep(dt)
	_comfort_and_prompt()
	# Dishes' buffs wear off.
	for dish in _food_until.keys():
		if t >= _food_until[dish]:
			_food_until.erase(dish)
			stats.set_buff("food:" + dish, null)


# Her bubble over her head while she's hungry (every 40 s) or starving (every 15 s, in coral), for 3 seconds.
func _bubble(t: float, st: String) -> void:
	if _bubble_label == null:
		_bubble_label = SpeechBubble.new()
		_bubble_label.visible = false
		miko.add_child(_bubble_label)
	if st == "" or sleeping():
		_bubble_label.visible = false
		return
	if t >= _bubble_at:
		_bubble_at = t + (15.0 if st == "Starving" else 40.0)
		_bubble_until = t + 3.0
		var key := "miko.starving" if st == "Starving" else "miko.hungry"
		_bubble_label.say(Loc.pick(key), Villager.bark_kind(key))
	_bubble_label.visible = t < _bubble_until
	if _bubble_label.visible:
		# Just over the top of her picture (as drawn now, so a jump or a pose carries it).
		var top := World.sprite_rect(miko.art).position.y - miko.global_position.y
		_bubble_label.place(Vector2(0, top + 0.02 * world.px))


# What going without does: half the HP regen while hungry; none, and slower, while starving; slower, with half the
# mana regen, while exhausted.
## How cold she is: 0 not (not winter, or by a burning fire, or under a roof), 1 cold, 2 freezing (out in the snow).
func cold() -> int:
	if world.clock == null or world.clock.season() != GameClock.Season.WINTER:
		return 0
	if (world.roofs != null and world.roofs.covers(miko.position)) or Cellars.inside(miko.position) or Mountains.in_cave(miko.position):
		return 0
	var fires: Fires = miko.get_node_or_null("Fires")
	if fires != null and fires.warm(miko.position, WARMTH * world.px):
		return 0
	return 2 if world.clock.weather() == GameClock.Weather.SNOW else 1


const WARMTH := 4.0              ## units from a burning fire or torch she's kept warm

func _penalties() -> void:
	var chill := cold()
	if not hungry() and not exhausted() and chill == 0:
		if stats.buffs.has(self): stats.set_buff(self, null)
		return
	var total := stats.unbuffed()
	var b := {}
	var hp_regen := maxf(0.0, float(total.get("hpRegen", 0.0)))
	if starving():
		b.hpRegen = -hp_regen
		b.moveSpeed = -float(s.starveSlow)
	elif hungry():
		b.hpRegen = -hp_regen * (1.0 - float(s.hungryRegen))
	if hungry():
		var weaker := float(s.starvingWeaker) if starving() else float(s.hungryWeaker)
		for k in ["attack", "defense", "magic"]:
			b[k] = -maxf(0.0, float(total.get(k, 0.0))) * weaker
	if exhausted():
		b.moveSpeed = float(b.get("moveSpeed", 0.0)) - 25.0
		b.manaRegen = -maxf(0.0, float(total.get("manaRegen", 0.0))) * 0.5
	# Cold: slower, mending less; freezing in the snow, worse, and her mana comes back slower too.
	if chill > 0:
		b.moveSpeed = float(b.get("moveSpeed", 0.0)) - (20.0 if chill == 2 else 10.0)
		b.hpRegen = float(b.get("hpRegen", 0.0)) - hp_regen * (0.5 if chill == 2 else 0.25)
		if chill == 2:
			b.manaRegen = float(b.get("manaRegen", 0.0)) - maxf(0.0, float(total.get("manaRegen", 0.0))) * 0.25
	if stats.buffs.get(self) != b:
		stats.set_buff(self, b)


# Builds while she's in the mist, faster in strong mist, up to that mist's worst; wears off out of it.
func _mist(dt: float) -> void:
	var tier := world.mist.tier_at(miko.position) if world.mist != null else Mist.Tier.CLEAR
	var cap := 2.0 if tier == Mist.Tier.STRONG else (1.0 if tier == Mist.Tier.NORMAL else 0.0)
	var was := mist_sickness
	if mist_sickness < cap:
		# (Clear Lungs, Iron Stomach: it builds more slowly)
		var slower := clampf(1.0 - stats.stat("mistResist") / 100.0, 0.1, 1.0)
		mist_sickness = minf(cap, mist_sickness + dt * slower / (float(s.strongMistBuild) / 2.0 if tier == Mist.Tier.STRONG else float(s.mistBuild)))
	elif mist_sickness > cap:
		mist_sickness = maxf(cap, mist_sickness - dt / float(s.mistRecover))
	if mist_sickness <= 0.001:
		if stats.buffs.has("mist"): stats.set_buff("mist", null)
		return
	if absf(mist_sickness - was) < 0.002 and stats.buffs.has("mist"):
		return  # barely changed: leave the buff be
	# From normal mist's worst (1) on to strong mist's (2), the effect grows from the one to the other.
	var k := minf(1.0, mist_sickness)
	var deep := clampf(mist_sickness - 1.0, 0.0, 1.0)
	var weaker := lerpf(float(s.mistWeaker), float(s.strongMistWeaker), deep) * k
	var regen := lerpf(float(s.mistRegen), float(s.strongMistRegen), deep) * k
	var total := stats.unbuffed()
	stats.set_buff("mist", {
		"attack": -maxf(0.0, float(total.get("attack", 0.0))) * weaker,
		"defense": -maxf(0.0, float(total.get("defense", 0.0))) * weaker,
		"magic": -maxf(0.0, float(total.get("magic", 0.0))) * weaker,
		"hpRegen": -maxf(0.0, float(total.get("hpRegen", 0.0))) * regen,
		"manaRegen": -maxf(0.0, float(total.get("manaRegen", 0.0))) * regen,
		"moveSpeed": -float(s.strongMistSlow) * deep,
	})


## Eats one food, the most filling first; false if she's full or there's nothing to eat.
func eat(food := "") -> bool:
	if sleeping():
		return false
	if hunger >= MAX - 1.0:
		_say("Not hungry", Color(0.85, 0.8, 0.7))
		return false
	for pair in EAT_ORDER:
		var kind: String = pair[0]
		if food != "" and food != kind:
			continue
		if world.village.take(miko.bag, miko, kind, 1):
			var fills: float = float(s[pair[1]]) if pair[1] is String else float(pair[1])
			hunger = minf(MAX, hunger + fills)
			_say("+%d hunger" % roundi(fills), Color(0.96, 0.68, 0.32))
			if FOOD_BUFFS.has(kind):
				_food_until[kind] = _now() + FOOD_LASTS
				stats.set_buff("food:" + kind, FOOD_BUFFS[kind])
			_sound("eatSound")
			return true
	_say("Nothing to eat", Color(1, 0.6, 0.5))
	return false


## Drinks one tea; false if she's full of energy or there's none.
func drink() -> bool:
	if sleeping():
		return false
	if energy >= MAX - 1.0:
		_say("Not thirsty", Color(0.85, 0.8, 0.7))
		return false
	if not world.village.take(miko.bag, miko, "Tea", 1):
		_say("Nothing to drink", Color(1, 0.6, 0.5))
		return false
	energy = minf(MAX, energy + float(s.teaFills))
	_say("+%d energy" % roundi(float(s.teaFills)), Color(0.62, 0.86, 0.5))
	_sound("drinkSound")
	return true


func _sound(key: String) -> void:
	var path: Variant = data.get(key)
	if path is String and ResourceLoader.exists(path):
		Sfx.play(world, Sfx.stream(path), miko.position, 0.8)


func _frames() -> Array:
	var up: Array = s.sleepUp
	return up if _facing_up and up.size() >= 16 else s.sleepDown


## The nearest bed within [param range] px: {pos, e (its prop entry), type, settings, points}, or {}.
func nearest_bed(at: Vector2, reach: float) -> Dictionary:
	var best := {}
	var best_d := reach
	for type in data.get("beds", {}):
		for b in world.props.entries_named(type):
			# (not one a villager's in: no prompt for it, and Z doesn't put her in it)
			var in_it: Variant = occupants.get(bed_key(b.pos))
			if in_it != null and in_it != miko and is_instance_valid(in_it):
				continue
			var d: float = b.pos.distance_to(at)
			if d <= best_d:
				best_d = d
				best = {"pos": b.pos, "e": b.e, "type": type, "settings": data.beds[type].settings, "points": data.beds[type].points}
	return best


func lie_down() -> void:
	if sleep != Sleep.AWAKE or miko.locked:
		return
	# On a bed: onto it, facing its foot (turn 0 south-west, 1 south-east, 2 north-east, 3 north-west).
	_bed = nearest_bed(miko.position, float(s.bedRange) * world.px)
	if not _bed.is_empty():
		_lie_from = miko.position
		var turn := int(_bed.e.turn)
		miko.facing_right = turn == 1 or turn == 2
		miko.facing_up = turn >= 2
		_facing_up = miko.facing_up
		miko.place(_sleep_point(_bed))
		occupants[bed_key(_bed.pos)] = miko
		# Lying on it, not bumping into it (a raised bed is solid), and drawn over it.
		for c in miko.get_children():
			if c is CollisionShape2D:
				c.set_deferred("disabled", true)
		miko.z_index = 1
	_facing_up = miko.facing_up
	sleep = Sleep.LYING_DOWN
	_sleep_clock = 0.0
	_slept_for = 0.0
	miko.locked = true


# Where she goes so her lying pose has its head on the pillow and its middle on the mattress's middle.
func _sleep_point(bed: Dictionary) -> Vector2:
	var lying: Variant = data.get("lying", {}).get("sleepUp" if _facing_up else "sleepDown")
	return fit_on_bed(world, bed, lying, miko.facing_right != bool(s.artFacesRight), absf(miko.art_scale.x))


## Where a sleeper goes on [param bed] (nearest_bed's dictionary) so their lying pose [param lying] ({middle, head},
## px from their pivot) has its head on the pillow and its middle on the mattress's middle (Unity's Bed.SleepPoint and
## Place, from the points exported for the bed's art and the pose's); [param mirrored]: the pose is shown flipped;
## [param k]: the art's scale.
static func fit_on_bed(w: World, bed: Dictionary, lying: Variant, mirrored: bool, k: float) -> Vector2:
	return lie_on_bed(w, bed, lying, mirrored, k, false)[0]


## As [method fit_on_bed], and with [param turn] the angle to turn the sleeper's art by so they lie along the bed (the
## line from their middle to their head along the mattress's, middle to pillow; never more than [constant MOST_TURN]):
## [where they go, the angle]. Turned, their head lies on the pillow exactly.
const MOST_TURN := 0.45

static func lie_on_bed(w: World, bed: Dictionary, lying: Variant, mirrored: bool, k: float, turn_art := true) -> Array:
	var at := _fit(w, bed, lying, mirrored, k)
	if not turn_art or at.size() < 5:
		return [at[0], 0.0]
	var centre: Vector2 = at[1]
	var pillow: Vector2 = at[2]
	var middle: Vector2 = at[3]
	var head: Vector2 = at[4]
	if (pillow - centre).length() < 1.0 or (head - middle).length() < 1.0:
		return [at[0], 0.0]
	var rot := clampf(wrapf((pillow - centre).angle() - (head - middle).angle(), -PI, PI), -MOST_TURN, MOST_TURN)
	# Their head on the pillow (a little down it, not hanging off the bed's end), the rest of them down the mattress.
	return [pillow - head.rotated(rot) + (centre - pillow).normalized() * 8.0 * k, rot]


# [where they go, the mattress's middle, the pillow, the pose's middle, its head] (the last four when they're known).
static func _fit(w: World, bed: Dictionary, lying: Variant, mirrored: bool, k: float) -> Array:
	var e: Dictionary = bed.e
	var turn := int(e.turn)
	var id := w.props.sprite_for(e.prop, turn)
	var flipped := w.props.shown_flipped(e)
	var pts: Dictionary = bed.points.get(str(id), {})
	if pts.is_empty() or lying == null:
		return [bed.pos]
	var feet_right := turn == 1 or turn == 2
	var pillow_right := (not feet_right) != flipped
	var pair: Array = pts.right if pillow_right else pts.left
	var centre := Vector2(pair[0][0], pair[0][1])
	var pillow := Vector2(pair[1][0], pair[1][1])
	if flipped:
		centre.x = -centre.x
		pillow.x = -pillow.x
	var bk := PropMap._scale(float(e.scale))
	centre = bed.pos + centre * bk
	pillow = bed.pos + pillow * bk
	var middle := Vector2(lying.middle[0], lying.middle[1]) * k
	var head := Vector2(lying.head[0], lying.head[1]) * k
	if mirrored:
		middle.x = -middle.x
		head.x = -head.x
	return [((centre - middle) + (pillow - head)) / 2.0, centre, pillow, middle, head]


## Every bed in the world: [{pos, e, type, settings, points}].
static func all_beds(w: World, beds: Dictionary) -> Array:
	var out := []
	for type in beds:
		for b in w.props.entries_named(type):
			out.append({"pos": b.pos, "e": b.e, "type": type, "settings": beds[type].settings, "points": beds[type].points})
	return out


## Who lies in each bed now (Miko or a villager), by where the bed stands.
static var occupants := {}


static func bed_key(pos: Vector2) -> Vector2i:
	return Vector2i(roundi(pos.x), roundi(pos.y))


func get_up() -> void:
	if sleep == Sleep.AWAKE or sleep == Sleep.GETTING_UP:
		return
	var lie := int(s.lieDownFrames)
	# Up from wherever the lying down got to.
	var shown := mini(lie - 1, int(_sleep_clock * float(s.lieDownFps))) if sleep == Sleep.LYING_DOWN else lie - 1
	sleep = Sleep.GETTING_UP
	_sleep_clock = (lie - 1 - shown) / float(s.getUpFps)
	if world.clock != null:
		world.clock.speed = 1.0


## Stops sleeping at once, no getting up and no comfort (fainting in her sleep).
func end_sleep_now() -> void:
	if sleep == Sleep.AWAKE:
		return
	sleep = Sleep.AWAKE
	if world.clock != null:
		world.clock.speed = 1.0
	_off_bed()
	miko.pose = -1


func _off_bed() -> void:
	if _bed.is_empty():
		return
	if occupants.get(bed_key(_bed.pos)) == miko:
		occupants.erase(bed_key(_bed.pos))
	for c in miko.get_children():
		if c is CollisionShape2D:
			c.set_deferred("disabled", false)
	miko.z_index = 0
	_bed = {}


func _hold(id: int) -> void:
	miko.pose = id
	miko.pose_mirror = miko.facing_right != bool(s.artFacesRight)


func _sleep(dt: float) -> void:
	if sleep == Sleep.AWAKE:
		return
	var frames := _frames()
	var lie := int(s.lieDownFrames)
	_sleep_clock += dt
	var t := _now()
	match sleep:
		Sleep.LYING_DOWN:
			var f := int(_sleep_clock * float(s.lieDownFps))
			if f >= lie:
				sleep = Sleep.ASLEEP
				_sleep_clock = 0.0
				_next_z = t + 1.0
				_next_stir = t + randf_range(s.stirEvery[0], s.stirEvery[1])
				_stir_until = 0.0
				if world.clock != null:
					world.clock.speed = float(s.sleepClockSpeed)
				f = lie - 1
			_hold(int(frames[f]))
		Sleep.ASLEEP:
			# Still, on the first sleeping frame; now and then a stir to another one.
			var loop := frames.size() - lie
			if t >= _next_stir:
				_next_stir = t + randf_range(s.stirEvery[0], s.stirEvery[1])
				if loop > 1 and randf() < float(s.stirChance):
					_stir_frame = randi_range(1, loop - 1)
					_stir_until = t + randf_range(s.stirFor[0], s.stirFor[1])
			_hold(int(frames[lie + (_stir_frame if t < _stir_until else 0)]))
			if t >= _next_z:
				_next_z = t + 1.8
				var side := 0.35 if miko.facing_right != bool(s.artFacesRight) else -0.35
				FloatingText.spawn(world, "z", miko.position + Vector2(side, -0.4) * world.px, Color(0.78, 0.84, 1.0))
		Sleep.GETTING_UP:
			var f := lie - 1 - int(_sleep_clock * float(s.getUpFps))
			if f < 0:
				sleep = Sleep.AWAKE
				miko.pose = -1
				_wake()
				if not _bed.is_empty():
					miko.place(_lie_from)  # off the bed, back where she stood to lie down
				_off_bed()
				miko.locked = false
				return
			_hold(int(frames[f]))


# Waking: a good night in a bed, or a stiff one on the ground (only once she's slept a while).
func _wake() -> void:
	if _slept_for < float(s.comfortAfter):
		return
	var block: Dictionary
	if not _bed.is_empty():
		var share := clampf(float(_bed.settings.comfort), 0.0, 1.0)
		block = {}
		for k in s.wellRested:
			if float(s.wellRested[k]) != 0.0:
				block[k] = float(s.wellRested[k]) * share
		comfort = "Well rested" if share >= 0.99 else "Rested"
		comfort_good = true
		_comfort_until = _now() + minf(float(s.comfortMost), _slept_for * float(s.comfortPerSecond)) * maxf(0.5, share)
	else:
		block = {}
		for k in s.stiff:
			if float(s.stiff[k]) != 0.0:
				block[k] = float(s.stiff[k])
		comfort = "Stiff"
		comfort_good = false
		_comfort_until = _now() + float(s.stiffFor)
	stats.set_buff("comfort", block)
	_say(comfort, Color(0.62, 0.86, 0.5) if comfort_good else Color(1, 0.6, 0.5))


func _comfort_and_prompt() -> void:
	if comfort != "" and _now() >= _comfort_until:
		comfort = ""
		stats.set_buff("comfort", null)
	# "Z  Sleep" by a bed she's beside.
	var near := {} if sleep != Sleep.AWAKE or miko.locked else nearest_bed(miko.position, float(s.bedRange) * world.px)
	prompt.visible = not near.is_empty()
	prompt.text = "Press Z to sleep" if not near.is_empty() else ""
	if not near.is_empty():
		WorldPrompts.at(prompt, near.pos + Vector2(0, -0.6 * world.px))


func _say(text: String, c: Color) -> void:
	FloatingText.spawn(world, text, miko.position + Vector2(0, -1.6 * world.px), c)
