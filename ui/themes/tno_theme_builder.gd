class_name TNOTheme
extends RefCounted

##
## TNOTheme: Центральная дизайн-система и фабрика стилей TNO (The New Order)
##
## Предоставляет цветовую палитру Cold War Terminal, шрифты Aldrich / Bombardier,
## аутентичные текстуры интерфейса и генераторы StyleBox для экранов Godot.
##

# ==============================================================================
# ЦВЕТОВАЯ ПАЛИТРА TNO (Design Tokens)
# ==============================================================================
const COLOR_BG_VOID          = Color(0.02, 0.03, 0.04, 1.0) # #05080a
const COLOR_BG_DARK          = Color(0.05, 0.07, 0.09, 0.96) # #0d1217
const COLOR_BG_PANEL         = Color(0.07, 0.10, 0.13, 0.95) # #121a21
const COLOR_BG_CARD          = Color(0.09, 0.13, 0.17, 0.92) # #17212b
const COLOR_BG_HIGHLIGHT     = Color(0.12, 0.18, 0.23, 0.95) # #1f2e3b

const COLOR_BORDER_DIM       = Color(0.12, 0.24, 0.28, 0.85) # #1f3d47
const COLOR_BORDER_CYAN      = Color(0.18, 0.90, 0.84, 0.95) # #2ee5d6 (Фирменный TNO циан)
const COLOR_BORDER_HOVER     = Color(0.35, 1.00, 0.95, 1.00) # #59fff2 (Свечение при наведении)
const COLOR_BORDER_AMBER     = Color(1.00, 0.72, 0.15, 0.95) # #ffb826 (Предупреждение / Внимание)
const COLOR_BORDER_RED       = Color(0.95, 0.25, 0.22, 0.95) # #f24038 (Кризис / Война / Дефицит)

const COLOR_TEXT_PRIMARY     = Color(0.90, 0.98, 0.97, 1.00) # #e6faf7 (Яркий фосфорный)
const COLOR_TEXT_SECONDARY   = Color(0.55, 0.68, 0.72, 1.00) # #8caebd (Телетайпный приглушенный)
const COLOR_TEXT_MUTED       = Color(0.32, 0.44, 0.48, 1.00) # #52707a (Вспомогательный)
const COLOR_TEXT_AMBER       = Color(1.00, 0.80, 0.25, 1.00) # #ffcc40
const COLOR_TEXT_GREEN       = Color(0.35, 0.95, 0.60, 1.00) # #59f299 (Профицит / Успех)
const COLOR_TEXT_RED         = Color(1.00, 0.35, 0.30, 1.00) # #ff594d (Дефицит / Урон)

# ==============================================================================
# ШРИФТЫ
# ==============================================================================
const FONT_ALDRICH_PATH = "res://assets/fonts/AldrichTNOV13.ttf"
const FONT_BOMBARDIER_PATH = "res://assets/fonts/BombardierTNOV6.otf"

static var _font_aldrich: Font = null
static var _font_bombardier: Font = null

static func get_font_aldrich() -> Font:
	if _font_aldrich == null:
		if ResourceLoader.exists(FONT_ALDRICH_PATH):
			_font_aldrich = load(FONT_ALDRICH_PATH)
	return _font_aldrich

static func get_font_bombardier() -> Font:
	if _font_bombardier == null:
		if ResourceLoader.exists(FONT_BOMBARDIER_PATH):
			_font_bombardier = load(FONT_BOMBARDIER_PATH)
	return _font_bombardier

# ==============================================================================
# АУТЕНТИЧНЫЕ ТЕКСТУРЫ TNO (кэшированные)
# ==============================================================================
static var _texture_cache: Dictionary = {}

static func get_texture(res_path: String) -> Texture2D:
	if _texture_cache.has(res_path):
		return _texture_cache[res_path]
	if ResourceLoader.exists(res_path):
		var tex = load(res_path) as Texture2D
		_texture_cache[res_path] = tex
		return tex
	return null

static func get_flag_texture(country_tag: String) -> Texture2D:
	var clean_tag = country_tag.strip_edges().to_upper()
	var path = "res://assets/gfx/flags/%s.png" % clean_tag
	var tex = get_texture(path)
	if tex != null:
		return tex
	# Fallback flag search
	for ext in ["_unified.png", "_communist.png", "_fascism.png", "_paternalism.png"]:
		tex = get_texture("res://assets/gfx/flags/%s%s" % [clean_tag, ext])
		if tex != null:
			return tex
	return get_texture("res://assets/gfx/flags/KOM.png")

static func get_ideology_icon(ideology_id: String) -> Texture2D:
	var key = ideology_id.to_lower().strip_edges()
	var path = "res://assets/gfx/interface/ideologies/%s_group.png" % key
	var tex = get_texture(path)
	if tex != null:
		return tex
	# Try specific subtype match
	path = "res://assets/gfx/interface/ideologies/%s.png" % key
	tex = get_texture(path)
	if tex != null:
		return tex
	# Common fallbacks
	if "communist" in key or "socialist" in key or "bolshev" in key:
		return get_texture("res://assets/gfx/interface/ideologies/communist_group.png")
	if "fascis" in key or "nazi" in key:
		return get_texture("res://assets/gfx/interface/ideologies/fascism_group.png")
	if "despot" in key or "warlord" in key:
		return get_texture("res://assets/gfx/interface/ideologies/despotism_group.png")
	return get_texture("res://assets/gfx/interface/ideologies/paternalism_group.png")

# ==============================================================================
# СТИЛИ КНОПОК И ПАНЕЛЕЙ
# ==============================================================================

static func apply_button_style(btn: Button, accent_color: Color = COLOR_BORDER_CYAN, base_bg: Color = COLOR_BG_CARD) -> void:
	if btn == null:
		return
	
	var font = get_font_aldrich()
	if font != null:
		btn.add_theme_font_override("font", font)
		btn.add_theme_font_size_override("font_size", 14)
	
	# Normal State
	var sb_normal = StyleBoxFlat.new()
	sb_normal.bg_color = base_bg
	sb_normal.border_color = COLOR_BORDER_DIM
	sb_normal.set_border_width_all(1)
	sb_normal.set_corner_radius_all(1)
	sb_normal.content_margin_left = 12
	sb_normal.content_margin_right = 12
	sb_normal.content_margin_top = 6
	sb_normal.content_margin_bottom = 6
	btn.add_theme_stylebox_override("normal", sb_normal)
	
	# Hover State (Cyan Glow)
	var sb_hover = StyleBoxFlat.new()
	sb_hover.bg_color = COLOR_BG_HIGHLIGHT
	sb_hover.border_color = accent_color
	sb_hover.set_border_width_all(1)
	sb_hover.set_corner_radius_all(1)
	sb_hover.shadow_color = Color(accent_color.r, accent_color.g, accent_color.b, 0.25)
	sb_hover.shadow_size = 4
	sb_hover.content_margin_left = 12
	sb_hover.content_margin_right = 12
	sb_hover.content_margin_top = 6
	sb_hover.content_margin_bottom = 6
	btn.add_theme_stylebox_override("hover", sb_hover)
	
	# Pressed State
	var sb_pressed = StyleBoxFlat.new()
	sb_pressed.bg_color = COLOR_BG_VOID
	sb_pressed.border_color = COLOR_BORDER_AMBER
	sb_pressed.set_border_width_all(1)
	sb_pressed.set_corner_radius_all(1)
	sb_pressed.content_margin_left = 12
	sb_pressed.content_margin_right = 12
	sb_pressed.content_margin_top = 6
	sb_pressed.content_margin_bottom = 6
	btn.add_theme_stylebox_override("pressed", sb_pressed)
	
	# Disabled State
	var sb_disabled = StyleBoxFlat.new()
	sb_disabled.bg_color = COLOR_BG_VOID
	sb_disabled.border_color = Color(0.1, 0.15, 0.18, 0.5)
	sb_disabled.set_border_width_all(1)
	sb_disabled.set_corner_radius_all(1)
	btn.add_theme_stylebox_override("disabled", sb_disabled)
	
	# Focus (transparent with cyan border)
	var sb_focus = StyleBoxFlat.new()
	sb_focus.draw_center = false
	sb_focus.border_color = accent_color
	sb_focus.set_border_width_all(1)
	btn.add_theme_stylebox_override("focus", sb_focus)
	
	# Font colors
	btn.add_theme_color_override("font_color", COLOR_TEXT_PRIMARY)
	btn.add_theme_color_override("font_hover_color", COLOR_BORDER_HOVER)
	btn.add_theme_color_override("font_pressed_color", COLOR_TEXT_AMBER)
	btn.add_theme_color_override("font_disabled_color", COLOR_TEXT_MUTED)

static func apply_panel_style(panel: PanelContainer, border_color: Color = COLOR_BORDER_DIM, bg_color: Color = COLOR_BG_DARK, border_width: int = 1, corner_radius: int = 2) -> void:
	if panel == null:
		return
	var sb = StyleBoxFlat.new()
	sb.bg_color = bg_color
	sb.border_color = border_color
	sb.set_border_width_all(border_width)
	sb.set_corner_radius_all(corner_radius)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", sb)

static func apply_box_style(panel: PanelContainer, border_color: Color = COLOR_BORDER_DIM, bg_color: Color = COLOR_BG_DARK, border_width: int = 1, corner_radius: int = 2) -> void:
	apply_panel_style(panel, border_color, bg_color, border_width, corner_radius)

static func apply_checkbox_style(chk: CheckBox, accent_color: Color = COLOR_BORDER_CYAN) -> void:
	if chk == null:
		return
	var font = get_font_aldrich()
	if font != null:
		chk.add_theme_font_override("font", font)
		chk.add_theme_font_size_override("font_size", 12)
	chk.add_theme_color_override("font_color", COLOR_TEXT_PRIMARY)
	chk.add_theme_color_override("font_hover_color", COLOR_BORDER_HOVER)
	chk.add_theme_color_override("font_pressed_color", accent_color)
	chk.add_theme_color_override("font_focus_color", COLOR_TEXT_PRIMARY)

static func apply_slider_style(slider: HSlider, accent_color: Color = COLOR_BORDER_CYAN) -> void:
	if slider == null:
		return
	var sb_slider = StyleBoxFlat.new()
	sb_slider.bg_color = COLOR_BG_VOID
	sb_slider.border_color = COLOR_BORDER_DIM
	sb_slider.set_border_width_all(1)
	sb_slider.content_margin_top = 4
	sb_slider.content_margin_bottom = 4
	slider.add_theme_stylebox_override("slider", sb_slider)
	
	var sb_grabber_area = StyleBoxFlat.new()
	sb_grabber_area.bg_color = Color(accent_color.r, accent_color.g, accent_color.b, 0.4)
	sb_grabber_area.border_color = accent_color
	sb_grabber_area.set_border_width_all(1)
	slider.add_theme_stylebox_override("grabber_area", sb_grabber_area)
	slider.add_theme_stylebox_override("grabber_area_highlight", sb_grabber_area)

static func create_pill_box(icon_tex: Texture2D, label_text: String, tooltip: String = "") -> PanelContainer:
	var container := PanelContainer.new()
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.06, 0.08, 0.92)
	sb.border_color = Color(0.16, 0.28, 0.34, 0.9)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(2)
	sb.content_margin_left = 6
	sb.content_margin_right = 8
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	container.add_theme_stylebox_override("panel", sb)
	
	if not tooltip.is_empty():
		container.tooltip_text = tooltip
	
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	container.add_child(hbox)
	
	if icon_tex != null:
		var trect := TextureRect.new()
		trect.texture = icon_tex
		trect.custom_minimum_size = Vector2(18, 18)
		trect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		trect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		trect.mouse_filter = Control.MOUSE_FILTER_PASS
		hbox.add_child(trect)
	
	var lbl := Label.new()
	lbl.name = "ValueLabel"
	lbl.text = label_text
	var font = get_font_aldrich()
	if font != null:
		lbl.add_theme_font_override("font", font)
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", COLOR_TEXT_PRIMARY)
	lbl.mouse_filter = Control.MOUSE_FILTER_PASS
	hbox.add_child(lbl)
	
	return container
