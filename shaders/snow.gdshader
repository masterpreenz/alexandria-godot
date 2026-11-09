// Snow settling on the world (from Unity's SnowCommon.hlsl). snow_cover (a global, 0 to 1, set by SnowCover) is how
// much has fallen. mode 0: standing things get a cap of snow along every edge that faces up, deeper as it builds, and
// a light frost; 1: the ground whitens in patches that spread until it's all white; 2: roofs, a fine speckle filling
// in quickly to a white blanket.
shader_type canvas_item;

global uniform float snow_cover;
uniform int mode = 0;
uniform float unit = 128.0;

varying vec2 world;

const vec3 SNOW = vec3(0.92, 0.95, 1.0);

float hash(vec2 p) {
	uvec2 q = uvec2(ivec2(floor(p)) + ivec2(65536));
	q = q * uvec2(1597334673u, 3812015801u);
	uint n = (q.x ^ q.y) * 1597334673u;
	n ^= n >> 15u;
	return float(n) * (1.0 / 4294967295.0);
}

float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

float luma(vec3 c) { return dot(c, vec3(0.3, 0.59, 0.11)); }

void vertex() {
	// World position in Unity's units (y up), for patterns pinned to the world.
	vec2 w = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy / unit;
	world = vec2(w.x, -w.y);
}

void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	if (snow_cover > 0.001 && c.a > 0.01) {
		vec3 rgb = c.rgb;
		if (mode == 1) {
			// Ground: patches settling first where the noise is high, spreading until all is white.
			vec2 p = floor(world * 32.0) / 32.0;
			float patch = noise(p * 0.45) * 0.6 + noise(p * 1.9 + 7.1) * 0.3 + noise(p * 6.0 + 3.3) * 0.1;
			patch = clamp((patch - 0.28) / 0.44, 0.0, 1.0);
			float edge = 1.0 - snow_cover * 1.08;
			float covered = smoothstep(edge, edge + 0.03, patch);
			float shade = clamp(luma(rgb) / 0.55, 0.0, 1.0);
			vec3 snow = mix(vec3(0.74, 0.8, 0.92), SNOW, 0.55 + 0.45 * shade);
			rgb = mix(rgb, snow, covered);
		} else if (mode == 2) {
			// Roofs: a fine speckle filling in quickly to a white blanket, draped over the edges.
			vec2 p = floor(world * 32.0) / 32.0;
			float speckle = hash(p * 32.0) * 0.6 + noise(p * 3.0) * 0.4;
			float covered = smoothstep(1.0 - snow_cover * 2.6, 1.0 - snow_cover * 2.6 + 0.05, speckle);
			float drift = noise(world * 2.5) * 0.7 + noise(world * 7.0) * 0.3;
			vec3 snow = mix(vec3(0.78, 0.84, 0.95), SNOW, 0.35 + 0.65 * drift);
			snow *= mix(0.8, 1.0, smoothstep(0.1, 0.3, luma(rgb)));
			rgb = mix(rgb, snow, covered);
		} else if (c.a >= 0.5) {
			// Standing things: a cap along every edge that faces up (nothing of the sprite just above).
			float wy = dFdy(world.y);
			vec2 uv_per_up = abs(wy) > 1e-5 ? dFdy(UV) / wy : vec2(0.0);
			float depth = mix(0.03, 0.16, snow_cover) * (0.75 + 0.5 * noise(world * 9.0));
			float open = 0.0;
			for (int i = 1; i <= 4; i++) {
				open = max(open, 1.0 - texture(TEXTURE, UV + uv_per_up * depth * (float(i) / 4.0)).a);
			}
			float cap = step(0.5, open) * smoothstep(0.0, 0.25, snow_cover);
			// Snow also settles on the lit tops of things: the brightest pixels, more as it deepens.
			float l = luma(rgb);
			float lit = smoothstep(0.72 - 0.3 * snow_cover, 0.8 - 0.3 * snow_cover, l) * smoothstep(0.1, 0.5, snow_cover);
			float snowy = max(cap, lit * 0.85);
			vec3 frosted = mix(rgb, SNOW * (0.7 + 0.3 * l), snow_cover * 0.12);
			vec3 snow = mix(vec3(0.78, 0.84, 0.95), SNOW, clamp(l * 1.4, 0.0, 1.0));
			rgb = mix(frosted, snow, snowy * 0.93);
		}
		c.rgb = rgb;
	}
	COLOR = c;
}
