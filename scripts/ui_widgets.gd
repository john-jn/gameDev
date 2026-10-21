class_name UiWidgets
extends RefCounted
## Small hardware-style widgets for the control-unit skin: screws, status LEDs
## and LCD readouts. They only draw; the game controller sets their state.


## A slotted casing screw.
class Screw extends Control:
	var angle := 0.0

	func _init(p_angle: float = 0.0) -> void:
		angle = p_angle
		custom_minimum_size = Vector2(14, 14)
		size = custom_minimum_size
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		draw_circle(c, r, Color("1b222e"))
		draw_circle(c, r - 1.5, Color("6b7788"))
		draw_circle(c - Vector2(1, 1), r - 3.5, Color("8794a6"))
		var d := Vector2.from_angle(angle) * (r - 2.5)
		draw_line(c - d, c + d, Color("2a3240"), 1.8)


## A round indicator light. Unlit it shows a dark lens; lit it glows.
class Led extends Control:
	var color := Color("39d98a"):
		set(v):
			if v != color:
				color = v
				queue_redraw()
	var lit := false:
		set(v):
			if v != lit:
				lit = v
				queue_redraw()

	func _init(diameter: float = 16.0) -> void:
		custom_minimum_size = Vector2(diameter, diameter)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_state(p_color: Color, p_lit: bool) -> void:
		color = p_color
		lit = p_lit

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		draw_circle(c, r, Color("0b0f16"))
		if lit:
			draw_circle(c, r + 2.0, Color(color, 0.18))
			draw_circle(c, r - 1.5, color)
			draw_circle(c - Vector2(r * 0.25, r * 0.25), r * 0.3, Color(1, 1, 1, 0.55))
		else:
			draw_circle(c, r - 1.5, color.darkened(0.8))


## A dark LCD readout (a Label, so `text` and font colour work as usual).
class Lcd extends Label:
	func _init(p_text: String = "", font_size: int = 20, p_color: Color = Color("ff4d3d")) -> void:
		text = p_text
		var font := SystemFont.new()
		font.font_names = PackedStringArray(["Consolas", "Courier New", "monospace"])
		font.font_weight = 700
		add_theme_font_override("font", font)
		add_theme_font_size_override("font_size", font_size)
		add_theme_color_override("font_color", p_color)
		horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("060a0e")
		sb.border_color = Color("3a4658")
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(3)
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		sb.content_margin_top = 3
		sb.content_margin_bottom = 3
		add_theme_stylebox_override("normal", sb)
