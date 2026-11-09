// A character's outline, for when something stands in front of them (from Unity's Custom/Sprite Outline): a soft rim
// traced along the inside of the sprite's edge plus a faint fill of its shape, unlit, drawn over everything. The
// node's modulate alpha fades it in and out.
shader_type canvas_item;
render_mode unshaded;

uniform vec4 outline_color : source_color = vec4(1.0, 0.96, 0.88, 1.0);
uniform vec4 fill_color : source_color = vec4(1.0, 0.96, 0.88, 0.22);
uniform float width = 2.5; // in texels

float alpha_at(sampler2D tex, vec2 uv) { return texture(tex, uv).a; }

void fragment() {
	vec2 d = TEXTURE_PIXEL_SIZE * width;
	float centre = alpha_at(TEXTURE, UV);
	// The rim: texels of the sprite with empty space close by.
	float emptiest = 1.0;
	emptiest = min(emptiest, alpha_at(TEXTURE, UV + vec2(d.x, 0.0)));
	emptiest = min(emptiest, alpha_at(TEXTURE, UV - vec2(d.x, 0.0)));
	emptiest = min(emptiest, alpha_at(TEXTURE, UV + vec2(0.0, d.y)));
	emptiest = min(emptiest, alpha_at(TEXTURE, UV - vec2(0.0, d.y)));
	emptiest = min(emptiest, alpha_at(TEXTURE, UV + d * 0.7071));
	emptiest = min(emptiest, alpha_at(TEXTURE, UV - d * 0.7071));
	emptiest = min(emptiest, alpha_at(TEXTURE, UV + vec2(d.x, -d.y) * 0.7071));
	emptiest = min(emptiest, alpha_at(TEXTURE, UV + vec2(-d.x, d.y) * 0.7071));
	float edge = clamp(centre - emptiest, 0.0, 1.0);
	vec4 c = fill_color * centre;
	c = mix(c, outline_color, edge);
	c.a = max(fill_color.a * centre, outline_color.a * edge);
	COLOR = vec4(c.rgb, c.a * COLOR.a);
}
