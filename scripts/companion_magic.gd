class_name CompanionMagic
extends Node
## A companion's own mind in a fight, by their tactics (Tactics: their stance and rules, set in the Tactics window):
## every little while they look about and go down their rules, top first, and do the first whose "when" holds and
## whose "do" can be done now: a spell (a heal on whoever's hurt, armour on whoever's struck, an attack at the monster
## or where the monsters are thickest), a potion from the bag, closing in hand to hand, stepping back, back to the
## leader. With Dodge on, a strip a monster has marked under them for its charge or leap sends them out of it first,
## dropping any spell. Each spell is a short pause: they stand, turn to it, a circle in the spell's colour at their
## feet, and it goes. data/companions.json's "magic" holds the spells' timings and what each is for;
## data/tactics.json the presets and how often each weight lets a rule come round.

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
var _cast_gap := 1.2              ## seconds after a spell before the next (their stance's skill use)
var _rule_next := {}              ## a rule (its place) -> when it may fire again (its weight)
var _rules_hash := 0
var _potion_next := 0.0
var _next_strip_look := 0.0
var _spells_now := {}             ## a rule's spell -> the spells of theirs it stands for, this look
var _foes: Array[Damageable] = [] ## the monsters about, at the last look
var done := {}                    ## action -> times done (the scenarios read these)
var potions := {}                 ## potion -> drunk
var dodges := 0                   ## times stepped out of a marked strip
var cancelled := 0                ## spells dropped to get out of the way
var cast_in_strip := 0            ## spells finished standing in a marked strip


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
	# A strip a monster has marked under them: with Dodge on, out of it before anything else (a spell being cast
	# dropped); looked for often, as a leap comes quickly. With it off they keep at what they're doing.
	if not Telegraph.live.is_empty() and t >= _next_strip_look and t >= body.dodge_until:
		_next_strip_look = t + 0.1
		if body.world != null and body._in_party() and not body.talking and body.hit != null and body.hit.alive() 				and body.state != Villager.State.FLEE and bool(Tactics.stance(body.person).get("dodge", true)):
			var strip := Tactics.strip_at(body.position)
			if strip != null:
				if _pending != "":
					_cancel()
				_dodge(strip, t)
				return
	if _pending != "":
		_follow_circle()
		if t >= body.cast_until:
			_release(t)
		return
	if t < _next:
		return
	_next = t + float(Tactics.data().get("think", 0.3))
	if body.world == null or not body._in_party() or body.talking or body.hit == null or not body.hit.alive():
		return
	if body.state == Villager.State.FLEE or body.state == Villager.State.ASLEEP or t < body.dodge_until or t < body.cast_until:
		return
	var st := Companions.stats_for(body.person)
	if st == null:
		return
	_look_at_lead(t)
	var __t := Time.get_ticks_usec()
	_follow_rules(t, st, Tactics.of(body.person))
	Perf.add(&"companion_magic.rules", __t)


# Their rules, top first: the first that holds and can be done now is done.
func _follow_rules(t: float, st: CharacterStats, tac: Dictionary) -> void:
	var stance: Dictionary = tac.stance
	_gather_foes()
	var foe := _foe()
	_spells_now.clear()
	var rules: Array = tac.rules
	# (their rules changed in the Tactics window: each starts afresh)
	if rules.hash() != _rules_hash:
		_rules_hash = rules.hash()
		_rule_next.clear()
	for i in rules.size():
		var r: Dictionary = rules[i]
		if not bool(r.get("on", true)) or (str(r.get("do", "")) == "cast" and _spells(st, str(r.get("spell", ""))).is_empty()):
			continue
		var key := i
		if t < float(_rule_next.get(key, 0.0)):
			continue
		var ctx := _holds(r, t, st, foe)
		if ctx.is_empty():
			continue
		# (its weight: how soon it can come again, and how readily it's taken)
		var w := Tactics.weight(int(r.get("weight", 3)))
		if randf() > float(w.get("chance", 1.0)):
			_rule_next[key] = t + 1.0
			continue
		if _do(r, ctx, t, st, stance):
			_rule_next[key] = t + float(w.get("every", 1.5))
			var what := str(r.get("do", ""))
			done[what] = int(done.get(what, 0)) + 1
			return


# The spells of theirs a rule's spell stands for (worked out once a look).
func _spells(st: CharacterStats, spell: String) -> Array:
	if not _spells_now.has(spell):
		if not _spells_now.has(""):
			_spells_now[""] = st.known_spells()
		_spells_now[spell] = Tactics.spells_for(st, spell, _spells_now[""])
	return _spells_now[spell]


# The leader's HP watched: less than at the last look, they've been hit.
func _look_at_lead(t: float) -> void:
	var lead: Miko = body.world.player as Miko
	if lead != null and lead.stats != null:
		if _sera_hp >= 0.0 and lead.stats.hp < _sera_hp - 0.01:
			_sera_hit_at = t
		_sera_hp = lead.stats.hp


# The monster they're fighting, else the one nearest the leader or them coming for either.
func _foe() -> Damageable:
	if body.foe != null and is_instance_valid(body.foe) and body.foe.alive():
		return body.foe
	return body._party_threat()


# Whether a rule's condition holds now: {} if not, else what it found (the foe, the ally it's about, the strip).
func _holds(r: Dictionary, t: float, st: CharacterStats, foe: Damageable) -> Dictionary:
	var td := Tactics.data()
	var when := str(r.get("when", ""))
	var v := float(r.get("value", Tactics.condition(when).get("default", 50)))
	var lately := float(td.get("guardAfter", 2.5))
	var yes := {"foe": foe}
	var lead := body.world.player as Miko
	match when:
		"always":
			return yes
		"inFight":
			return yes if foe != null else {}
		"selfHpBelow":
			return yes if body.hit.hp < body.hit.max_hp * v / 100.0 else {}
		"selfManaBelow":
			var most := st.stat("maxMana")
			return yes if most > 0.0 and st.mana < most * v / 100.0 else {}
		"allyHpBelow":
			var who := _ally(func(b: Node2D, s: CharacterStats) -> bool: return SpellEffects.WaterBlanket.share_of_hp(b, s) < v / 100.0)
			return {"foe": foe, "ally": who} if who != null else {}
		"leaderHpBelow":
			if lead != null and lead.stats != null and SpellEffects.WaterBlanket.share_of_hp(lead, lead.stats) < v / 100.0:
				return {"foe": foe, "ally": lead}
		"beingAttacked":
			return yes if t - _hit_at < lately else {}
		"leaderAttacked":
			if lead != null and t - _sera_hit_at < lately:
				return {"foe": _nearest_foe(lead.position, Party.GUARD), "ally": lead}
		"enemyInMelee":
			var f := _nearest_foe(body.position, float(td.get("meleeRange", 1.6)))
			return {"foe": f} if f != null else {}
		"enemiesNear":
			return yes if _count_near(float(td.get("nearRange", 5.0))) >= int(v) else {}
		"allyNoShield":
			var who := _ally(func(b: Node2D, _s: CharacterStats) -> bool: return t - _hit_time(b) < lately and not SpellEffects.FrostArmor.on(b))
			return {"foe": foe, "ally": who} if who != null else {}
		"allyNoBlanket":
			var who := _ally(func(b: Node2D, s: CharacterStats) -> bool: return SpellEffects.WaterBlanket.share_of_hp(b, s) < v / 100.0 and not SpellEffects.WaterBlanket.on(b))
			return {"foe": foe, "ally": who} if who != null else {}
		"enemyFrozen":
			var f := _frozen_foe()
			return {"foe": f} if f != null else {}
		"inTelegraph":
			var strip := Tactics.strip_at(body.position)
			return {"foe": foe, "strip": strip} if strip != null else {}
	return {}


# Does a rule's action, if it can be done now (and makes a difference): whether it was.
func _do(r: Dictionary, ctx: Dictionary, t: float, st: CharacterStats, stance: Dictionary) -> bool:
	var td := Tactics.data()
	var w := body.world
	var lead := w.player as Node2D
	match str(r.get("do", "")):
		"cast":
			return _cast_rule(str(r.get("spell", "@attack")), ctx, t, st, stance)
		"hpPotion", "manaPotion":
			if t < _potion_next:
				return false
			var potion := "HpPotion" if str(r.do) == "hpPotion" else "ManaPotion"
			if Tactics.drink(body, st, potion):
				_potion_next = t + float(td.get("potionEvery", 8.0))
				potions[potion] = int(potions.get(potion, 0)) + 1
				return true
		"attackNearest":
			return _melee(_nearest_foe(body.position, Party.GUARD), t)
		"attackLeaderTarget":
			var f: Damageable = ctx.get("foe") if str(r.get("when", "")) == "leaderAttacked" else null
			if f == null and lead != null:
				f = _nearest_foe(lead.position, Party.GUARD)
			return _melee(f, t)
		"keepDistance":
			var f := _nearest_foe(body.position, float(td.get("keepNear", 4.0)))
			return f != null and body.step_back(f.global_position, t)
		"toLeader":
			if lead == null or lead.position.distance_to(body.position) < 2.5 * w.px:
				return false
			body.hold_until = t + 2.5
			body.foe = null
			body._follow_start(t)
			return true
		"dodge":
			var strip: Telegraph = ctx.get("strip") if ctx.get("strip") != null else Tactics.strip_at(body.position)
			if strip == null:
				return false
			_dodge(strip, t)
			return true
	return false


# Into the fight hand to hand with [param f] (closing in a while, even if they'd keep their distance otherwise).
# Whether that's a change.
func _melee(f: Damageable, t: float) -> bool:
	if f == null:
		return false
	body.melee_until = t + 3.0
	body.hold_until = 0.0
	if body.state == Villager.State.FIGHT and body.foe == f:
		return false
	body._fight(f)
	return true


# A rule's spell cast, if one of those it stands for is ready, affordable (attacks keep the mana reserve back) and
# has someone or something to go at: whether one was started.
func _cast_rule(spell: String, ctx: Dictionary, t: float, st: CharacterStats, stance: Dictionary) -> bool:
	if t < _gap_until:
		return false
	var cfg: Dictionary = Companions.data().get("magic", {})
	var uses: Dictionary = cfg.get("spells", {})
	var freq := Tactics.frequency(str(stance.get("frequency", "normal")))
	var reserve := (float(stance.get("reserve", 0.0)) + float(freq.get("reserve", 0.0))) / 100.0 * st.stat("maxMana")
	var foe: Damageable = ctx.get("foe")
	for sp in _spells(st, spell):
		var s := Companions.spell(str(sp))
		if s.is_empty() or t < float(ready_at.get(sp, 0.0)):
			continue
		var kind := Tactics.kind_of(str(sp))
		var cost := float(s.get("manaCost", 0.0))
		if st.mana + 0.001 < cost + (reserve if kind in ["attack", "area"] else 0.0):
			continue
		var at: Damageable = null
		var spot := Vector2.INF
		var ally: Node2D = null
		match kind:
			"heal":
				ally = ctx.get("ally")
				if ally == null:
					ally = _ally(func(b: Node2D, bs: CharacterStats) -> bool: return SpellEffects.WaterBlanket.share_of_hp(b, bs) < 0.95)
				if ally == null or SpellEffects._ground_gap(ally.global_position, body.position) > float(s.get("range", 640.0)):
					continue
			"guard":
				# (armour goes on everyone near them: the one it's for must be within its reach, and not wearing it)
				var who: Node2D = ctx.get("ally") if ctx.get("ally") != null else body
				if SpellEffects._ground_gap(who.global_position, body.position) > float(s.get("reach", s.get("range", 200.0))):
					continue
				if str(s.get("effect", "")) == "FrostArmor" and SpellEffects.FrostArmor.on(who):
					continue
			"area":
				var best := _thickest(float(s.get("range", 0.0)), float(s.get("aoeRadius", 64.0)))
				if int(best[1]) < maxi(1, int(uses.get(sp, {}).get("atLeast", 1))):
					continue
				spot = best[0]
			"attack":
				var f := foe if foe != null else _foe()
				if f == null or f.global_position.distance_to(body.position) > float(s.get("range", 0.0)):
					continue
				at = f
			_:
				continue
		if st.spend_mana(cost):
			_cast_gap = float(freq.get("gap", cfg.get("gap", 1.2)))
			_start(str(sp), s, at, t, cfg, spot, ally)
			return true
	return false


# Whom of the party (the leader, the companions, themselves) a heal or shield is for, of those [param fits] holds for:
# as their stance says (the leader first, themselves first, or the most hurt); null if nobody.
func _ally(fits: Callable) -> Node2D:
	var protect := str(Tactics.stance(body.person).get("protect", "lowest"))
	var best: Node2D = null
	var low := INF
	for pair in SpellEffects.party_near(body.world, body.position, INF):
		var b: Node2D = pair[0]
		if not fits.call(b, pair[1]):
			continue
		if (protect == "leader" and b == body.world.player) or (protect == "self" and b == body):
			return b
		var f := SpellEffects.WaterBlanket.share_of_hp(b, pair[1])
		if f < low:
			low = f
			best = b
	return best


# When [param who] (of the party) was last struck.
func _hit_time(who: Node2D) -> float:
	if who == body:
		return _hit_at
	if who == body.world.player:
		return _sera_hit_at
	var m := who.get_node_or_null("Magic") as CompanionMagic
	return m._hit_at if m != null else -99.0


# A monster (one they'd fight) within [param units] of [param at], the nearest; or null.
func _nearest_foe(at: Vector2, units: float) -> Damageable:
	var best: Damageable = null
	var best_d := units * body.world.px
	for d in _foes:
		if _is_foe(d):
			var dd := d.global_position.distance_to(at)
			if dd < best_d:
				best_d = dd
				best = d
	return best


func _count_near(units: float) -> int:
	var n := 0
	for d in _foes:
		if _is_foe(d) and d.global_position.distance_to(body.position) <= units * body.world.px:
			n += 1
	return n


# The nearest monster near them frozen solid or frostbitten.
func _frozen_foe() -> Damageable:
	var best: Damageable = null
	var best_d := Party.GUARD * body.world.px
	for d in _foes:
		if _is_foe(d) and (StatusEffects.frozen(d) or StatusEffects.has_effect(d, "Frostbite")):
			var dd := d.global_position.distance_to(body.position)
			if dd < best_d:
				best_d = dd
				best = d
	return best


# The monsters about (near them or the leader), gathered once a look for the rules to ask about.
func _gather_foes() -> void:
	_foes.clear()
	var lead := body.world.player as Node2D
	var far := 2.0 * Party.GUARD * body.world.px
	for d in Damageable.all:
		if _is_foe(d) and (d.global_position.distance_to(body.position) < far or (lead != null and d.global_position.distance_to(lead.position) < far)):
			_foes.append(d)


static func _is_foe(d: Damageable) -> bool:
	return is_instance_valid(d) and d.alive() and d.team == Damageable.Team.ENEMY and d.get_parent() is Creature and not d.get_parent() is Rabbit


# Out of [param strip] sideways (to the nearer edge), a step past it.
func _dodge(strip: Telegraph, t: float) -> void:
	var w := body.world
	var g := Telegraph._ground(body.position - strip.from)
	var gd := Telegraph._ground(strip.dir * strip.length)
	var n := Vector2(-gd.y, gd.x).normalized()
	var side := g.dot(n)
	var sgn := signf(side)
	if absf(side) < 0.05 * w.px:
		# (right down the middle: the side nearer the leader)
		var lead := w.player as Node2D
		sgn = signf(Telegraph._ground(lead.position - body.position).dot(n)) if lead != null else 1.0
		sgn = 1.0 if sgn == 0.0 else sgn
	var out := sgn * (strip.width * 0.5 + float(Tactics.data().get("dodgeMargin", 0.45)) * w.px) - side
	body.dodge_to = body.position + Telegraph._screen(n * out)
	body.dodge_until = t + 1.2
	dodges += 1


# The spell being cast dropped (to get out of the way): its mana back, the circle gone.
func _cancel() -> void:
	var st := Companions.stats_for(body.person)
	var s := Companions.spell(_pending)
	if st != null and not s.is_empty():
		st.mana = minf(st.stat("maxMana"), st.mana + float(s.get("manaCost", 0.0)))
	_pending = ""
	_pending_foe = null
	_pending_ally = null
	_hide_circle()
	body.cast_until = 0.0
	cancelled += 1


# Where the monsters are thickest within [param reach] of her, for a spell of area [param area]: [spot, how many].
func _thickest(reach: float, area: float) -> Array:
	var foes := []
	for d in _foes:
		if _is_foe(d) and d.global_position.distance_to(body.position) <= reach:
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
	_gap_until = t + _cast_gap
	if Tactics.strip_at(body.position) != null:
		cast_in_strip += 1
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
