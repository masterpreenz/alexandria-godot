class_name StatusBars
extends Control
## Miko's HP and mana, in the corner (the start of Unity's PlayerHud: its full frame comes with the HUD in phase 5).

var stats: CharacterStats


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if stats == null:
		return
	var t := stats.total()
	_bar(0, stats.hp, t.get("maxHp", 100.0), UiKit.colors.get("hp", Color(0.85, 0.2, 0.18)), "HP")
	# A shield shows as a blue band over the top of the HP bar.
	var sh := stats.shield()
	if sh > 0.0:
		var most := maxf(1.0, t.get("maxHp", 100.0))
		draw_rect(Rect2(2, 2, 216.0 * clampf(sh / most, 0.0, 1.0), 6), Color(0.55, 0.8, 1.0, 0.95))
	_bar(26, stats.mana, t.get("maxMana", 50.0), UiKit.colors.get("mana", Color(0.25, 0.5, 0.98)), "MP")
	var f: Font = UiKit.body_font if UiKit.body_font else get_theme_default_font()
	var line := "Level %d   XP %d / %d" % [stats.level, stats.xp, stats.xp_to_next()]
	draw_string_outline(f, Vector2(0, 70), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 5, Color(0, 0, 0, 0.8))
	draw_string(f, Vector2(0, 70), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)


func _bar(y: float, v: float, most: float, c: Color, label: String) -> void:
	var w := 220.0
	draw_rect(Rect2(0, y, w, 20), Color(0.1, 0.07, 0.06, 0.8))
	draw_rect(Rect2(2, y + 2, (w - 4) * clampf(v / maxf(1.0, most), 0.0, 1.0), 16), c)
	var f: Font = UiKit.body_font if UiKit.body_font else get_theme_default_font()
	var text := "%s %d / %d" % [label, roundi(v), roundi(most)]
	draw_string_outline(f, Vector2(6, y + 16), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color(0, 0, 0, 0.8))
	draw_string(f, Vector2(6, y + 16), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
