class_name LevelUp
extends Node2D
## Miko's level-up moment (from Unity's LevelUpEffect; her character level only, life skills rise quietly): a golden
## flash at her feet, a soft column of light rising and fading, sparkles rising straight up around her, and "LEVEL UP!"
## with the new level over her head. It follows her while it plays and is gone in about two and a half seconds.

const GOLD := Color(1.0, 0.84, 0.38)
const PALE := Color(1.0, 0.97, 0.8)

var age := 0.0
var unit := 128.0


static func play(w: World, who: Node2D, level: int) -> void:
	var fx := LevelUp.new()
	fx.unit = w.px
	fx.z_as_relative = false
	fx.z_index = 3991
	who.add_child(fx)
	# Sparkles rising straight up around her, a burst of them at the start.
	var p := CPUParticles2D.new()
	p.amount = 100
	p.lifetime = 1.4
	p.lifetime_randomness = 0.4
	p.explosiveness = 0.35
	p.one_shot = true
	p.local_coords = true
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.5 * w.px
	p.scale = Vector2(1, 0.5)
	p.direction = Vector2(0, -1)
	p.spread = 0.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 1.2 * w.px * 2.0
	p.initial_velocity_max = 2.6 * w.px * 2.0
	p.texture = Fires._soft_dot()
	p.scale_amount_min = 0.12 * w.px / 64.0 * 2.0
	p.scale_amount_max = 0.26 * w.px / 64.0 * 2.0
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.15, 0.6, 1.0])
	g.colors = PackedColorArray([Color(GOLD, 0), PALE, GOLD, Color(GOLD, 0)])
	p.color_ramp = g
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = add
	p.emitting = true
	fx.add_child(p)
	Sfx.play(w, WorldSounds.chime(), who.position, 0.7)
	FloatingText.spawn(w, Loc.t("levelup.title"), who.position + Vector2(0, -2.1 * w.px), GOLD, 30, 2.4)
	FloatingText.spawn(w, Loc.t("levelup.level", {"level": level}), who.position + Vector2(0, -1.7 * w.px), PALE, 22, 2.4)
	_banner(w, level)


# A banner across the top of the screen: "Level up! · Level 9 · +2 talent points (K)", sliding in and fading after a
# few seconds.
static func _banner(w: World, level: int) -> void:
	var hud := w.get_tree().current_scene.get_node_or_null("Hud")
	if hud == null:
		return
	var k := HudStyle.SCALE
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", HudStyle.piece("panelStrong"))
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(col)
	var title := HudStyle.label(Loc.t("levelup.title"), 22, "bold", GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var sub := HudStyle.label(Loc.t("levelup.banner", {"level": level, "points": CharacterStats.points_per_level_of(w.player.stats.character if w.player != null and "stats" in w.player else {})}), 13, "bold", HudStyle.color("text"))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(sub)
	hud.add_child(box)
	box.reset_size()
	var vp := box.get_viewport_rect().size
	box.position = Vector2((vp.x - box.size.x) / 2.0, -box.size.y).round()
	var tw := box.create_tween()
	tw.tween_property(box, "position:y", 70.0 * k, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(3.2)
	tw.tween_property(box, "modulate:a", 0.0, 0.6)
	tw.tween_callback(box.queue_free)


func _process(delta: float) -> void:
	var __t := Time.get_ticks_usec()
	_process_timed(delta)
	Perf.add(&"level_up.process", __t)


func _process_timed(delta: float) -> void:
	age += delta
	queue_redraw()
	if age > 2.6:
		queue_free()


func _draw() -> void:
	# A quick bright ring at her feet, spreading and fading.
	var t := clampf(age / 0.6, 0.0, 1.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1, 0.5))
	draw_arc(Vector2.ZERO, unit * lerpf(0.25, 1.8, t), 0.0, TAU, 48, Color(GOLD, 1.0 - t), 6.0, true)
	draw_circle(Vector2.ZERO, unit * lerpf(0.2, 1.4, t), Color(GOLD, 0.3 * (1.0 - t)))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# A soft column of light that rises, holds a moment, and fades.
	var rise := clampf(age / 0.25, 0.0, 1.0)
	var alpha := rise if age < 0.25 else clampf(1.0 - (age - 0.6) / 0.9, 0.0, 1.0)
	var w := unit * 0.9 * lerpf(0.6, 1.0, rise)
	var h := unit * 2.6 * rise
	var steps := 8
	for i in steps:
		var f := float(i) / steps
		var a := alpha * 0.8 * (1.0 - f) * 0.35
		draw_rect(Rect2(-w / 2.0 * (1.0 - f * 0.5), -h * (f + 1.0 / steps), w * (1.0 - f * 0.5), h / steps), Color(GOLD, a))
