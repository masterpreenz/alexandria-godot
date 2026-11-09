class_name FloatingText
extends Label
## Words rising off something in the world and fading (from Unity's FloatingText): "+1 Stone", damage, "Needs...".

var _age := 0.0


static func spawn(w: World, text: String, at: Vector2, color := Color.WHITE) -> void:
	var l := FloatingText.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_font_size_override("font_size", 22)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.z_as_relative = false
	l.z_index = 4090
	l.size = Vector2(240, 30)
	l.position = at - Vector2(120, 15)
	w.add_child(l)


func _process(delta: float) -> void:
	_age += delta
	position.y -= 40.0 * delta
	modulate.a = 1.0 - clampf((_age - 0.6) / 0.6, 0.0, 1.0)
	if _age >= 1.2:
		queue_free()
