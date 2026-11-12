class_name Spoilage
extends Node
## Food goes off (from Unity's Spoilage): as the game's hours pass, a share of every stack of food in storage and in
## Miko's bag spoils and is gone, so laying up far more than is eaten doesn't pay. Raw food spoils sooner than cooked;
## candied jelly keeps a long while; tea keeps. What spoiled is told in the village's messages (and over Miko, from her
## bag), a few game hours' worth at a time.

const PER_DAY := {
	"Food": 0.35, "Jelly": 0.2, "Potato": 0.12, "Meal": 0.15, "BakedPotato": 0.08, "Candy": 0.03, "Carrot": 0.1,
	"Cabbage": 0.12, "Wheat": 0.01, "Flour": 0.02, "Bread": 0.05, "Fish": 0.4, "GrilledFish": 0.12, "SmokedFish": 0.015, "FishSoup": 0.4, "FishStew": 0.2, "HeartyStew": 0.15,
}

var world: World
var miko: Miko
var _stash_carry := {}
var _bag_carry := {}
var _stash_lost := {}
var _bag_lost := {}
var _last_hours := -1.0
var _next_tell := 0.0
var _next_tick := 0.0


func setup(w: World, who: Miko) -> void:
	world = w
	miko = who


## A line for an item's description: how fast it spoils.
static func note(r: String) -> String:
	var day: float = PER_DAY.get(r, 0.0)
	if day <= 0.0:
		return ""
	var speed := "fast" if day >= 0.3 else ("in a few days" if day >= 0.1 else ("slowly" if day >= 0.05 else "very slowly"))
	return " Spoils %s (about %d%% a day)." % [speed, roundi(day * 100.0)]


func _process(delta: float) -> void:
	var __t := Time.get_ticks_usec()
	_process_timed(delta)
	Perf.add(&"spoilage.process", __t)


func _process_timed(_delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	if t < _next_tick or world.clock == null:
		return
	_next_tick = t + 1.0
	var now := world.clock.hours
	if _last_hours < 0.0 or now < _last_hours:
		_last_hours = now
		_next_tell = now + 6.0
		return
	var dh := minf(24.0, now - _last_hours)
	_last_hours = now
	if dh <= 0.0:
		return
	var v := world.village
	# Cool Cellar, Green Thumb: that much less of it goes off.
	var keeps := clampf(1.0 - (miko.stats.stat("foodKeeps") if miko.stats != null else 0.0) / 100.0, 0.2, 1.0)
	# What the cellars keep cold spoils a quarter as fast: so much less of storage's food goes off.
	var cold := Cellars.active.cold_share() if Cellars.active != null else 0.0
	var stored_keeps := 1.0 - cold * (1.0 - Cellars.COLD_RATE)
	for r in PER_DAY:
		# The share of a stack gone in dh hours, at its daily rate.
		var share := (1.0 - pow(1.0 - float(PER_DAY[r]), dh / 24.0)) * keeps
		if v.founded():
			# (what's kept for planting is kept dry and sound: it doesn't spoil)
			_stash_carry[r] = float(_stash_carry.get(r, 0.0)) + v.spare(r) * share * stored_keeps
			var gone := mini(floori(_stash_carry[r]), v.spare(r))
			if gone > 0 and v.take_from_stash(r, gone):
				_stash_carry[r] -= gone
				_stash_lost[r] = int(_stash_lost.get(r, 0)) + gone
			if v.stored(r) == 0:
				_stash_carry[r] = 0.0
		_bag_carry[r] = float(_bag_carry.get(r, 0.0)) + miko.bag.count(r) * share
		var lost := mini(floori(_bag_carry[r]), miko.bag.count(r))
		if lost > 0 and miko.bag.spend(r, lost):
			_bag_carry[r] -= lost
			_bag_lost[r] = int(_bag_lost.get(r, 0)) + lost
		if miko.bag.count(r) == 0:
			_bag_carry[r] = 0.0
	if now >= _next_tell:
		_next_tell = now + 6.0
		var store := _list(_stash_lost)
		if store != "":
			VillageLog.event("spoiled", "Spoiled in storage: " + store)
		var mine := _list(_bag_lost)
		if mine != "":
			FloatingText.spawn(world, "Spoiled: " + mine, miko.position + Vector2(0, -1.3 * world.px), Color(0.75, 0.7, 0.45))


func _list(lost: Dictionary) -> String:
	var parts := []
	for r in PER_DAY:
		var n := int(lost.get(r, 0))
		if n > 0:
			parts.append("%d %s" % [n, UiKit.resource_name(r).to_lower()])
		lost[r] = 0
	return ", ".join(parts)
