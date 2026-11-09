// The earth wall on a far shore, under the ground's edge and down to the water (from Unity's Custom/Cliff, smoothed):
// grass hanging over the lip, the stone (a seamless tile at its real size), darker towards the water, a wet band above
// the waterline, and the waterline itself, rippling gently.
//
// UV: x is cells along the bank, y is 0 at the top to 1 at the water. COLOR.r is the wall's height / 4 (world units).
shader_type canvas_item;

uniform sampler2D stone : source_color, filter_linear_mipmap, repeat_enable;
uniform float tile_size = 1.6;     // world units a stone tile covers
uniform float cell_length = 0.559; // world units along a cell's edge
uniform vec4 grass : source_color = vec4(0.36, 0.52, 0.25, 1.0);
uniform vec4 grass_light : source_color = vec4(0.41, 0.6, 0.27, 1.0);
uniform vec4 wet : source_color = vec4(0.16, 0.18, 0.19, 1.0);
uniform vec4 waterline : source_color = vec4(0.42, 0.55, 0.55, 1.0);

// A random value for the lattice point at (or under) p: an integer hash, exact anywhere on the map.
float hash(vec2 p) {
	uvec2 q = uvec2(ivec2(floor(p)) + ivec2(65536));
	q = q * uvec2(1597334673u, 3812015801u);
	uint n = (q.x ^ q.y) * 1597334673u;
	n ^= n >> 15u;
	return float(n) * (1.0 / 4294967295.0);
}

float noise1(float x) {
	float i = floor(x), f = fract(x);
	return mix(hash(vec2(i, 3.0)), hash(vec2(i + 1.0, 3.0)), f * f * (3.0 - 2.0 * f));
}

void fragment() {
	float height = max(COLOR.r * 4.0, 0.01);
	float along = UV.x * cell_length;   // world units along the bank
	float depth = UV.y * height;        // world units below the top
	float wander = noise1(along * 0.31 + 4.0) * 0.6 + noise1(along * 0.87 + 19.0) * 0.4;
	float grass_end = 0.06 + 0.04 * noise1(along * 2.9 + 2.0) + step(0.62, hash(vec2(floor(along * 7.0), 5.0))) * 0.05;
	vec3 color;
	if (depth < grass_end) {
		// Grass over the lip: blades of two tones.
		float blade = hash(vec2(floor(along * 60.0), floor(depth * 30.0)));
		color = blade > 0.55 ? grass_light.rgb : grass.rgb;
	} else {
		vec2 st = vec2(along, depth) / tile_size;
		color = texture(stone, st).rgb;
		color *= 0.92 + 0.16 * wander;
		// Shade just under the turf.
		color *= mix(1.0, 0.72, 1.0 - smoothstep(grass_end, grass_end + 0.1, depth));
		color *= mix(1.0, 0.72, UV.y);
	}
	// The wet band just above the water, and the waterline, lifting and falling a little.
	float swell = 0.012 * sin(TIME * 1.4 + along * 3.0);
	float wet_from = height - (0.06 + 0.06 * noise1(along * 1.3 + 31.0)) + swell;
	color = mix(color, wet.rgb, smoothstep(wet_from - 0.02, wet_from + 0.02, depth) * 0.65);
	float line = smoothstep(height - 0.05 + swell, height - 0.025 + swell, depth);
	color = mix(color, waterline.rgb, line * (0.6 + 0.4 * noise1(along * 4.0 - TIME * 0.6)));
	COLOR = vec4(color, 1.0);
}
