shader_type canvas_item;

uniform float intensity : hint_range(0.0, 0.08) = 0.018;
uniform float scanline_density : hint_range(100.0, 1200.0) = 720.0;
uniform float vignette_strength : hint_range(0.0, 0.04) = 0.012;

void fragment() {
	float scanline = step(0.88, fract(UV.y * scanline_density));
	float distance_from_center = length((UV - vec2(0.5)) * 2.0);
	float vignette = smoothstep(0.45, 1.35, distance_from_center);
	float alpha = intensity * scanline + vignette_strength * vignette;
	COLOR = vec4(0.0, 0.02, 0.025, alpha);
}
