// The world's lights, in one pass over the screen (LightMap): each pixel takes the brightest light reaching it, not
// their sum, so torches standing close never light more than one does. The screen comes in already dimmed by the
// day's tint (Daylight); a light gives back what it would have added: base * (tint + light), as one Light2D would.
shader_type canvas_item;

const int MOST = 48;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform sampler2D glow : filter_linear;         // the lights' falloff (Fires._glow): bright middle to dark edge
uniform sampler2D unlit_mask : filter_linear;   // what's shown as drawn (bubbles, numbers, outlines): left as it is
uniform vec3 tint = vec3(1.0);               // the day's light (Daylight's colour)
uniform vec2 screen_px = vec2(1600.0, 900.0);
uniform int count = 0;
uniform vec4 lights[MOST];                   // x, y (px on screen), radius (px), unused
uniform vec3 colours[MOST];                  // colour times energy

void fragment() {
	vec2 at = SCREEN_UV * screen_px;
	vec3 best = vec3(0.0);
	for (int i = 0; i < MOST; i++) {
		if (i >= count) {
			break;
		}
		vec4 l = lights[i];
		float d = length(at - l.xy) / max(l.z, 1.0);
		if (d >= 1.0) {
			continue;
		}
		float g = texture(glow, vec2(0.5 + 0.5 * d, 0.5)).r;
		best = max(best, colours[i] * g);
	}
	vec4 s = texture(screen_tex, SCREEN_UV);
	vec3 t = max(tint, vec3(0.02));
	float keep = texture(unlit_mask, SCREEN_UV).a;
	COLOR = vec4(s.rgb * mix(1.0 + best / t, vec3(1.0), keep), 1.0);
}
