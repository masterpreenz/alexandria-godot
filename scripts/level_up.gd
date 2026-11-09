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
	FloatingText.spawn(w, "LEVEL UP!", who.position + Vector2(0, -1.7 * w.px), GOLD)
	FloatingText.spawn(w, "Lv %d" % level, who.position + Vector2(0, -1.25 * w.px), PALE)


func _process(delta: float) -> void:
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
