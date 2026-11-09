// A cleansing crystal's curtain (Crystals): a band round its clearing's edge, from the ground up, its brightness
// rippling round and its height wavering. The mesh holds the band at rest (both rows on the ground; UV.x the angle
// round, UV.y 0 at the ground and 1 at the top; the ground row's alpha how much shows there); the movement is here,
// so the mesh is only rebuilt when the curtain itself changes.
shader_type canvas_item;
#include "res://shaders/map_still.gdshaderinc"

uniform float base = 0.22;      // its brightness at rest (the back half a little brighter than the front)
uniform float height = 140.8;   // px, the band's height
uniform float phase = 0.0;      // seconds, so no two crystals ripple together

varying float angle;

void vertex() {
	angle = UV.x;
	// (The height's slow sway runs on the game's clock even on the maps: a few pixels there.)
	VERTEX.y -= UV.y * height * (0.8 + 0.2 * sin(UV.x * 3.0 + (TIME + phase) * 0.9));
}

void fragment() {
	float t = anim_time(SCREEN_PIXEL_SIZE) + phase;
	COLOR.a *= base + 0.12 * (0.5 + 0.5 * sin(angle * 6.0 - t * 1.4));
}
