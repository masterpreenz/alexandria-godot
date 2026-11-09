extends Node2D
## Phase 0 world viewer: the exported world with a free camera. Pan with WASD / arrow keys or by dragging with the
## middle or right mouse button; zoom with the wheel. Run with [code]-- --shot=path.png [--at=x,y] [--zoom=z][/code]
## to save a screenshot and quit.

@onready var camera: Camera2D = $Camera


func _ready() -> void:
	await get_tree().process_frame
	Shots.take_if_asked(self, camera)


func _process(delta: float) -> void:
	var dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if Input.is_key_pressed(KEY_A): dir.x -= 1
	if Input.is_key_pressed(KEY_D): dir.x += 1
	if Input.is_key_pressed(KEY_W): dir.y -= 1
	if Input.is_key_pressed(KEY_S): dir.y += 1
	camera.position += dir.limit_length(1.0) * 1600.0 * delta / camera.zoom.x


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and (event.button_mask & (MOUSE_BUTTON_MASK_MIDDLE | MOUSE_BUTTON_MASK_RIGHT)):
		camera.position -= event.relative / camera.zoom
	else:
		Shots.wheel_zoom(event, camera, 0.03, 4.0)
