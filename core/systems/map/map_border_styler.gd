class_name MapBorderStyler
extends RefCounted

##
## MapBorderStyler: Настройка шейдерных стилей и иерархии границ CRT-терминала
## ==============================================================================
## Отвечает за:
## 1. Синхронизацию параметров границ (национальные, штатные, провинциальные, береговые линии, реки).
## 2. Настройку неонового свечения (Inner Border Glow), пунктиров и режимов ленты границ.
## 3. Адаптацию шейдерных пульсаций границ к уровню международной напряженности DEFCON.
## ==============================================================================


"""Синхронизирует все униформы границ с шейдерным материалом.
"""
static func sync_border_uniforms(mat: ShaderMaterial, c: MapController) -> void:
	if mat == null:
		return
	mat.set_shader_parameter("zoom_level", c.current_zoom)
	mat.set_shader_parameter("show_national_borders", c.show_national_borders)
	mat.set_shader_parameter("show_state_borders", c.show_state_borders)
	mat.set_shader_parameter("show_province_borders", c.show_province_borders)
	mat.set_shader_parameter("show_coastlines", c.show_coastlines)
	mat.set_shader_parameter("national_border_width", c.national_border_width)
	mat.set_shader_parameter("state_border_width", c.state_border_width)
	mat.set_shader_parameter("province_border_width", c.province_border_width)
	mat.set_shader_parameter("coastline_width", c.coastline_width)
	mat.set_shader_parameter("national_border_color", c.national_border_color)
	mat.set_shader_parameter("state_border_color", c.state_border_color)
	mat.set_shader_parameter("province_border_color", c.province_border_color)
	mat.set_shader_parameter("coastline_color", c.coastline_color)
	mat.set_shader_parameter("frontline_border_color", c.frontline_border_color)
	mat.set_shader_parameter("river_color", c.river_color)
	mat.set_shader_parameter("border_color_mode", c.border_color_mode)
	mat.set_shader_parameter("enable_inner_border_glow", c.enable_inner_border_glow)
	mat.set_shader_parameter("inner_border_glow_width", c.inner_border_glow_width)
	mat.set_shader_parameter("inner_border_glow_intensity", c.inner_border_glow_intensity)
	mat.set_shader_parameter("inner_border_glow_tint", c.inner_border_glow_tint)
	mat.set_shader_parameter("enable_dashed_state_borders", c.enable_dashed_state_borders)
	mat.set_shader_parameter("state_border_dash_scale", c.state_border_dash_scale)
	mat.set_shader_parameter("state_border_dash_ratio", c.state_border_dash_ratio)


"""Адаптирует частоту и масштаб пульсации границ и DMZ к уровню DEFCON.
"""
static func apply_defcon_visuals(mat: ShaderMaterial, defcon_level: int) -> void:
	if mat == null:
		return
	match defcon_level:
		1: # DEFCON 1: Ядерная полночь
			mat.set_shader_parameter("dmz_pulse_speed", 10.0)
			mat.set_shader_parameter("dmz_dash_scale", 16.0)
			mat.set_shader_parameter("border_rendering_mode", 2)
		2: # DEFCON 2: Военное положение
			mat.set_shader_parameter("dmz_pulse_speed", 7.5)
			mat.set_shader_parameter("dmz_dash_scale", 20.0)
			mat.set_shader_parameter("border_rendering_mode", 2)
		3: # DEFCON 3: Кризис
			mat.set_shader_parameter("dmz_pulse_speed", 5.5)
			mat.set_shader_parameter("dmz_dash_scale", 24.0)
			mat.set_shader_parameter("border_rendering_mode", 2)
		_:
			mat.set_shader_parameter("dmz_pulse_speed", 3.5)
			mat.set_shader_parameter("dmz_dash_scale", 30.0)
			mat.set_shader_parameter("border_rendering_mode", 0)
