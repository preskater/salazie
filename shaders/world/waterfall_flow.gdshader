shader_type canvas_item;
render_mode blend_mix;

// Scrolling cascade used by the Map 1 waterfall sprite. The custom waterfall
// texture is a 3 x 9 tile column; adding a second offset sample hides the loop.

uniform float speed = 0.38;
uniform float opacity = 0.92;
uniform vec4 tint : source_color = vec4(0.78, 0.95, 1.0, 1.0);
uniform float tint_strength = 0.18;

void fragment() {
	vec2 uv_a = vec2(UV.x, fract(UV.y + TIME * speed));
	vec2 uv_b = vec2(UV.x, fract(UV.y + TIME * speed + 0.5));
	float blend = abs(UV.y * 2.0 - 1.0);
	vec4 base = mix(texture(TEXTURE, uv_a), texture(TEXTURE, uv_b), blend * 0.35);
	vec3 color = mix(base.rgb, tint.rgb, tint_strength);
	COLOR = vec4(color, base.a * opacity);
}
