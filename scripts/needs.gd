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
const EAT_ORDER := [["CarrotStew", 55.0], ["CabbageSoup", 50.0], ["Meal", "mealFills"], ["BakedPotato", "bakedPotatoFills"],
	["Bread", 40.0], ["Candy", "candyFills"], ["Food", "meatFills"], ["Cabbage", 15.0], ["Carrot", 12.0], ["Potato", "potatoFills"]]
const FOOD_BUFFS := {
	"CarrotStew": {"hpRegen": 1.5, "gatherSpeed": 15.0},
	"CabbageSoup": {"defense": 3.0, "manaRegen": 1.0},
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


## The effects on her now, for the HUD: [name, good].
func effects() -> Array:
	var list := []
	if hunger_state() != "": list.append([hunger_state(), false])
	if exhausted(): list.append(["Exhausted", false])
	if mist_sickness > 0.01: list.append(["Mist sick %d%%" % roundi(mist_sickness * 50.0), false])
	if comfort != "": list.append([comfort, comfort_good])
	for dish in _food_until:
		list.append([UiKit.resource_name(dish), true])
	return list


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and not event.ctrl_pressed:
		match event.keycode:
			KEY_Z: _keys["z"] = true
			KEY_F: _keys["f"] = true
			KEY_G: _keys["g"] = true


func _process(dt: float) -> void:
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
			var lost := minf(float(s.starvePang), stats.hp - 1.0)
			stats.set_hp(stats.hp - lost)
			FloatingText.spawn(world, "-%s" % str(snappedf(lost, 0.1)), miko.position + Vector2(0, -1.2 * world.px), Color(1, 0.45, 0.35))
	# Say so when she becomes hungry or starving.
	var st := hunger_state()
	if st != "" and st != _last_state:
		_say(st, Color(1, 0.6, 0.5))
	_last_state = st
	_penalties()
	_mist(dt)
	_sleep(dt)
	_comfort_and_prompt()
	# Dishes' buffs wear off.
	for dish in _food_until.keys():
		if t >= _food_until[dish]:
			_food_until.erase(dish)
			stats.set_buff("food:" + dish, null)


# What going without does: half the HP regen while hungry; none, and slower, while starving; slower, with half the
# mana regen, while exhausted.
func _penalties() -> void:
	if not hungry() and not exhausted():
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
	if stats.buffs.get(self) != b:
		stats.set_buff(self, b)


# Builds while she's in the mist, faster in strong mist, up to that mist's worst; wears off out of it.
func _mist(dt: float) -> void:
	var tier := world.mist.tier_at(miko.position) if world.mist != null else Mist.Tier.CLEAR
	var cap := 2.0 if tier == Mist.Tier.STRONG else (1.0 if tier == Mist.Tier.NORMAL else 0.0)
	var was := mist_sickness
	if mist_sickness < cap:
		mist_sickness = minf(cap, mist_sickness + dt / (float(s.strongMistBuild) / 2.0 if tier == Mist.Tier.STRONG else float(s.mistBuild)))
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
		if miko.bag.spend(kind, 1):
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
	if not miko.bag.spend("Tea", 1):
		_say("Nothing to drink", Color(1, 0.6, 0.5))
		return false
	energy = minf(MAX, energy + float(s.teaFills))
	_say("+%d energy" % roundi(float(s.teaFills)), Color(0.62, 0.86, 0.5))
	_sound("drinkSound")
	return true


func _sound(key: String) -> void:
	var path: Variant = data.get(key)
	if path is String and ResourceLoader.exists(path):
		Sfx.play(world, load(path), miko.position, 0.8)


func _frames() -> Array:
	var up: Array = s.sleepUp
	return up if _facing_up and up.size() >= 16 else s.sleepDown


## The nearest bed within [param range] px: {pos, e (its prop entry), type, settings, points}, or {}.
func nearest_bed(at: Vector2, range: float) -> Dictionary:
	var best := {}
	var best_d := range
	for type in data.get("beds", {}):
		for b in world.props.entries_named(type):
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


# Where she goes so her lying pose has its head on the pillow and its middle on the mattress's middle (Unity's
# Bed.SleepPoint and Place, from the points exported for the bed's art and her pose).
func _sleep_point(bed: Dictionary) -> Vector2:
	var e: Dictionary = bed.e
	var turn := int(e.turn)
	var id := world.props.sprite_for(e.prop, turn)
	var flipped := world.props.shown_flipped(e)
	var pts: Dictionary = bed.points.get(str(id), {})
	var lying: Variant = data.get("lying", {}).get("sleepUp" if _facing_up else "sleepDown")
	if pts.is_empty() or lying == null:
		return bed.pos
	var feet_right := turn == 1 or turn == 2
	var pillow_right := (not feet_right) != flipped
	var pair: Array = pts.right if pillow_right else pts.left
	var centre := Vector2(pair[0][0], pair[0][1])
	var pillow := Vector2(pair[1][0], pair[1][1])
	if flipped:
		centre.x = -centre.x
		pillow.x = -pillow.x
	var k := PropMap._scale(float(e.scale))
	centre = bed.pos + centre * k
	pillow = bed.pos + pillow * k
	var middle := Vector2(lying.middle[0], lying.middle[1]) * absf(miko.art_scale.x)
	var head := Vector2(lying.head[0], lying.head[1]) * absf(miko.art_scale.x)
	if miko.facing_right != bool(s.artFacesRight):
		middle.x = -middle.x
		head.x = -head.x
	return ((centre - middle) + (pillow - head)) / 2.0


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


func _say(text: String, c: Color) -> void:
	FloatingText.spawn(world, text, miko.position + Vector2(0, -1.6 * world.px), c)
