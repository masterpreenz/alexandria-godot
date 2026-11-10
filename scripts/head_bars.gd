class_name HeadBars
extends Node2D
## Miko's HP and mana over her head, so a fight needn't be read off the corner of the screen: two thin bars, HP (red,
## her shield in pale blue past it) over mana (blue). They show while either is short of full and fade away a moment
## after both are full again. Bright whatever the hour.

const WIDTH := 66.0
const HP_TALL := 8.0
const MANA_TALL := 6.0
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
	var dark := Color(0.08, 0.05, 0.05, 0.85)
	var x := -WIDTH / 2.0
	var y := -(HP_TALL + GAP + MANA_TALL)
	draw_rect(Rect2(x - 1, y - 1, WIDTH + 2, HP_TALL + 2), dark)
	draw_rect(Rect2(x, y, WIDTH * clampf(st.hp / max_hp, 0.0, 1.0), HP_TALL), Color(0.9, 0.24, 0.2))
	# Her shield, over the HP's end.
	var shield := 0.0
	for k in st.shields:
		shield += float(st.shields[k])
	if shield > 0.5:
		draw_rect(Rect2(x, y, WIDTH * clampf(shield / max_hp, 0.0, 1.0), 2.0), Color(0.7, 0.86, 1.0))
	var my := y + HP_TALL + GAP
	draw_rect(Rect2(x - 1, my - 1, WIDTH + 2, MANA_TALL + 2), dark)
	draw_rect(Rect2(x, my, WIDTH * clampf(st.mana / max_mana, 0.0, 1.0), MANA_TALL), Color(0.36, 0.62, 0.96))
