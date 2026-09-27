@tool
extends SceneTree

func _init():
	print("Building res://ui/themes/tno_theme.tres ...")
	var theme = Theme.new()
	
	# Load fonts
	var font_aldrich = load("res://assets/fonts/AldrichTNOV13.ttf")
	var font_bomb = load("res://assets/fonts/BombardierTNOV6.otf")
	
	if font_aldrich != null:
		theme.default_font = font_aldrich
		theme.default_font_size = 14
	
	# Common colors
	var col_cyan = Color(0.18, 0.90, 0.84, 0.95)
	var col_border = Color(0.14, 0.26, 0.32, 0.85)
	var col_bg = Color(0.06, 0.08, 0.11, 0.95)
	var col_bg_card = Color(0.09, 0.13, 0.17, 0.95)
	var col_bg_hi = Color(0.12, 0.18, 0.23, 0.95)
	var col_amber = Color(1.00, 0.75, 0.20, 0.95)
	var col_text = Color(0.90, 0.98, 0.97, 1.0)
	
	# Button StyleBoxes
	var sb_btn_norm = StyleBoxFlat.new()
	sb_btn_norm.bg_color = col_bg_card
	sb_btn_norm.border_color = col_border
	sb_btn_norm.set_border_width_all(1)
	sb_btn_norm.set_corner_radius_all(1)
	sb_btn_norm.content_margin_left = 12
	sb_btn_norm.content_margin_right = 12
	sb_btn_norm.content_margin_top = 6
	sb_btn_norm.content_margin_bottom = 6
	theme.set_stylebox("normal", "Button", sb_btn_norm)
	
	var sb_btn_hover = StyleBoxFlat.new()
	sb_btn_hover.bg_color = col_bg_hi
	sb_btn_hover.border_color = col_cyan
	sb_btn_hover.set_border_width_all(1)
	sb_btn_hover.set_corner_radius_all(1)
	sb_btn_hover.shadow_color = Color(col_cyan.r, col_cyan.g, col_cyan.b, 0.3)
	sb_btn_hover.shadow_size = 3
	sb_btn_hover.content_margin_left = 12
	sb_btn_hover.content_margin_right = 12
	sb_btn_hover.content_margin_top = 6
	sb_btn_hover.content_margin_bottom = 6
	theme.set_stylebox("hover", "Button", sb_btn_hover)
	
	var sb_btn_press = StyleBoxFlat.new()
	sb_btn_press.bg_color = Color(0.03, 0.04, 0.05, 1.0)
	sb_btn_press.border_color = col_amber
	sb_btn_press.set_border_width_all(1)
	sb_btn_press.set_corner_radius_all(1)
	sb_btn_press.content_margin_left = 12
	sb_btn_press.content_margin_right = 12
	sb_btn_press.content_margin_top = 6
	sb_btn_press.content_margin_bottom = 6
	theme.set_stylebox("pressed", "Button", sb_btn_press)
	
	var sb_btn_dis = StyleBoxFlat.new()
	sb_btn_dis.bg_color = Color(0.03, 0.04, 0.05, 0.8)
	sb_btn_dis.border_color = Color(0.08, 0.12, 0.15, 0.6)
	sb_btn_dis.set_border_width_all(1)
	sb_btn_dis.set_corner_radius_all(1)
	theme.set_stylebox("disabled", "Button", sb_btn_dis)
	
	theme.set_color("font_color", "Button", col_text)
	theme.set_color("font_hover_color", "Button", Color(0.4, 1.0, 0.95))
	theme.set_color("font_pressed_color", "Button", col_amber)
	theme.set_color("font_disabled_color", "Button", Color(0.35, 0.45, 0.5))
	
	# PanelContainer StyleBox
	var sb_panel = StyleBoxFlat.new()
	sb_panel.bg_color = col_bg
	sb_panel.border_color = col_border
	sb_panel.set_border_width_all(1)
	sb_panel.set_corner_radius_all(2)
	sb_panel.content_margin_left = 8
	sb_panel.content_margin_right = 8
	sb_panel.content_margin_top = 6
	sb_panel.content_margin_bottom = 6
	theme.set_stylebox("panel", "PanelContainer", sb_panel)
	theme.set_stylebox("panel", "Panel", sb_panel)
	
	# TabContainer StyleBox & Font
	var sb_tab_selected = StyleBoxFlat.new()
	sb_tab_selected.bg_color = col_bg_card
	sb_tab_selected.border_color = col_cyan
	sb_tab_selected.set_border_width_all(1)
	sb_tab_selected.border_width_bottom = 2
	sb_tab_selected.content_margin_left = 16
	sb_tab_selected.content_margin_right = 16
	sb_tab_selected.content_margin_top = 8
	sb_tab_selected.content_margin_bottom = 8
	theme.set_stylebox("tab_selected", "TabContainer", sb_tab_selected)
	
	var sb_tab_unselected = StyleBoxFlat.new()
	sb_tab_unselected.bg_color = Color(0.04, 0.06, 0.08, 0.9)
	sb_tab_unselected.border_color = col_border
	sb_tab_unselected.set_border_width_all(1)
	sb_tab_unselected.content_margin_left = 14
	sb_tab_unselected.content_margin_right = 14
	sb_tab_unselected.content_margin_top = 6
	sb_tab_unselected.content_margin_bottom = 6
	theme.set_stylebox("tab_unselected", "TabContainer", sb_tab_unselected)
	
	var sb_tab_panel = StyleBoxFlat.new()
	sb_tab_panel.bg_color = col_bg
	sb_tab_panel.border_color = col_cyan
	sb_tab_panel.border_width_top = 2
	sb_tab_panel.border_width_left = 1
	sb_tab_panel.border_width_right = 1
	sb_tab_panel.border_width_bottom = 1
	theme.set_stylebox("panel", "TabContainer", sb_tab_panel)
	
	# Labels
	theme.set_color("font_color", "Label", col_text)
	
	# TooltipPanel
	var sb_tt = StyleBoxFlat.new()
	sb_tt.bg_color = Color(0.04, 0.06, 0.08, 0.96)
	sb_tt.border_color = col_cyan
	sb_tt.set_border_width_all(1)
	sb_tt.set_corner_radius_all(1)
	sb_tt.content_margin_left = 10
	sb_tt.content_margin_right = 10
	sb_tt.content_margin_top = 6
	sb_tt.content_margin_bottom = 6
	theme.set_stylebox("panel", "TooltipPanel", sb_tt)
	theme.set_color("font_color", "TooltipLabel", col_text)
	
	# Save theme
	var err = ResourceSaver.save(theme, "res://ui/themes/tno_theme.tres")
	if err == OK:
		print("Successfully generated res://ui/themes/tno_theme.tres!")
	else:
		printerr("Failed to save theme: ", err)
	
	quit()
