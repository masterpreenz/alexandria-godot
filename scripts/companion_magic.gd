class_name CompanionMagic
extends Node
## A companion's own spellcasting (Miyu once she has her water book): while she's with Sera and a monster's near (the
## ones she'd fight), she casts the spells she knows when they're ready and she has the mana for them: a heal when Sera
## or she is hurt, a barrier while she's being hit, else her attack spells at the monster (in their range). Each is a
## short pause: she stands, turns to it, a circle in the spell's colour at her feet, and it goes. Otherwise she fights
## as ever. data/companions.json's "magic" holds the timings.

const PROJECTILE_LIFT := 0.45     ## units above her feet a spell she throws leaves from

signal cast(spell: String, at: Vector2)

var body: Villager
var ready_at := {}                ## spell -> when it can be cast again
var casts: Array = []             ## [spell, at] of each cast so far (the scenarios read it)
var _next := 0.0
var _gap_until := 0.0
var _hit_at := -99.0
var _pending := ""                ## the spell being cast, till the pause is over
var _pending_foe: Damageable      ## the monster it goes at (followed till it goes), or null: at her own feet
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
	var foe := body.foe if body.foe != null and is_instance_valid(body.foe) and body.foe.alive() else body._party_threat()
	if foe == null:
		return
	var uses: Dictionary = cfg.get("spells", {})
	# What's called for, most pressing first: a heal, a barrier, then the attacks.
	var heal_below := float(cfg.get("healBelow", 0.6))
	var sera: Miko = body.world.player as Miko
	var sera_low := sera != null and sera.stats != null and sera.stats.hp < sera.stats.stat("maxHp") * heal_below
	var me_low := body.hit.hp < body.hit.max_hp * heal_below
	var hit_lately := t - _hit_at < float(cfg.get("guardAfter", 2.5))
	for want in ["heal", "guard", "attack"]:
		for sp in known:
			var s := Companions.spell(sp)
			if s.is_empty() or _use_of(sp, s, uses) != want or t < float(ready_at.get(sp, 0.0)):
				continue
			if st.mana + 0.001 < float(s.get("manaCost", 0.0)):
				continue
			var at: Damageable = null
			match want:
				"heal":
					if not (sera_low or me_low):
						continue
				"guard":
					if not hit_lately or body.hit.shields.size() > 0 or st.shield() > 0.0:
						continue
				"attack":
					if foe.global_position.distance_to(body.position) > float(s.get("range", 0.0)):
						continue
					at = foe
			if st.spend_mana(float(s.get("manaCost", 0.0))):
				_start(sp, s, at, t, cfg)
				return


# What a spell's for: as companions.json says, else to attack if it does damage.
func _use_of(sp: String, s: Dictionary, uses: Dictionary) -> String:
	if uses.has(sp):
		return str(uses[sp].get("use", ""))
	if str(s.get("effect", "")) == "Shikigami":
		return ""
	return "attack" if float(s.get("damage", 0.0)) > 0.0 and str(s.get("delivery", "")) in ["Directional", "SkyFall", "Ground"] else ""


# She stops, turns to it, and the circle comes up at her feet.
func _start(sp: String, s: Dictionary, at: Damageable, t: float, cfg: Dictionary) -> void:
	var st := Companions.stats_for(body.person)
	var quick := 1.0 + maxf(0.0, st.stat("castSpeed")) / 100.0
	var pause := clampf(float(s.get("castTime", 1.0)) * float(cfg.get("pauseShare", 0.4)) / quick, float(cfg.get("pauseMin", 0.5)), float(cfg.get("pauseMax", 1.1)))
	_pending = sp
	_pending_foe = at
	_pending_spot = at.global_position if at != null else body.position
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
	if _pending_foe != null and is_instance_valid(_pending_foe) and _pending_foe.alive():
		target = _pending_foe.global_position
	elif _pending_foe == null:
		target = body.position
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
	var cdr := clampf(st.stat("cooldownReduction"), 0.0, 60.0)
	var cd := float(s.get("cooldown", 0.0)) * (1.0 - cdr / 100.0)
	if str(s.get("delivery", "")) == "SkyFall":
		cd *= 1.0 - clampf(st.stat("meteorCooldown"), 0.0, 60.0) / 100.0
	ready_at[sp] = t + cd
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
