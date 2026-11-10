class_name FloatingText
extends Label
## Words rising off something in the world and fading (from Unity's FloatingText): "+1 Stone", damage, "Needs...".

var _age := 0.0
var life := 1.2                  ## seconds it shows (fading over the last half)


static func spawn(w: World, msg: String, at: Vector2, color := Color.WHITE, font_size := 22, seconds := 1.2) -> void:
	var l := FloatingText.new()
	l.life = seconds
	l.text = msg
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_font_size_override("font_size", font_size)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.z_as_relative = false
	l.z_index = 4090
	l.size = Vector2(240, 30)
	World.keep_lit(l)   # (bright at night too)
	l.position = at - Vector2(120, 15)
	w.add_child(l)


func _process(delta: float) -> void:
	var __t := Time.get_ticks_usec()
	_process_timed(delta)
	Perf.add(&"floating_text.process", __t)


func _process_timed(delta: float) -> void:
	_age += delta
	position.y -= 40.0 * delta
	modulate.a = 1.0 - clampf((_age - life * 0.5) / (life * 0.5), 0.0, 1.0)
	if _age >= life:
		queue_free()
