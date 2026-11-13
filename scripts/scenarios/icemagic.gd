extends Scenario
## Ice and water magic, and what lingers after a spell: a Fireball leaving a slime burning; an Ice Blast frostbiting
## another and freezing the ground under it (a mutated villager walking onto it slowed harder); Ice Barrier soaking
## blows on Sera and bursting into frostbite when it breaks; Water Heal mending her; and the barrier and the heal cast
## by a villager instead of Sera. Prints HP over time and takes a few pictures. Run with --window=icemagic.

var md: Dictionary
var spells: Dictionary


func run() -> void:
	for i in 30:
		await get_tree().process_frame
	md = JSON.parse_string(FileAccess.get_file_as_string("res://data/monsters.json"))
	spells = (JSON.parse_string(FileAccess.get_file_as_string("res://data/combat.json")) as Dictionary).spells
	var spot := _open_spot()
	miko.place(spot)
	miko.stats.hp = miko.stats.stat("maxHp")
	miko.stats.mana = miko.stats.stat("maxMana")
	for i in 20:
		await get_tree().process_frame
	print("Ice: Sera's magic ", miko.stats.stat("magic"), ", spell damage ", miko.stats.stat("spellDamage"))
	await _fire()
	await _ice()
	await _slowed()
	await _barrier()
	await _heal()
	await _others()
	print("Ice: done")


# Somewhere open and dry, out of the village.
func _open_spot() -> Vector2:
	var c0 := world.village.banner_cell()
	for r in range(8, 60, 2):
		for k in 24:
			var a := k * TAU / 24.0
			var c := c0 + Vector2i(roundi(cos(a) * r), roundi(sin(a) * r))
			var at := world.floors.cell_centre(c)
			if world.water_depth(at) <= 0.0 and Wilds.open(world, at, 4.0, 0.3) and Wilds.open(world, at + Vector2(5.0, 0.0) * world.px, 3.0, 0.3):
				print("Ice: open ground at ", c)
				return at
	return world.floors.cell_centre(c0 + Vector2i(12, 0))


func _cast(id: String, target: Vector2, caster: Node2D = null, stats: CharacterStats = null) -> void:
	var s: Dictionary = spells[id]
	var from := miko.position if caster == null else caster.global_position
	var origin := target
	var ground_origin := target
	if s.delivery == "Directional":
		ground_origin = from
		origin = from + Vector2(0, -58.24)
	elif s.delivery == "SkyFall":
		origin = target + Vector2(-320, -1024)
	SpellEffects.begin(world, s, stats if stats != null or caster != null else miko.stats, origin, ground_origin, target, caster)


func _hp(d: Damageable) -> String:
	return str(snappedf(d.hp, 0.1)) if is_instance_valid(d) else "gone"


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


# A Fireball: the slime keeps burning.
func _fire() -> void:
	var sl := Slime.spawn(world, md.slime, true, miko.position + Vector2(4.0, 0.0) * world.px)
	sl.hit.max_hp = 400.0
	sl.hit.hp = 400.0
	await _frames(5)
	print("Fire: slime HP ", _hp(sl.hit), " before the Fireball")
	_cast("Fireball", sl.position)
	var shot_done := false
	for i in 9:
		await get_tree().create_timer(0.5).timeout
		print("Fire: t=", (i + 1) * 0.5, "s HP ", _hp(sl.hit), " burning ", StatusEffects.has_effect(sl.hit, "Burn"), " tint ", StatusEffects.tint_of(sl.hit))
		if i == 2 and not shot_done:
			shot_done = true
			shot("burn")
	sl.queue_free()


# An Ice Blast: frostbite on the slime, the ground frozen under it.
func _ice() -> void:
	var sl := Slime.spawn(world, md.slime, true, miko.position + Vector2(4.0, 0.5) * world.px)
	sl.hit.max_hp = 400.0
	sl.hit.hp = 400.0
	await _frames(5)
	print("Ice: slime HP ", _hp(sl.hit), " before the Ice Blast")
	_cast("IceBlast", sl.position)
	for i in 12:
		await get_tree().create_timer(0.5).timeout
		var st := sl.hit.get_node_or_null("Status") as StatusEffects
		var keys := st.effects.keys() if st != null else []
		print("Ice: t=", (i + 1) * 0.5, "s HP ", _hp(sl.hit), " frostbitten ", StatusEffects.has_effect(sl.hit, "Frostbite"), " speed x", snappedf(StatusEffects.speed_of(sl.hit), 0.01), " ", keys, " frozen ground ", _grounds())
		if i == 1:
			shot("frostbite")
	sl.queue_free()


func _grounds() -> int:
	var n := 0
	for c in world.ground.get_children():
		if c is SpellEffects.FrozenGround:
			n += 1
	return n


# A mutated villager marching on the village: its pace before, frostbitten, and on frozen ground.
func _slowed() -> void:
	var mv := MutatedVillager.spawn(world, md.mutatedVillager, miko.position + Vector2(8.0, 0.0) * world.px)
	mv.hit.max_hp = 600.0
	mv.hit.hp = 600.0
	mv.raid_to = world.floors.cell_centre(world.village.banner_cell())   # (marching on the village: walking all the while)
	await _frames(40)
	var pace := func() -> float:
		var a := mv.position
		await get_tree().create_timer(0.5).timeout
		return mv.position.distance_to(a) / world.px / 0.5
	print("Slow: walking ", snappedf(await pace.call(), 0.01), " units/s, speed x", StatusEffects.speed_of(mv.hit))
	mv.position = miko.position + Vector2(8.0, 0.0) * world.px
	StatusEffects.from_spell(mv.hit, spells.IceSpikes, 12.0)
	print("Slow: frostbitten ", snappedf(await pace.call(), 0.01), " units/s, speed x", StatusEffects.speed_of(mv.hit))
	mv.position = miko.position + Vector2(8.0, 0.0) * world.px
	SpellEffects.FrozenGround.make(world, spells.IceBlast, mv.position + Vector2(-1.0, 0.0) * world.px, 160.0, 13.0, true)
	await _frames(20)
	print("Slow: on frozen ground ", snappedf(await pace.call(), 0.01), " units/s, speed x", StatusEffects.speed_of(mv.hit), " HP ", _hp(mv.hit))
	mv.queue_free()
	await _frames(5)


# Ice Barrier on Sera: blows soaked, then it breaks and bursts on the slimes round her.
func _barrier() -> void:
	var near: Array[Slime] = []
	for k in 3:
		var sl := Slime.spawn(world, md.slime, false, miko.position + Vector2.from_angle(k * TAU / 3.0) * Vector2(1.2, 0.6) * world.px)
		sl.hit.max_hp = 300.0
		sl.hit.hp = 300.0
		near.append(sl)
	miko.stats.hp = miko.stats.stat("maxHp")
	_cast("IceBarrier", miko.position)
	await _frames(10)
	print("Barrier: Sera's shield ", snappedf(miko.stats.shield(), 0.1), ", HP ", snappedf(miko.stats.hp, 0.1))
	shot("barrier")
	for blow in [15.0, 15.0, 40.0]:
		miko.stats.damage(blow)
		await _frames(3)
		print("Barrier: a blow of ", blow, ": shield ", snappedf(miko.stats.shield(), 0.1), ", HP ", snappedf(miko.stats.hp, 0.1))
	await _frames(4)
	shot("burst")
	for sl in near:
		print("Barrier: slime by her HP ", _hp(sl.hit), " frostbitten ", StatusEffects.has_effect(sl.hit, "Frostbite"))
	await get_tree().create_timer(1.5).timeout
	for sl in near:
		print("Barrier: 1.5s on, slime HP ", _hp(sl.hit))
		if is_instance_valid(sl):
			sl.queue_free()


# Water Heal: Sera mended over two seconds.
func _heal() -> void:
	miko.stats.hp = 30.0
	_cast("WaterHeal", miko.position)
	var hp := [snappedf(miko.stats.hp, 0.1)]
	for i in 6:
		await get_tree().create_timer(0.4).timeout
		hp.append(snappedf(miko.stats.hp, 0.1))
		if i == 1:
			shot("waterheal")
	print("Heal: Sera's HP over 2.4s ", hp)


# Cast by someone else: a villager's barrier (on what can be hit of them) and heal.
func _others() -> void:
	if Villager.all.is_empty():
		print("Others: no villagers")
		return
	var v: Villager = Villager.all[0]
	_cast("IceBarrier", v.global_position, v)
	await _frames(5)
	print("Others: ", v.name, "'s barrier shield ", snappedf(v.hit.shield_from(_barrier_of(v)), 0.1))
	var hp0 := v.hit.hp
	v.hit.hurt(30.0)
	await _frames(3)
	print("Others: hit for 30 (HP ", snappedf(hp0, 0.1), " -> ", snappedf(v.hit.hp, 0.1), "), barrier left ", _barrier_left(v))
	v.hit.hurt(30.0)
	await _frames(3)
	print("Others: hit for 30 again (HP ", snappedf(v.hit.hp, 0.1), "), barrier left ", _barrier_left(v))
	v.hit.hp = maxf(1.0, v.hit.max_hp * 0.5)
	var before := v.hit.hp
	_cast("WaterHeal", v.global_position, v)
	await get_tree().create_timer(2.5).timeout
	print("Others: ", v.name, " healed ", snappedf(before, 0.1), " -> ", snappedf(v.hit.hp, 0.1), " of ", v.hit.max_hp)


func _barrier_of(v: Node2D) -> Object:
	for k in v.hit.shields.keys():
		if k is SpellEffects.IceBarrier:
			return k
	return null


func _barrier_left(v: Node2D) -> String:
	var b := _barrier_of(v)
	return "none (broken)" if b == null else str(snappedf(v.hit.shield_from(b), 0.1))
