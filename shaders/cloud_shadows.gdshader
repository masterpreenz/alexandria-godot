// Cloud shadows (from Unity's SkyEffects): soft blobs of shadow pinned to the world and drifting with the wind, so they
// slide across the ground as you walk. Drawn over a rectangle covering the view.
shader_type canvas_item;

uniform float strength = 0.0;       // 0 none .. 1 full
uniform float darkness = 0.42;
uniform float cloud_scale = 14.0;   // world units a cloud pattern spans
uniform vec2 wind = vec2(0.35, 0.12); // world units a second (Unity's y up)
uniform float unit = 128.0;

varying vec2 world;

float hash(vec2 p) {
	uvec2 q = uvec2(ivec2(floor(p)) + ivec2(65536));
	q = q * uvec2(1597334673u, 3812015801u);
	uint n = (q.x ^ q.y) * 1597334673u;
	n ^= n >> 15u;
	return float(n) * (1.0 / 4294967295.0);
}

float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy / unit;
}

void fragment() {
	// In Unity's units (y up), the ground's y counting double so clouds lie flat.
	vec2 g = vec2(world.x, -world.y * 2.0) - wind * TIME;
	vec2 p = g / cloud_scale * 4.0;
	float v = noise(p) * 0.6 + noise(p * 2.1 + 7.3) * 0.3 + noise(p * 4.3 + 1.7) * 0.1;
	float a = smoothstep(0.52, 0.72, v);
	COLOR = vec4(0.05, 0.06, 0.12, darkness * strength * a);
}
