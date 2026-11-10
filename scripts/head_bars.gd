class_name HeadBars
extends Node2D
## Miko's HP and mana over her head, so a fight needn't be read off the corner of the screen: two thin bars, HP (red,
## her shield in pale blue past it) over mana (blue). They show while either is short of full and fade away a moment
## after both are full again. Bright whatever the hour.

const WIDTH := 46.0
const HP_TALL := 6.0
const MANA_TALL := 4.0
const GAP := 2.0
const LINGER := 1.2              ## seconds they stay after both are full
const FADE := 0.4

var world: World
var miko: Miko
var _full_since := -1.0
var _shown := 0.0


func setup(w: World, who: Miko) -> void:
	world = w
	miko = who
	z_as_relative = false
	z_index = 3997
	World.keep_lit(self)


func _process(delta: float) -> void:
	var st := miko.stats
	if st == null:
		return
	var tot := st.total()
	var max_hp := float(tot.get("maxHp", 100.0))
	var max_mana := float(tot.get("maxMana", 50.0))
	var short := st.hp < max_hp - 0.5 or st.mana < max_mana - 0.5
	var now := Time.get_ticks_msec() / 1000.0
	if short:
		_full_since = -1.0
	elif _full_since < 0.0:
		_full_since = now
	var want := 1.0 if short or (_full_since >= 0.0 and now - _full_since < LINGER and _shown > 0.0) else 0.0
	_shown = move_toward(_shown, want, delta / FADE)
	visible = _shown > 0.0 and miko.visible and st.hp > 0.0
	if not visible:
		return
	# Just over her head (the top of what's drawn of her).
	var top := World.sprite_rect(miko.art).position.y - miko.global_position.y
	position = Vector2(0, top + 0.16 * world.px)
	modulate.a = _shown
	queue_redraw()


func _draw() -> void:
	var st := miko.stats
	if st == null:
		return
	var tot := st.total()
	var max_hp := maxf(1.0, float(tot.get("maxHp", 100.0)))
	var max_mana := maxf(1.0, float(tot.get("maxMana", 50.0)))
	var x := -WIDTH / 2.0
	var y := -(HP_TALL + GAP + MANA_TALL)
	_bar(Rect2(x, y, WIDTH, HP_TALL), st.hp / max_hp, Color(0.9, 0.24, 0.2))
	# Her shield, a pale line along the top of the HP.
	var shield := 0.0
	for k in st.shields:
		shield += float(st.shields[k])
	if shield > 0.5:
		draw_rect(Rect2(x + 2.0, y + 1.0, (WIDTH - 4.0) * clampf(shield / max_hp, 0.0, 1.0), 1.5), Color(0.75, 0.9, 1.0))
	_bar(Rect2(x, y + HP_TALL + GAP, WIDTH, MANA_TALL), st.mana / max_mana, Color(0.36, 0.62, 0.96))


# A rounded bar: a dark pill, filled from the left by [param share].
func _bar(r: Rect2, share: float, fill: Color) -> void:
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.08, 0.05, 0.05, 0.85)
	back.set_corner_radius_all(ceili(r.size.y / 2.0) + 1)
	back.anti_aliasing = true
	draw_style_box(back, r.grow(1.0))
	var w := r.size.x * clampf(share, 0.0, 1.0)
	if w < 1.0:
		return
	var front := StyleBoxFlat.new()
	front.bg_color = fill
	front.set_corner_radius_all(ceili(r.size.y / 2.0))
	front.anti_aliasing = true
	draw_style_box(front, Rect2(r.position, Vector2(maxf(w, r.size.y), r.size.y)))
