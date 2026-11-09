class_name SpellCaster
extends Node2D
## Aims and casts spells (from Unity's SpellCaster). A spell's key or slot starts aiming: a ring the size of the
## spell's area follows the mouse (up to its range), with a line along a directional spell's path; clicking the
## ground picks where it lands. Miko then holds the cast pose over the element's magic circle, a cast bar filling over
## her, for the spell's cast time (shorter with cast speed), and lets it go; a ground or sky spell's ring stays where
## it was aimed meanwhile, turning on the ground. Right-click, Escape or the same key again cancels aiming. Casting
## costs mana up front; cooldowns are shortened by cooldown reduction (at most 60%).

signal cast_done(spell: String)

var world: World
var miko: Miko
var stats: CharacterStats
var spells: Dictionary       ## name -> spell (combat.json)
var data: Dictionary         ## the caster's settings (marker, circles, offsets)
var aiming := ""             ## the spell being aimed, or ""
var casting := false
var ready_at := {}           ## spell -> when it can be cast again
var cooldown_of := {}        ## spell -> the whole cooldown it last started
var shikigami := {}          ## spell -> its shikigami's settings (shikigami.json)

var _marker: Sprite2D
var _pinned: Sprite2D
var _circle: Sprite2D
var _bar: Node2D
var _bar_fill := 0.0
var _bar_color := Color.WHITE
var _charge: CPUParticles2D
var _pin_spin := 0.0


func setup(w: World, who: Miko, st: CharacterStats, sp: Dictionary, d: Dictionary) -> void:
	world = w
	miko = who
	stats = st
	spells = sp
	data = d
	var f := FileAccess.open("res://data/shikigami.json", FileAccess.READ)
	if f != null:
		shikigami = JSON.parse_string(f.get_as_text())
	z_as_relative = false
	z_index = 3995
	_marker = _ring()
	_pinned = _ring()
	_circle = Sprite2D.new()
	_circle.visible = false
	_circle.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF  # placed by hand each frame
	world.add_ground_layer(_circle, -9979)  # on the ground under her (following her as she turns)
	_charge = CPUParticles2D.new()
	_charge.emitting = false
	_charge.amount = 30
	_charge.lifetime = 0.9
	_charge.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_charge.emission_rect_extents = Vector2(30, 6)
	_charge.direction = Vector2(0, -1)
	_charge.spread = 15.0
	_charge.gravity = Vector2.ZERO
	_charge.initial_velocity_min = 40.0
	_charge.initial_velocity_max = 90.0
	_charge.texture = Waterfall._dot(16, 1.0)
	_charge.scale_amount_min = 0.4
	_charge.scale_amount_max = 0.8
	miko.add_child(_charge)


func _ring() -> Sprite2D:
	var r := Sprite2D.new()
	world.show_frame(r, int(data.marker))
	r.centered = true
	r.offset = Vector2.ZERO
	r.visible = false
	add_child(r)
	return r


func cooldown_left(spell: String) -> float:
	return maxf(0.0, ready_at.get(spell, 0.0) - _now())


func cooldown_total(spell: String) -> float:
	return cooldown_of.get(spell, float(spells.get(spell, {}).get("cooldown", 0.0)))


func _cooldown(spell: String) -> float:
	var cdr := clampf(stats.stat("cooldownReduction"), 0.0, 60.0)
	return float(spells[spell].cooldown) * (1.0 - cdr / 100.0)


## Starts [param spell]'s cooldown (now, or when its summon has gone).
func start_cooldown(spell: String) -> void:
	cooldown_of[spell] = _cooldown(spell)
	ready_at[spell] = _now() + cooldown_of[spell]


func can_cast(spell: String) -> bool:
	return spells.has(spell) and not casting and cooldown_left(spell) <= 0.0 and stats.mana + 0.001 >= float(spells[spell].manaCost)


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


## Starts aiming [param spell], or cancels if it's already being aimed; a self spell goes off at once.
func toggle_aiming(spell: String) -> void:
	if casting or not spells.has(spell) or (spell != aiming and cooldown_left(spell) > 0.0):
		return
	if spells[spell].delivery == "Self":
		cast_at(spell, miko.position)
		return
	_set_aiming("" if aiming == spell else spell)


func cast_at(spell: String, target: Vector2) -> void:
	if casting or cooldown_left(spell) > 0.0:
		return
	if not stats.spend_mana(float(spells[spell].manaCost)):
		FloatingText.spawn(world, "Not enough mana", miko.position + Vector2(0, -1.8 * world.px), Color(0.6, 0.75, 1.0))
		_set_aiming("")
		return
	_cast(spell, target)


func _unhandled_input(event: InputEvent) -> void:
	if aiming == "":
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_set_aiming("")
		elif event.button_index == MOUSE_BUTTON_LEFT:
			cast_at(aiming, _aim_point(aiming))
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_set_aiming("")
		get_viewport().set_input_as_handled()


# The ring follows the mouse, up to the spell's range.
func _aim_point(spell: String) -> Vector2:
	var to := get_global_mouse_position() - miko.position
	return miko.position + to.limit_length(float(spells[spell].range))


func _process(delta: float) -> void:
	if aiming != "":
		var t := _aim_point(aiming)
		_marker.position = t
		_size_ring(_marker, aiming, 1.0 + 0.06 * sin(_now() * 6.0))
	if _pinned.visible:
		_pin_spin += delta
	if _circle.visible:
		_circle.position = miko.drawn_position() + Vector2(0, data.circleY)
		_circle.rotation += deg_to_rad(float(data.spinSpeed)) * delta
	queue_redraw()


# The ring art lies flat on the ground; sized to the spell's area.
func _size_ring(r: Sprite2D, spell: String, k: float) -> void:
	var s := float(spells[spell].aoeRadius) / float(data.markerRadius) * k
	var info: Dictionary = world.sprites[int(data.marker)]
	var base := world.px / float(info.ppu)
	r.scale = Vector2(s, s) * base
	r.modulate = SpellEffects.color(spells[spell])


func _draw() -> void:
	# A directional spell's path while aiming.
	if aiming != "" and spells[aiming].delivery == "Directional":
		var c := SpellEffects.color(spells[aiming])
		draw_line(miko.position, _marker.position, Color(c, 0.4), 3.0, true)
	# The cast bar over her while casting.
	if casting:
		var at := miko.drawn_position() + Vector2(data.barOffset[0], data.barOffset[1]) + Vector2(-40, 0)
		draw_rect(Rect2(at, Vector2(80, 9)), Color(0.12, 0.08, 0.06, 0.85))
		draw_rect(Rect2(at + Vector2(1, 1), Vector2(78 * _bar_fill, 7)), _bar_color)


func _set_aiming(spell: String) -> void:
	aiming = spell
	_marker.visible = spell != ""
	if spell != "":
		_size_ring(_marker, spell, 1.0)


const ELEMENTS := ["Fire", "Ice", "Lightning", "Water", "Wind", "Light", "Dark"]


func _cast(spell: String, target: Vector2) -> void:
	var s: Dictionary = spells[spell]
	_set_aiming("")
	casting = true
	miko.locked = true
	var c := SpellEffects.color(s)
	_bar_color = c
	_bar_fill = 0.0
	miko.hold_cast(target - miko.position)
	_charge.color = c
	_charge.emitting = true
	var e := ELEMENTS.find(s.element)
	var circles: Array = data.circles
	if e >= 0 and e < circles.size() and int(circles[e]) >= 0:
		world.show_frame(_circle, int(circles[e]), Vector2.ONE * float(data.circleScale))
		_circle.centered = true
		_circle.offset = Vector2.ZERO
		_circle.position = miko.drawn_position() + Vector2(0, data.circleY)
		_circle.visible = true
	var cast_time := float(s.castTime) / (1.0 + maxf(0.0, stats.stat("castSpeed")) / 100.0)
	# Ground and sky spells leave their ring where they were aimed, turning until they go off.
	var pin: bool = s.delivery == "SkyFall" or s.delivery == "Ground"
	if pin:
		_pinned.position = target
		_size_ring(_pinned, spell, 1.0)
		_pinned.visible = true
		_pin_spin = 0.0
	var t := 0.0
	while t < cast_time:
		await get_tree().process_frame
		t += get_process_delta_time()
		_bar_fill = clampf(t / cast_time, 0.0, 1.0)
		if pin:
			_pinned.rotation = -deg_to_rad(t * float(data.pinnedSpin))
	_pinned.visible = false
	_charge.emitting = false
	var origin := target
	var ground_origin := target
	match s.delivery:
		"Directional":
			ground_origin = miko.position
			origin = miko.position + Vector2(data.bodyCentre[0], data.bodyCentre[1])
		"SkyFall":
			origin = target + Vector2(data.skyOffset[0], data.skyOffset[1])
	if s.effect == "Shikigami" and shikigami.has(spell):
		Shikigami.summon(world, spell, shikigami[spell], miko, stats, self, target)
	else:
		SpellEffects.begin(world, s, stats, origin, ground_origin, target)
	# A summon that cools down only once it's gone waits (ShikigamiHealer); the rest start now.
	if bool(s.get("cooldownAfterSummon", false)):
		cooldown_of[spell] = _cooldown(spell)
		ready_at[spell] = INF
	else:
		start_cooldown(spell)
	cast_done.emit(spell)
	await get_tree().create_timer(0.25).timeout
	miko.end_cast()
	_circle.visible = false
	miko.locked = false
	casting = false
