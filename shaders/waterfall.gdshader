// The falls (from Unity's Custom/Waterfall, smoothed): the river's own deep water where it tips over the lip, falling
// in streaks that run fast down the face (faster as they drop), pale where the water is thin, churning white at the
// foot, the sides fading into the deep water beside them. Spray and mist come from particles at its foot.
//
// UV: x is 0..1 across the falls, y is 0 at the lip to 1 at the foot.
shader_type canvas_item;

uniform vec4 deep : source_color = vec4(0.15, 0.39, 0.48, 1.0);
uniform vec4 water : source_color = vec4(0.28, 0.55, 0.58, 1.0);
uniform vec4 pale : source_color = vec4(0.42, 0.70, 0.67, 1.0);
uniform vec4 foam : source_color = vec4(0.88, 0.93, 0.88, 1.0);
uniform float edge_fade = 0.14;
uniform float speed = 2.4;

// A random value for the lattice point at (or under) p: an integer hash, exact anywhere on the map.
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

void fragment() {
	float t = TIME;
	float across = UV.x, down = UV.y;
	float fall = down * (1.0 + down * 0.8);
	float flow_n = noise(vec2(across * 18.0, fall * 3.0 - t * speed));
	float streak = noise(vec2(across * 42.0 + 3.0, fall * 6.0 - t * speed * 1.6));
	vec3 color = mix(water.rgb, pale.rgb, smoothstep(0.45, 0.65, flow_n));
	color = mix(color, foam.rgb, smoothstep(0.72, 0.9, streak) * 0.8);
	// The lip: the river's deep water where it tips over, easing into the falls.
	color = mix(color, deep.rgb, 1.0 - smoothstep(0.0, 0.22, down));
	// The foot: churning foam, ragged at its top.
	float churn = noise(vec2(across * 10.0 + t * 1.3, t * 2.0));
	float foot = smoothstep(0.74 + (churn - 0.5) * 0.12, 0.84 + (churn - 0.5) * 0.12, down);
	color = mix(color, foam.rgb, foot * (0.8 + 0.2 * noise(vec2(across * 30.0, t * 8.0))));
	// The sides fade into the deep water beside them.
	float side = min(across, 1.0 - across);
	color = mix(deep.rgb, color, smoothstep(0.0, edge_fade, side));
	COLOR = vec4(color, COLOR.a * step(0.005, side));
}
