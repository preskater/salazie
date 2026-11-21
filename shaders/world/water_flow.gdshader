shader_type canvas_item;
render_mode blend_mix;

// Gentle moving highlights over the Map 1 water TileMapLayer. The tiles stay
// static; only the light crests move, which keeps the river readable.

uniform vec4 highlight : source_color = vec4(0.78, 0.94, 1.0, 1.0);
uniform float speed = 0.9;
uniform float scale = 0.055;
uniform float strength = 0.42;

varying vec2 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	float time = TIME * speed;
	float wave_a = sin((world_position.x + world_position.y) * scale + time * 2.0);
	float wave_b = sin((world_position.x - world_position.y * 1.3) * scale * 1.7 - time * 1.3);
	float wave_c = sin((world_position.x * 0.6 + world_position.y * 1.8) * scale * 2.3 + time * 0.7);
	float crest = smoothstep(0.35, 1.0, wave_a * 0.4 + wave_b * 0.4 + wave_c * 0.2);
	COLOR = vec4(mix(base.rgb, highlight.rgb, crest * strength), base.a);
}
