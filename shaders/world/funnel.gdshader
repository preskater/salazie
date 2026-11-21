shader_type canvas_item;
render_mode blend_add, unshaded;

// Texture de bruit (NoiseTexture2D, "seamless" coché)
uniform sampler2D noise_tex : repeat_enable;

uniform float speed : hint_range(0.0, 3.0) = 0.45;
uniform float twist : hint_range(0.0, 20.0) = 7.0;
uniform float base_width : hint_range(0.02, 0.5) = 0.14;
uniform float top_width : hint_range(0.1, 0.7) = 0.42;
uniform float noise_scale = 2.5;
uniform vec4 tint : source_color = vec4(0.72, 0.8, 0.95, 1.0);
uniform float intensity : hint_range(0.0, 2.0) = 1.0;

mat2 rot(float a) {
	float s = sin(a);
	float c = cos(a);
	return mat2(vec2(c, -s), vec2(s, c));
}

void fragment() {
	vec2 uv = UV;
	float h = 1.0 - uv.y;                                 // 0 = pied, 1 = sommet

	// largeur de l'entonnoir a la hauteur h
	float width = mix(base_width, top_width, h);

	// masque en forme de cone
	float d = abs(uv.x - 0.5);
	float shape = 1.0 - smoothstep(width * 0.7, width, d);

	// ne touche pas le sol, s'efface au sommet
	float fade = smoothstep(0.0, 0.12, h) * (1.0 - smoothstep(0.7, 1.0, h));

	// vrille : on tourne l'echantillonnage du bruit selon la hauteur + le temps
	vec2 p = uv - vec2(0.5);
	vec2 q = rot(h * twist + TIME * speed) * p;

	vec2 nuv = vec2(q.x * noise_scale, q.y * noise_scale - TIME * speed * 2.0);
	float n = texture(noise_tex, nuv).r;

	// tranches horizontales qui montent
	float bands = 0.5 + 0.5 * sin(uv.y * 14.0 - TIME * 3.0 + n * 6.0);

	float a = shape * fade * (0.3 + 0.7 * n) * (0.55 + 0.45 * bands) * intensity;
	COLOR = vec4(tint.rgb, a);
}
