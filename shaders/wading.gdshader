// A character standing in water (from Unity's Wading, which masked the body): everything of them below the waterline
// (the ground level at their feet) is cut away, so the water shows instead.
shader_type canvas_item;

uniform float waterline = 1e9;  // world y (canvas px) below which nothing of the body draws

varying float world_y;

void vertex() {
	world_y = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).y;
}

void fragment() {
	if (world_y > waterline) {
		discard;
	}
}
