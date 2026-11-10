class_name HeadBars
extends Node2D
## Miko's HP and mana beside her, so a fight needn't be read off the corner of the screen: two thin upright bars at her
## lower left, standing from her feet and filling upwards, HP (red, her shield a pale line up its side) and mana
## (blue, shorter) beside it. Out of the way of the casting bar over her head. They show while either is short of full and fade away a moment
## after both are full again. Bright whatever the hour.

const THICK := 5.0               ## how wide each bar is
const HP_TALL := 62.0            ## how tall the HP bar stands
const MANA_TALL := 44.0
const GAP := 3.0
const BESIDE := 0.36             ## units left of her middle the nearer bar stands
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
	# At her feet (the bars stand up from there, to her left).
	position = Vector2.ZERO
	modulate.a = _shown
	queue_redraw()


func _draw() -> void:
	var st := miko.stats
	if st == null:
		return
	var tot := st.total()
	var max_hp := maxf(1.0, float(tot.get("maxHp", 100.0)))
	var max_mana := maxf(1.0, float(tot.get("maxMana", 50.0)))
	var x := -BESIDE * world.px - THICK
	_bar(Rect2(x - THICK - GAP, -HP_TALL, THICK, HP_TALL), st.hp / max_hp, Color(0.9, 0.24, 0.2))
	# Her shield, a pale line up the HP's outer side.
	var shield := 0.0
	for k in st.shields:
		shield += float(st.shields[k])
	if shield > 0.5:
		var sh := (HP_TALL - 4.0) * clampf(shield / max_hp, 0.0, 1.0)
		draw_rect(Rect2(x - THICK - GAP - 3.0, -2.0 - sh, 1.5, sh), Color(0.75, 0.9, 1.0))
	_bar(Rect2(x, -MANA_TALL, THICK, MANA_TALL), st.mana / max_mana, Color(0.36, 0.62, 0.96))


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
