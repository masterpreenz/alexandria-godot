// Snow settling on the world (from Unity's SnowCommon.hlsl). snow_cover (a global, 0 to 1, set by SnowCover) is how
// much has fallen. mode 0: standing things get a cap of snow along every edge that faces up, deeper as it builds, and
// a light frost; 1: the ground whitens in patches that spread until it's all white; 2: roofs, a fine speckle filling
// in quickly to a white blanket; 3: the grass, as 1, and (grass_variety) varied across the world by a noise map:
// broad lusher and drier patches and a finer mottling, so the grass picture's repeat (every 8 x 16 cells) doesn't show.
shader_type canvas_item;

global uniform float snow_cover;
uniform int mode = 0;
uniform float unit = 128.0;
uniform sampler2D variety : filter_linear, repeat_enable;  // FastNoiseLite, seamless (World.grass_variety)
uniform float grass_variety = 0.0;                          // 0 plain .. 1 fully varied
// Trees (modes 4 and 5, 5 without snow of its own: the snowy art has it drawn): swaying from the root up, each in its
// own time, the top of a 4-unit tree [sway] units each way; a wind gust passing (gust_x, its front, px) leans them
// over as it goes. Only what's drawn is moved: trees off screen aren't drawn, so cost nothing.
uniform float sway = 0.0;
uniform float gust = 0.0;
uniform float gust_x = 0.0;
// Where no snow lies (SnowCover's map, a cell a pixel: inside houses, round burning fires): 0 snow as anywhere,
// 1 none. The ground reads it at each pixel; standing things by where they stand.
uniform sampler2D clear_map : filter_linear, repeat_disable;
uniform float clear_on = 0.0;
uniform vec2 clear_origin = vec2(0.0);   // the map's first cell
uniform float clear_size = 128.0;        // cells a side
uniform vec2 floor_origin = vec2(0.0);   // the floor grid's corner (0, 0), in units (y up)
// The corruption in the grass (mode 3): where the mist lies, the ground's tiles are the stained kind: the same grass
// with dark stains in it.
uniform sampler2D mist_map : filter_linear, repeat_disable;   // Mist's own picture (r: normal mist, g: strong)
uniform vec4 mist_rect = vec4(0.0, 0.0, 1.0, 1.0);             // the world it covers, px: x, y, w, h
uniform float stain_on = 0.0;
uniform float stain_pix = 40.0;         // texels to a world unit: the grid the stains are drawn on
uniform float stain_level = 0.6;        // how high the noise must be for a stain (lower: more of the grass stained)
uniform vec4 underground = vec4(0.0);    // cells where no snow ever lies (the cellar's room and round it): x, y, w, h

varying vec2 world;
varying float stands_clear;

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

// How clear of snow the ground is at w (units, y up): 0 to 1.
float cleared(vec2 w) {
	vec2 d = w - floor_origin;
	float u = d.x / 0.5;
	float v = d.y / 0.25;
	vec2 cell = vec2((u + v) * 0.5, (v - u) * 0.5);
	if (underground.z > 0.0 && cell.x >= underground.x && cell.y >= underground.y && cell.x < underground.x + underground.z && cell.y < underground.y + underground.w) return 1.0;
	if (clear_on < 0.5) return 0.0;
	vec2 uv = (cell - clear_origin) / clear_size;
	if (uv.x <= 0.0 || uv.y <= 0.0 || uv.x >= 1.0 || uv.y >= 1.0) return 0.0;
	return textureLod(clear_map, uv, 0.0).r;
}

void vertex() {
	if (sway > 0.0) {
		vec2 base = MODEL_MATRIX[3].xy;   // the tree's root (its sprite's origin)
		vec2 at = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
		float h = clamp((base.y - at.y) / unit, 0.0, 8.0);
		float ph = base.x * 0.011 + base.y * 0.017;
		float calm = sin(TIME * 1.3 + ph) * 0.55 + sin(TIME * 2.9 + ph * 1.9) * 0.2 + sin(TIME * 0.5 + ph * 0.7) * 0.35;
		float d = (base.x - gust_x) / (6.0 * unit);
		float blown = gust * exp(-d * d) * (2.2 + 0.6 * sin(TIME * 4.0 + ph));
		float off = (calm + blown) * sway * pow(h / 4.0, 1.6) * unit;
		VERTEX.x += off / max(0.001, length(MODEL_MATRIX[0].xy));
	}
	// World position in Unity's units (y up), for patterns pinned to the world.
	vec2 w = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy / unit;
	world = vec2(w.x, -w.y);
	// Standing things: by where they stand (their own origin).
	vec2 foot = MODEL_MATRIX[3].xy / unit;
	stands_clear = (mode == 1 || mode == 2 || mode == 3) ? 0.0 : smoothstep(0.3, 0.6, cleared(vec2(foot.x, -foot.y)));
}

void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	if (mode == 3 && grass_variety > 0.0) {
		// Broad patches (about 30 units across): lush and dark one way, sunned and drier the other; then a finer
		// mottle (about 7 units) a little lighter or darker.
		float broad = texture(variety, world / 34.0).r;
		float fine = texture(variety, world / 7.5 + vec2(0.37, 0.61)).r;
		vec3 lush = vec3(0.84, 0.92, 0.82);
		vec3 dry = vec3(1.1, 1.05, 0.8);
		vec3 tint = mix(lush, dry, smoothstep(0.25, 0.75, broad));
		tint *= 0.94 + 0.12 * fine;
		c.rgb = mix(c.rgb, c.rgb * tint, grass_variety);
	}
	if (mode == 3 && stain_on > 0.0) {
		// The stained grass: this tile's own grass (its blades and shading kept), gone dark and violet in blotches
		// with a darker heart, a few loose specks round them. Worked out on a grid of texels pinned to the world, so
		// the stains run on from tile to tile and sit still. More of them in the strong mist. Where the mist is
		// being driven off (its thinning edge, round a crystal) they shrink and pale, and the clean grass is back.
		vec2 here = vec2(world.x, -world.y);   // (the screen's way up, units)
		vec4 mt = texture(mist_map, (here * unit - mist_rect.xy) / mist_rect.zw);
		float mist_here = clamp(mt.r + mt.g, 0.0, 1.0);
		if (mist_here > 0.02) {
			vec2 texel_at = floor(here * stain_pix);
			vec2 wp = (texel_at + 0.5) / stain_pix;
			vec2 g = vec2(wp.x, wp.y * 2.0);
			float n = textureLod(variety, g / 5.5 + vec2(0.4, 0.13), 0.0).r * 0.62 + textureLod(variety, g.yx / 17.0 + vec2(0.21, 0.7), 0.0).r * 0.38;
			float grain = fract(sin(dot(texel_at, vec2(12.9898, 78.233))) * 43758.5453);
			float level = mix(1.2, stain_level, smoothstep(0.08, 0.7, mist_here)) - mt.g * 0.05;
			float blot = step(level, n + (grain - 0.5) * 0.03);
			float heart = step(level + 0.06, n);
			float speck = step(0.95, grain) * step(level - 0.05, n);
			float edge = smoothstep(0.02, 0.3, mist_here) * (1.0 - smoothstep(0.3, 0.75, mist_here));
			vec3 stained = c.rgb * vec3(0.5, 0.36, 0.58) + vec3(0.03, 0.0, 0.05);
			vec3 deep = c.rgb * vec3(0.27, 0.19, 0.34) + vec3(0.02, 0.0, 0.04);
			vec3 pale = c.rgb * vec3(0.85, 0.82, 0.95) + vec3(0.08);
			vec3 rgb = mix(c.rgb, mix(stained, pale, edge * 0.7), max(blot, speck));
			c.rgb = mix(rgb, mix(deep, pale, edge * 0.7), heart);
		}
	}
	if (snow_cover > 0.001 && c.a > 0.01) {
		vec3 rgb = c.rgb;
		if (mode == 1 || mode == 3) {
			// Ground: patches settling first where the noise is high, spreading until all is white.
			vec2 p = floor(world * 32.0) / 32.0;
			float patch = noise(p * 0.45) * 0.6 + noise(p * 1.9 + 7.1) * 0.3 + noise(p * 6.0 + 3.3) * 0.1;
			patch = clamp((patch - 0.28) / 0.44, 0.0, 1.0);
			float edge = 1.0 - snow_cover * 1.08;
			float covered = smoothstep(edge, edge + 0.03, patch);
			// None indoors or by a burning fire: melted back to a ragged edge.
			float bare = cleared(world) + (noise(p * 5.0 + 11.0) - 0.5) * 0.22;
			covered *= 1.0 - smoothstep(0.38, 0.52, bare);
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
		} else if (c.a >= 0.5 && mode != 5 && stands_clear < 0.99) {
			// Standing things: a cap along every edge that faces up (nothing of the sprite just above).
			float snow_here = snow_cover * (1.0 - stands_clear);
			float wy = dFdy(world.y);
			vec2 uv_per_up = abs(wy) > 1e-5 ? dFdy(UV) / wy : vec2(0.0);
			float depth = mix(0.03, 0.16, snow_here) * (0.75 + 0.5 * noise(world * 9.0));
			float open = 0.0;
			for (int i = 1; i <= 4; i++) {
				open = max(open, 1.0 - texture(TEXTURE, UV + uv_per_up * depth * (float(i) / 4.0)).a);
			}
			float cap = step(0.5, open) * smoothstep(0.0, 0.25, snow_here);
			// Snow also settles on the lit tops of things: the brightest pixels, more as it deepens.
			float l = luma(rgb);
			float lit = smoothstep(0.72 - 0.3 * snow_here, 0.8 - 0.3 * snow_here, l) * smoothstep(0.1, 0.5, snow_here);
			float snowy = max(cap, lit * 0.85);
			vec3 frosted = mix(rgb, SNOW * (0.7 + 0.3 * l), snow_here * 0.12);
			vec3 snow = mix(vec3(0.78, 0.84, 0.95), SNOW, clamp(l * 1.4, 0.0, 1.0));
			rgb = mix(frosted, snow, snowy * 0.93);
		}
		c.rgb = rgb;
	}
	COLOR = c;
}
