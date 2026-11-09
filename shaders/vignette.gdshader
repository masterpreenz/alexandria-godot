shader_type canvas_item;
// Unity's Vignette (the scene's post-processing): the edges darkened a little, towards black.
uniform float intensity = 0.2;
uniform float smoothness = 0.2;

void fragment() {
	vec2 d = abs(UV - vec2(0.5)) * 2.0;
	d.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;   // round, not stretched with the screen
	d.x /= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float r = length(d) * 0.70710678;
	float v = smoothstep(1.0 - intensity - smoothness, 1.0 + smoothness, r) * intensity * 1.6;
	COLOR = vec4(0.0, 0.0, 0.0, clamp(v, 0.0, 1.0));
}
