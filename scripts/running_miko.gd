class_name RunningMiko
extends Control
## Miko running in place (her down-right run, 12 frames a second), drawn [member height] px tall with her feet on the
## bottom of the control: the loading screen's progress (she runs along its track) and the "Saving…" indicator.

var world: World
var height := 64.0
var alpha := 1.0
var _frames: Array = []
var _fps := 12.0


func setup(w: World) -> void:
	world = w
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/player.json"))
	_frames = d.get("frames", {}).get("runDownRight", [])
	_fps = float(d.get("runFps", 12))
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if world == null or _frames.is_empty():
		return
	var id := int(_frames[int(Time.get_ticks_msec() / 1000.0 * _fps) % _frames.size()])
	var info: Dictionary = world.sprites[id]
	var tex := world._texture(info.tex)
	var region := Rect2(info.rect[0], info.rect[1], info.rect[2], info.rect[3])
	var k := height / region.size.y
	var w := region.size.x * k
	# Her feet (the sprite's pivot) at the middle of the bottom edge.
	var at := Vector2(size.x / 2.0 - float(info.pivot[0]) * k, size.y - float(info.pivot[1]) * k)
	draw_texture_rect_region(tex, Rect2(at, Vector2(w, height)), region, Color(1, 1, 1, alpha))
