class_name HeadBars
extends Node2D
## Miko's HP and mana beside her, so a fight needn't be read off the corner of the screen: two thin upright bars at her
## lower left, standing from her feet and filling upwards, HP (red, her shield a pale line up its side) and mana
## (blue, shorter) beside it. Out of the way of the casting bar over her head. They show while either is short of full,
## and all through a fight (a monster after her or near, a hit taken lately, a raid on), and fade away a moment after.
## Bright whatever the hour. A villager has the same, HP alone (they've no mana), while they fight, run or are hurt.

const THICK := 5.0               ## how wide each bar is
const HP_TALL := 62.0            ## how tall the HP bar stands
const MANA_TALL := 44.0
const GAP := 3.0
const BESIDE := 0.36             ## units left of her middle the nearer bar stands
const LINGER := 1.2              ## seconds they stay after both are full
const FADE := 0.4

const FIGHT_NEAR := 8.0          ## units: a monster going for someone this near is a fight
const HIT_LASTS := 5.0           ## seconds a hit taken counts as being in a fight

var world: World
var miko: Miko
var villager: Villager           ## (or a villager's: HP alone)
var _hurt_at := -INF
var _full_since := -1.0
var _shown := 0.0


func setup(w: World, who: Node2D) -> void:
	world = w
	if who is Miko:
		miko = who
		miko.stats.hurt.connect(func(_a): _hurt_at = Time.get_ticks_msec() / 1000.0)
	else:
		villager = who
	z_as_relative = false
	z_index = 3997
	World.keep_lit(self)


func _body() -> Node2D:
	if miko != null:
		return miko
	return villager


## [hp, most hp, mana, most mana]: mana -1 for those who have none.
func values() -> Array:
	if miko != null:
		var st := miko.stats
		if st == null:
			return [1.0, 1.0, -1.0, 1.0]
		var tot := st.total()
		return [st.hp, maxf(1.0, float(tot.get("maxHp", 100.0))), st.mana, maxf(1.0, float(tot.get("maxMana", 50.0)))]
	var h: Damageable = villager.hit
	if h == null:
		return [1.0, 1.0, -1.0, 1.0]
	return [h.hp, maxf(1.0, h.max_hp), -1.0, 1.0]


## Whether they're in a fight now: a monster going for them (or about to) near, a hit taken lately, a raid on while
## they're in the village; a villager fighting or running.
func fighting() -> bool:
	var who := _body()
	var now := Time.get_ticks_msec() / 1000.0
	if villager != null:
		if villager.state == Villager.State.FIGHT or villager.state == Villager.State.FLEE:
			return true
		if Villager.now() - villager._hit_at < HIT_LASTS:
			return true
	elif now - _hurt_at < HIT_LASTS:
		return true
	if Raids.on() and world.village.contains(who.position, 6.0):
		return true
	var near := FIGHT_NEAR * world.px
	for c in Creature.all:
		if is_instance_valid(c) and c.hit != null and c.hit.alive() and c.hostile() and c.position.distance_to(who.position) < near:
			return true
	return false


func _process(delta: float) -> void:
	var who := _body()
	if who == null or not is_instance_valid(who):
		return
	var v := values()
	var short := float(v[0]) < float(v[1]) - 0.5 or (float(v[2]) >= 0.0 and float(v[2]) < float(v[3]) - 0.5)
	# (a villager's show only in a fight, or hurt: not every scratch while they go about their day)
	if villager != null:
		short = short and (float(v[0]) < float(v[1]) * 0.75)
	short = short or fighting()
	var now := Time.get_ticks_msec() / 1000.0
	if short:
		_full_since = -1.0
	elif _full_since < 0.0:
		_full_since = now
	var want := 1.0 if short or (_full_since >= 0.0 and now - _full_since < LINGER and _shown > 0.0) else 0.0
	_shown = move_toward(_shown, want, delta / FADE)
	visible = _shown > 0.0 and who.visible and float(v[0]) > 0.0 and not (villager != null and villager.in_bed)
	if not visible:
		return
	# At her feet (the bars stand up from there, to her left).
	position = Vector2.ZERO
	modulate.a = _shown
	queue_redraw()


func _draw() -> void:
	var v := values()
	var x := -BESIDE * world.px - THICK
	var has_mana := float(v[2]) >= 0.0
	# (with no mana, the HP bar stands where the mana's would, nearest them)
	var hp_x := x - THICK - GAP if has_mana else x
	_bar(Rect2(hp_x, -HP_TALL, THICK, HP_TALL), float(v[0]) / float(v[1]), Color(0.9, 0.24, 0.2))
	# Her shield, a pale line up the HP's outer side.
	if miko != null and miko.stats != null:
		var shield := 0.0
		for k in miko.stats.shields:
			shield += float(miko.stats.shields[k])
		if shield > 0.5:
			var sh := (HP_TALL - 4.0) * clampf(shield / float(v[1]), 0.0, 1.0)
			draw_rect(Rect2(hp_x - 3.0, -2.0 - sh, 1.5, sh), Color(0.75, 0.9, 1.0))
	if has_mana:
		_bar(Rect2(x, -MANA_TALL, THICK, MANA_TALL), float(v[2]) / float(v[3]), Color(0.36, 0.62, 0.96))


# A rounded upright bar: a dark pill, filled from the bottom by [param share].
func _bar(r: Rect2, share: float, fill: Color) -> void:
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.08, 0.05, 0.05, 0.85)
	back.set_corner_radius_all(ceili(r.size.x / 2.0) + 1)
	back.anti_aliasing = true
	draw_style_box(back, r.grow(1.0))
	var h := r.size.y * clampf(share, 0.0, 1.0)
	if h < 1.0:
		return
	h = maxf(h, r.size.x)
	var front := StyleBoxFlat.new()
	front.bg_color = fill
	front.set_corner_radius_all(ceili(r.size.x / 2.0))
	front.anti_aliasing = true
	draw_style_box(front, Rect2(r.position.x, r.end.y - h, r.size.x, h))
