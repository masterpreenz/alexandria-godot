class_name HudPiece
extends StyleBox
## One of the HUD's 9-sliced pieces (a pill, a slot, a panel...), drawn as Unity draws a sliced sprite: the corners at
## their own size, or, when the piece is drawn smaller than its corners need, all of them shrunk evenly so its shape
## holds (a pill stays round at any height; Godot's StyleBoxTexture would pinch it instead).

var texture: Texture2D
var region := Rect2()
var left := 0.0
var top := 0.0
var right := 0.0
var bottom := 0.0
var tint := Color.WHITE


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	if texture == null:
		return
	# Shrunk evenly when the rect is smaller than the corners on either axis.
	var k := 1.0
	if left + right > 0.0:
		k = minf(k, rect.size.x / (left + right))
	if top + bottom > 0.0:
		k = minf(k, rect.size.y / (top + bottom))
	var dl := left * k
	var dt := top * k
	var dr := right * k
	var db := bottom * k
	# Columns and rows, in the picture and on screen.
	var sx := [region.position.x, region.position.x + left, region.end.x - right, region.end.x]
	var sy := [region.position.y, region.position.y + top, region.end.y - bottom, region.end.y]
	var dx := [rect.position.x, rect.position.x + dl, rect.end.x - dr, rect.end.x]
	var dy := [rect.position.y, rect.position.y + dt, rect.end.y - db, rect.end.y]
	var rid := texture.get_rid()
	for i in 3:
		for j in 3:
			var src := Rect2(sx[i], sy[j], sx[i + 1] - sx[i], sy[j + 1] - sy[j])
			var dst := Rect2(dx[i], dy[j], dx[i + 1] - dx[i], dy[j + 1] - dy[j])
			if src.size.x <= 0.0 or src.size.y <= 0.0 or dst.size.x <= 0.0 or dst.size.y <= 0.0:
				continue
			RenderingServer.canvas_item_add_texture_rect_region(to_canvas_item, dst, rid, src, tint)
