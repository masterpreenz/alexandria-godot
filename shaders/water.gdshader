// Godot water for the river, the lake and the ponds (replacing Unity's pixel-art Custom/River). Smooth, not pixel
// snapped: deep in the middle easing to shallow at the banks, slow ripples drifting with the current (along the river,
// barely moving on still ponds), soft glints where the ripples catch the light, a net of caustics in the shallows,
// foam lapping at the banks, and the odd sparkle.
//
// UV: x is cells along the river (0 on a pond), y is 0..1 across it (a pond: 0.5 in the middle, 1 at the shore).
shader_type canvas_item;
#include "res://shaders/map_still.gdshaderinc"

uniform vec4 deep : source_color = vec4(0.15, 0.39, 0.48, 1.0);
uniform vec4 shallow : source_color = vec4(0.42, 0.70, 0.67, 1.0);
uniform vec4 foam : source_color = vec4(0.88, 0.93, 0.88, 1.0);
uniform float flow = 0.7;          // cells a second along the river
uniform float ripple_scale = 1.4;
uniform float foam_width = 0.14;   // share of the way in from the bank
uniform float cell_px = 128.0;     // a cell's width in px, for world-space patterns

varying vec2 world;
varying vec3 flow_dir;  // which way the water runs here (rg, unpacked), and b: whether it runs at all

// A random value for the lattice point at (or under) p: an integer hash, exact anywhere on the map (a float one broke
// into squares far from the origin).
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

float fbm(vec2 p) {
	float v = 0.0, a = 0.5;
	for (int k = 0; k < 4; k++) { v += a * noise(p); p *= 2.03; a *= 0.5; }
	return v;
}

// A web of bright lines, as light focused by the ripples falls on the bed (cellular, animated).
float caustics(vec2 p, float t) {
	vec2 i = floor(p), f = fract(p);
	float d1 = 8.0, d2 = 8.0;
	for (int y = -1; y <= 1; y++)
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = vec2(hash(i + g), hash(i + g + vec2(17.0, 31.0)));
			o = 0.5 + 0.45 * sin(t * 0.9 + 6.2831 * o);
			float d = length(g + o - f);
			if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
		}
	return 1.0 - smoothstep(0.0, 0.3, d2 - d1);
}

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy / cell_px;
	flow_dir = vec3(COLOR.rg * 2.0 - 1.0, COLOR.b);
	COLOR = vec4(1.0);
}

// The water's look at one moment of the flow: depth, glints, caustics and its ripples' values (for the foam).
vec4 surface(vec2 at, vec2 offset, float t) {
	float n1 = fbm((at * 0.6 + offset) * ripple_scale);
	float n2 = fbm((at * 1.2 + offset * 1.6 + vec2(3.1, 7.7)) * ripple_scale);
	return vec4(n1, n2, 0.0, 0.0);
}

void fragment() {
	float t = anim_time(SCREEN_PIXEL_SIZE);
	float edge = clamp(abs(UV.y - 0.5) * 2.0, 0.0, 1.0);  // 0 in the middle, 1 at a bank
	vec2 at = world * vec2(1.0, 2.0);  // patterns laid in the world (the iso ground is half as tall on screen)
	// Drifting downstream, as a flow map: two layers carried along and faded in turn, each starting over while it's
	// invisible, so the carrying never builds up (and turning water bends its ripples without tearing them). Still
	// water barely drifts.
	vec2 dir = flow_dir.z > 0.5 && flow > 0.3 ? normalize(flow_dir.xy + 1e-5) : vec2(0.8, 0.6);
	float speed = flow > 0.3 ? flow : 0.06;
	float period = 3.0;
	float p0 = fract(t / period), p1 = fract(t / period + 0.5);
	float w0 = 1.0 - abs(p0 - 0.5) * 2.0;
	vec4 s0 = surface(at, -dir * p0 * period * speed + vec2(0.0, 0.0), t);
	vec4 s1 = surface(at, -dir * p1 * period * speed + vec2(5.2, 1.3), t);
	float n1 = mix(s1.x, s0.x, w0);
	float n2 = mix(s1.y, s0.y, w0);
	// Keep the contrast the blend would wash out.
	n1 = (n1 - 0.5) * 1.3 + 0.5;
	n2 = (n2 - 0.5) * 1.3 + 0.5;

	// Depth: deep to shallow towards the banks, swayed by slow, soft ripples.
	float shallowness = smoothstep(0.1, 1.0, edge) + (n1 - 0.5) * 0.35;
	vec3 color = mix(deep.rgb, shallow.rgb, clamp(shallowness, 0.0, 1.0));

	// Glints: where the ripples face the light, soft streaks drifting with the water.
	float glint = smoothstep(0.62, 0.78, n2) * (0.35 + 0.65 * n1);
	color = mix(color, min(vec3(1.0), shallow.rgb * 1.25 + 0.12), glint * 0.4);

	// Caustics on the bed, faint, showing through only where it is shallow.
	float c = caustics(at * 1.3, t);
	color += vec3(0.85, 1.0, 0.95) * c * c * 0.05 * smoothstep(0.7, 0.97, edge) * (0.4 + n1);

	// Foam lapping at the banks: a thin band that breathes in and out, broken up, a darker line just inside it.
	float lap = 0.025 * sin(t * 1.6 + dot(at, vec2(2.0, 1.3)));
	float foam_at = 1.0 - foam_width * 0.6 - lap - 0.05 * (n2 - 0.5) * 2.0;
	float band = smoothstep(foam_at - 0.012, foam_at + 0.012, edge);
	float breakup = smoothstep(0.35, 0.6, noise(at * 3.0 + t * 0.3));
	color *= 1.0 - 0.1 * smoothstep(foam_at - 0.06, foam_at - 0.015, edge) * (1.0 - band);
	color = mix(color, foam.rgb, band * mix(0.5, 0.9, breakup));

	// The odd sparkle, winking on and off on the brightest ripples.
	float spark = step(0.993, hash(floor(world * 40.0) + floor(t * 4.0) * 13.0)) * smoothstep(0.55, 0.7, n2);
	color = mix(color, vec3(1.0), spark * 0.85);

	COLOR = vec4(color, 1.0);
}
