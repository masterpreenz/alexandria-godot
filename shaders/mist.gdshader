// The purple mist (from Unity's Custom/Mist; see scripts/mist.gd): a rectangle over the whole world. `mist` says how
// thick it is where (r: normal mist, g: strong, b: how near a tree or rock is). Two layers of a seamless wisp texture
// drift past each other at different sizes and angles, so the smoke curls and never reads as one picture scrolling;
// under them the ground is darkened and tinted violet, as if the mist has soaked into it. Strong mist is darker and
// thicker. `part` 1 draws only the darkened ground (under everything standing), 2 only the drifting smoke (over
// everything). Lit by the world (CanvasModulate), like everything else.
shader_type canvas_item;

uniform sampler2D mist : filter_linear, repeat_disable;
uniform sampler2D wisps : filter_linear_mipmap, repeat_enable;
uniform vec2 texel = vec2(0.002, 0.004);
uniform vec3 color : source_color = vec3(0.66, 0.38, 0.9);
uniform vec3 deep : source_color = vec3(0.5, 0.24, 0.78);
uniform vec3 ground : source_color = vec3(0.3, 0.12, 0.4);
uniform float ground_amount = 0.55;
uniform float normal_amount = 0.75;
uniform float strong_amount = 1.0;
uniform float scale = 9.0;              // world units a wisp tile covers
uniform vec2 drift_a = vec2(0.35, 0.08); // world units a second (Unity's y up)
uniform vec2 drift_b = vec2(-0.2, 0.14);
uniform float swirl = 1.6;              // how far it curls round trees and rocks
uniform int part = 1;
uniform float unit = 128.0;             // px a world unit

varying vec2 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy / unit;
}

void fragment() {
	vec3 mt = texture(mist, UV).rgb;
	float near = mt.b;
	float amount = mt.r * normal_amount + mt.g * (strong_amount - normal_amount);
	if (amount <= 0.001) {
		discard;
	}
	vec3 tint = mix(color, deep, clamp(mt.g, 0.0, 1.0));
	float g_amount = ground_amount * (0.7 + 0.3 * clamp(mt.g + mt.r, 0.0, 1.0));
	if (part == 1) {
		// The darkened, violet ground alone (drawn under everything standing on it).
		COLOR = vec4(ground, g_amount * amount);
	} else {
		// Ground-plane coordinates in Unity's units (y up), the screen's y counting double, so the wisps lie flat.
		vec2 g = vec2(world.x, -world.y * 2.0);
		// Flowing round trees and rocks: pushed along the way round each one (across the slope of how near it is).
		float nx = texture(mist, UV + vec2(texel.x, 0.0)).b - texture(mist, UV - vec2(texel.x, 0.0)).b;
		float ny = texture(mist, UV - vec2(0.0, texel.y)).b - texture(mist, UV + vec2(0.0, texel.y)).b;
		vec2 slope = vec2(nx, ny * 0.5);
		g += vec2(-slope.y, slope.x) * swirl * 4.0 + slope * swirl * 2.0;
		float t = TIME;
		vec2 uv_a = (g - drift_a * t) / scale;
		// The second layer: bigger, turned a little, drifting the other way.
		vec2 r = vec2(g.x * 0.94 - g.y * 0.34, g.x * 0.34 + g.y * 0.94);
		vec2 uv_b = (r - drift_b * t) / (scale * 1.55) + 0.37;
		float a = texture(wisps, uv_a).a;
		float b = texture(wisps, uv_b).a;
		// Where both are thick the smoke billows; either alone leaves a thinner trail.
		float wisp = clamp(a * b * 1.8 + (a + b) * 0.28, 0.0, 1.0);
		wisp = clamp(wisp * (1.0 + mt.g * 0.5), 0.0, 1.0);
		vec3 col = tint;
		// Brighter where the smoke is thickest.
		col = mix(col, mix(tint, vec3(0.95, 0.88, 1.0), 0.4), clamp((wisp - 0.55) * 2.5, 0.0, 1.0));
		// Right against a trunk or stone the smoke is thin; a little way out it piles up in a pale rim.
		float rim = clamp(near * 2.0, 0.0, 1.0) * clamp((1.0 - near) * 2.5, 0.0, 1.0);
		wisp = clamp(wisp * (1.0 - near * 0.85) + rim * 0.35 * clamp(wisp * 3.0, 0.0, 1.0), 0.0, 1.0);
		col = mix(col, mix(tint, vec3(0.95, 0.88, 1.0), 0.45), rim * 0.5 * clamp(wisp * 2.0, 0.0, 1.0));
		COLOR = vec4(col, wisp * 0.85 * amount);
	}
}
