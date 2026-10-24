shader_type canvas_item;

uniform vec4 flash_color : source_color = vec4(1.0, 0.3, 0.3, 1.0);
uniform float intensity : hint_range(0.0, 0.4) = 0.0;

void fragment() {
	float edge_distance = max(abs(UV.x - 0.5), abs(UV.y - 0.5)) * 2.0;
	float edge_mask = smoothstep(0.35, 1.0, edge_distance);
	COLOR = vec4(flash_color.rgb, flash_color.a * intensity * edge_mask);
}
