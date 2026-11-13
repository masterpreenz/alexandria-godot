extends AnimatedSprite2D
## One-shot VFX. Node origin = ground contact point (BASE pivot).

@export var free_when_done := true

func _ready() -> void:
	play("default")
	if free_when_done:
		animation_finished.connect(queue_free)
