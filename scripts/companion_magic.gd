class_name CompanionMagic
extends Node
## A companion's own spellcasting (Miyu once she has her water book): while she's with Sera and a monster's near (the
## ones she'd fight), she casts the spells she knows when they're ready and she has the mana for them: a heal when
## anyone with her is hurt (her Healing Blanket on the most hurt, and kept on whoever's taking the blows in a fight),
## armour when she or Sera is being hit and nobody near has any on, else her attack spells, the strongest first, at the monster (in their range), or where the
## monsters are thickest for those that cover an area (Ice Blast, Blizzard). Each is a short pause: she stands, turns
## to it, a circle in the spell's colour at her feet, and it goes. Otherwise she fights as ever. data/companions.json's
## "magic" holds the timings and what each spell is for.

const PROJECTILE_LIFT := 0.45     ## units above her feet a spell she throws leaves from

signal cast(spell: String, at: Vector2)

var body: Villager
var ready_at := {}                ## spell -> when it can be cast again
var casts: Array = []             ## [spell, at] of each cast so far (the scenarios read it)
var _next := 0.0
var _gap_until := 0.0
var _hit_at := -99.0
var _sera_hp := -1.0                ## Sera's HP at the last look (less now: she's been hit)
var _sera_hit_at := -99.0
var _pending := ""                ## the spell being cast, till the pause is over
var _pending_foe: Damageable      ## the monster it goes at (followed till it goes), or null: at her own feet
var _pending_fixed := false       ## it goes at a spot on the ground (where the monsters are thickest), not at a monster
var _pending_ally: Node2D         ## the one of her side it's for (her Healing Blanket), followed till it goes
var _pending_spot := Vector2.ZERO
var _circle: Sprite2D
var _circle_flat: Node2D
var _charge: CPUParticles2D


## Gives [param v] their own spellcasting (once).
static func give(v: Villager) -> CompanionMagic:
	var m: CompanionMagic = v.get_node_or_null("Magic")
	if m == null:
		m = CompanionMagic.new()
		m.name = "Magic"
		m.body = v
		v.add_child(m)
	return m


func _ready() -> void:
	if body == null:
		body = get_parent() as Villager
	if body != null and body.hit != null:
		body.hit.damaged.connect(func(_a): _hit_at = Villager.now())


func _exit_tree() -> void:
	if _circle_flat != null and is_instance_valid(_circle_flat):
		_circle_flat.queue_free()


func _physics_process(delta: float) -> void:
	var __t := Time.get_ticks_usec()
	_think(delta)
	Perf.add(&"companion_magic.think", __t)


func _think(_delta: float) -> void:
	var t := Villager.now()
	if _pending != "":
		_follow_circle()
		if t >= body.cast_until:
			_release(t)
		return
	if t < _next:
		return
	var cfg: Dictionary = Companions.data().get("magic", {})
	_next = t + float(cfg.get("think", 0.35))
	if t < _gap_until or body.world == null or not body._in_party() or body.talking or body.hit == null or not body.hit.alive():
		return
	if body.state == Villager.State.FLEE or body.state == Villager.State.ASLEEP:
		return
	var st := Companions.stats_for(body.person)
	if st == null:
		return
	var known := st.known_spells()
	if known.is_empty():
		return
	var sera: Miko = body.world.player as Miko
	if sera != null and sera.stats != null:
		if _sera_hp >= 0.0 and sera.stats.hp < _sera_hp - 0.01:
			_sera_hit_at = t
		_sera_hp = sera.stats.hp
	var foe := body.foe if body.foe != null and is_instance_valid(body.foe) and body.foe.alive() else body._party_threat()
	if foe == null:
		return
	var uses: Dictionary = cfg.get("spells", {})
	# The strongest first (each spell's priority).
	known.sort_custom(func(a, b): return float(uses.get(a, {}).get("priority", 0.0)) > float(uses.get(b, {}).get("priority", 0.0)))
	# What's called for, most pressing first: a heal, armour, then the attacks.
	var heal_below := float(cfg.get("healBelow", 0.6))
	var lowest := _lowest_share()
	var hit_lately := t - maxf(_hit_at, _sera_hit_at) < float(cfg.get("guardAfter", 2.5))
	for want in ["heal", "guard", "attack"]:
		for sp in known:
			var s := Companions.spell(sp)
			if s.is_empty() or _use_of(sp, s, uses) != want or t < float(ready_at.get(sp, 0.0)):
				continue
			if st.mana + 0.001 < float(s.get("manaCost", 0.0)):
				continue
			var at: Damageable = null
			var spot := Vector2.INF
			var ally: Node2D = null
			var use: Dictionary = uses.get(sp, {})
			match want:
				"heal":
					if str(s.get("effect", "")) == "HealingBlanket":
						# The most hurt in reach if they're low; else (keepUp) whoever's taking the blows, kept wrapped.
						var who := _blanket_for(t, float(s.get("range", 0.0)), heal_below, float(use.get("keepUp", 0.0)), float(cfg.get("guardAfter", 2.5)))
						if who == null:
							continue
						ally = who
					elif lowest >= heal_below:
						continue
				"guard":
					if not hit_lately:
						continue
					if str(s.get("effect", "")) == "FrostArmor":
						if _armoured(float(s.get("reach", 0.0))):
							continue
					elif body.hit.shields.size() > 0 or st.shield() > 0.0:
						continue
				"attack":
					if str(use.get("aim", "")) == "group":
						var best := _thickest(float(s.get("range", 0.0)), float(s.get("aoeRadius", 64.0)))
						if int(best[1]) < int(use.get("atLeast", 1)):
							continue
						spot = best[0]
					elif foe.global_position.distance_to(body.position) > float(s.get("range", 0.0)):
						continue
					else:
						at = foe
			if st.spend_mana(float(s.get("manaCost", 0.0))):
				_start(sp, s, at, t, cfg, spot, ally)
				return


# Who her Healing Blanket's for: the most hurt of her side within [param reach] if they're under [param below] of
# their HP; else, with [param keep], whoever's been struck lately (Sera, or she) while under that share and not wrapped
# already; else null.
func _blanket_for(t: float, reach: float, below: float, keep: float, lately: float) -> Node2D:
	var worst: Node2D = null
	var low := below
	for pair in SpellEffects.party_near(body.world, body.position, reach):
		var f := SpellEffects.WaterBlanket.share_of_hp(pair[0], pair[1])
		if f < low:
			low = f
			worst = pair[0]
	if worst != null or keep <= 0.0:
		return worst
	var sera := body.world.player as Node2D
	for pick in [[sera, _sera_hit_at], [body, _hit_at]]:
		var who: Node2D = pick[0]
		if who == null or t - float(pick[1]) >= lately or SpellEffects.WaterBlanket.on(who):
			continue
		var st: CharacterStats = (who as Miko).stats if who is Miko else Companions.stats_for((who as Villager).person)
		if st != null and SpellEffects.WaterBlanket.share_of_hp(who, st) < keep:
			return who
	return null


# The lowest share of HP of anyone with her (Sera, the other companions, herself).
func _lowest_share() -> float:
	var low := 1.0
	for pair in SpellEffects.party_near(body.world, body.position, INF):
		var b: Node2D = pair[0]
		var st: CharacterStats = pair[1]
		var hit: Damageable = b.get("hit") as Damageable if "hit" in b else null
		if hit != null and is_instance_valid(hit):
			low = minf(low, hit.hp / maxf(1.0, hit.max_hp))
		else:
			low = minf(low, st.hp / maxf(1.0, st.stat("maxHp")))
	return low


# Whether anyone her armour would reach has armour on already.
func _armoured(reach: float) -> bool:
	for pair in SpellEffects.party_near(body.world, body.position, reach):
		if SpellEffects.FrostArmor.on(pair[0]):
			return true
	return SpellEffects.FrostArmor.on(body)


# Where the monsters are thickest within [param reach] of her, for a spell of area [param area]: [spot, how many].
func _thickest(reach: float, area: float) -> Array:
	var foes := []
	for d in Damageable.all:
		if is_instance_valid(d) and d.alive() and d.team == Damageable.Team.ENEMY and d.get_parent() is Creature \
				and not d.get_parent() is Rabbit and d.global_position.distance_to(body.position) <= reach:
			foes.append(d.global_position)
	var best := [Vector2.INF, 0]
	for a in foes:
		var n := 0
		var mid := Vector2.ZERO
		for b in foes:
			if SpellEffects._ground_gap(a, b) <= area * 0.9:
				n += 1
				mid += b
		if n > int(best[1]):
			best = [mid / float(n), n]
	return best


# What a spell's for: as companions.json says, else to attack if it does damage.
func _use_of(sp: String, s: Dictionary, uses: Dictionary) -> String:
	if uses.has(sp):
		return str(uses[sp].get("use", ""))
	if str(s.get("effect", "")) == "Shikigami":
		return ""
	return "attack" if float(s.get("damage", 0.0)) > 0.0 and str(s.get("delivery", "")) in ["Directional", "SkyFall", "Ground"] else ""


# She stops, turns to it, and the circle comes up at her feet.
func _start(sp: String, s: Dictionary, at: Damageable, t: float, cfg: Dictionary, spot := Vector2.INF, ally: Node2D = null) -> void:
	var st := Companions.stats_for(body.person)
	var quick := 1.0 + maxf(0.0, st.stat("castSpeed")) / 100.0
	var pause := clampf(float(s.get("castTime", 1.0)) * float(cfg.get("pauseShare", 0.4)) / quick, float(cfg.get("pauseMin", 0.5)), float(cfg.get("pauseMax", 1.1)))
	_pending = sp
	_pending_foe = at
	_pending_fixed = spot != Vector2.INF
	_pending_ally = ally
	_pending_spot = spot if _pending_fixed else (at.global_position if at != null else (ally.global_position if ally != null else body.position))
	body.cast_until = t + pause
	body.cast_toward = _pending_spot
	var c := SpellEffects.color(s) if s.has("color") else Color(0.65, 0.88, 1.0)
	_show_circle(str(s.get("element", "")), c)
	FloatingText.spawn(body.world, Companions.spell_name(sp), body.position + Vector2(0, -1.5 * body.world.px), c.lightened(0.3), 18, 1.0)


# The pause over: the spell goes (at the monster where it is now), and its cooldown starts.
func _release(t: float) -> void:
	var sp := _pending
	_pending = ""
	_hide_circle()
	var s := Companions.spell(sp)
	var st := Companions.stats_for(body.person)
	if s.is_empty() or st == null:
		return
	var target := _pending_spot
	if _pending_ally != null and is_instance_valid(_pending_ally):
		target = _pending_ally.global_position
	elif _pending_foe != null and is_instance_valid(_pending_foe) and _pending_foe.alive():
		target = _pending_foe.global_position
	elif _pending_foe == null and not _pending_fixed and _pending_ally == null:
		target = body.position
	_pending_ally = null
	_pending_foe = null
	var w := body.world
	var origin := target
	var ground_origin := target
	match str(s.get("delivery", "")):
		"Directional":
			ground_origin = body.position
			origin = body.position + Vector2(0, -PROJECTILE_LIFT * w.px)
		"SkyFall":
			var sky: Array = Companions.combat().get("caster", {}).get("skyOffset", [-320, -1024])
			origin = target + Vector2(float(sky[0]), float(sky[1]))
	SpellEffects.begin(w, s, st, origin, ground_origin, target, body)
	ready_at[sp] = t + SpellEffects.cooldown(s, st)
	_gap_until = t + float(Companions.data().get("magic", {}).get("gap", 1.2))
	casts.append([sp, target])
	cast.emit(sp, target)


# A circle in the spell's element at her feet while she casts, and motes rising (as Sera's).
func _show_circle(element: String, c: Color) -> void:
	var w := body.world
	var cd: Dictionary = Companions.combat().get("caster", {})
	if _circle_flat == null:
		_circle_flat = Node2D.new()
		_circle_flat.scale = Vector2(1.0, 0.5)
		_circle_flat.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		_circle = Sprite2D.new()
		_circle_flat.add_child(_circle)
		w.add_ground_layer(_circle_flat, -9979)
		_charge = CPUParticles2D.new()
		_charge.amount = 20
		_charge.lifetime = 0.8
		_charge.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		_charge.emission_rect_extents = Vector2(24, 5)
		_charge.direction = Vector2(0, -1)
		_charge.spread = 15.0
		_charge.gravity = Vector2.ZERO
		_charge.initial_velocity_min = 40.0
		_charge.initial_velocity_max = 80.0
		_charge.texture = Waterfall._dot(16, 1.0)
		_charge.scale_amount_min = 0.4
		_charge.scale_amount_max = 0.7
		body.add_child(_charge)
	var e := SpellCaster.ELEMENTS.find(element)
	var circles: Array = cd.get("circles", [])
	_circle.visible = e >= 0 and e < circles.size() and int(circles[e]) >= 0
	if _circle.visible:
		w.show_frame(_circle, int(circles[e]), Vector2.ONE * float(cd.get("circleScale", 0.7)) * 0.8)
		_circle.centered = true
		_circle.offset = Vector2.ZERO
	_charge.color = c
	_charge.emitting = true
	_follow_circle()


func _follow_circle() -> void:
	if _circle_flat != null:
		_circle_flat.position = body.position + Vector2(0, float(Companions.combat().get("caster", {}).get("circleY", -1.792)))
		_circle.rotation += 0.03


func _hide_circle() -> void:
	if _circle != null:
		_circle.visible = false
	if _charge != null:
		_charge.emitting = false
