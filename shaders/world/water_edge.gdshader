shader_type canvas_item;
render_mode blend_mix;

// Sea-water edge tiles contain a full water cell plus a sand/foam rim. The
// water body is already drawn by the Water tile map, so keep only the rim and
// let the two overlays of a corner stack without hiding each other.
void fragment() {
	vec4 source = texture(TEXTURE, UV);
	float sand = smoothstep(0.04, 0.14, source.r - source.b);
	float foam = smoothstep(0.72, 0.84, min(source.g, source.b))
			* (1.0 - smoothstep(0.18, 0.34, abs(source.r - source.g)));
	float keep = max(sand, foam);
	COLOR = vec4(source.rgb, source.a * keep);
}
