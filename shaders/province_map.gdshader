shader_type canvas_item;

/**
 * ==============================================================================
 * TNO CRT MILITARY TERMINAL: PROVINCE MAP & HIERARCHICAL BORDER SHADER (GODOT 4)
 * ==============================================================================
 * High-performance, multi-layered GIS border & territory rendering engine:
 *
 * 1. HIERARCHICAL BORDER DETECTION (via ownership_lut Texture):
 *    - NATIONAL BORDERS: owner_A != owner_B. Thick, phosphor-luminescent lines.
 *    - STATE BORDERS: owner_A == owner_B, but state_A != state_B. Medium line.
 *    - TACTICAL PROVINCE BORDERS: state_A == state_B. Dynamic sub-division,
 *      fades in smoothly upon camera zoom (tactical theater view).
 *    - COASTLINES: land vs sea/lake. High-contrast maritime contour.
 *    - ACTIVE FRONTLINES: contested warzones, pulsating alert neon red/amber.
 *    - PLAYER SOVEREIGNTY: glowing neon halo on player nation perimeter.
 *
 * 2. CRT & TACTICAL TERMINAL POST-PROCESSING:
 *    - Phosphor edge glow (Bloom / Luminescence).
 *    - CRT raster scanline modulation.
 *    - Tactical coordinate grid with reticles.
 *    - Rotating radar reconnaissance sweep.
 *
 * 3. STRATEGIC DATA-DRIVEN MAP MODES:
 *    - 0 = Political Sovereignty (LUT Palette)
 *    - 1 = Economic / Industrial Capacity (IC Heatmap)
 *    - 2 = Unrest & Secession Risk Heatmap
 *    - 3 = Global Spheres of Influence & Blocs
 * ==============================================================================
 */

// ------------------------------------------------------------------------------
// 1. TEXTURES & SAMPLERS
// ------------------------------------------------------------------------------
uniform sampler2D provinces_mask : filter_nearest, repeat_disable;
uniform sampler2D lut_palette : filter_nearest, repeat_disable;
uniform sampler2D data_lut_texture : filter_nearest, repeat_disable;
uniform sampler2D ownership_lut : filter_nearest, repeat_disable;
uniform sampler2D rivers_mask : filter_linear, repeat_disable;
uniform sampler2D world_normal : filter_linear, repeat_disable;

// ------------------------------------------------------------------------------
// 2. MAP MODES & CAMERA SCALE
// ------------------------------------------------------------------------------
// 0 = Political, 1 = Economy (IC), 2 = Unrest / Stability, 3 = Diplomacy / Spheres
uniform int map_mode = 0;
uniform float zoom_level = 1.0;

// ------------------------------------------------------------------------------
// 3. INTERACTIVE HIGHLIGHTS
// ------------------------------------------------------------------------------
uniform int hovered_province_id = 0;
uniform int selected_province_id = 0;

// ------------------------------------------------------------------------------
// 4. BORDER HIERARCHY SWITCHES & ADVANCED CONFIGURATION
// ------------------------------------------------------------------------------
uniform bool enable_borders = true;
uniform bool show_national_borders = true;
uniform bool show_state_borders = true;
uniform bool show_province_borders = true;
uniform bool show_coastlines = true;
uniform bool enable_frontline_pulse = true;

// Adaptive line widths in base texels (automatically compensated by zoom_level)
uniform float border_thickness : hint_range(0.0, 6.0, 0.1) = 1.0;
uniform float national_border_width : hint_range(0.5, 6.0, 0.1) = 2.2;
uniform float state_border_width : hint_range(0.2, 4.0, 0.1) = 1.2;
uniform float province_border_width : hint_range(0.1, 2.5, 0.1) = 0.7;
uniform float coastline_width : hint_range(0.5, 5.0, 0.1) = 1.8;
uniform float province_border_zoom_threshold : hint_range(0.5, 5.0, 0.1) = 1.6;

// Dynamic Border Demarcation Mode:
// 0 = Standard Sovereign Demarcation
// 1 = Spheres of Influence / Blocs (OFN, Unity-Pakt, Sphere, Russia/Player)
// 2 = Smuta / Warlord Disputed / DMZ Demilitarized Zones
uniform int border_rendering_mode : hint_range(0, 2) = 0;

// Fortifications & Tactical Barriers (Crenelated Fort Teeth)
uniform bool enable_fortifications = true;
uniform float fortification_spacing : hint_range(4.0, 64.0, 1.0) = 16.0;
uniform float fortification_notch_width : hint_range(1.0, 16.0, 0.5) = 6.0;
uniform vec4 fortification_color : source_color = vec4(1.0, 0.85, 0.20, 1.0); // Fort yellow-amber

// DMZ & Contested Border Pulsing
uniform vec4 dmz_border_color : source_color = vec4(1.0, 0.22, 0.15, 1.0); // Warning crimson
uniform float dmz_pulse_speed : hint_range(1.0, 15.0, 0.5) = 5.0;
uniform float dmz_dash_scale : hint_range(5.0, 100.0, 2.0) = 30.0;

// Advanced State Border Styling Modes:
// 0 = Classic Phosphor Green/Teal, 1 = Dual-Hue Ribbon (Country Color Blend), 2 = High-Contrast Dark-Core
uniform int border_color_mode : hint_range(0, 2) = 1;

// Inner Territorial Glow / Border Feathering
uniform bool enable_inner_border_glow = true;
uniform float inner_border_glow_width : hint_range(1.0, 10.0, 0.5) = 4.0;
uniform float inner_border_glow_intensity : hint_range(0.0, 1.5, 0.05) = 0.45;
uniform vec4 inner_border_glow_tint : source_color = vec4(0.0, 0.0, 0.0, 0.0); // alpha > 0 overrides country tint

// ------------------------------------------------------------------------------
// TNO POLITICAL VIGNETTE & INNER SHADOW (BORDER GLOW & INNER CORE FALLOFF)
// ------------------------------------------------------------------------------
uniform bool enable_political_vignette = true;
uniform float inner_falloff_dim : hint_range(0.0, 0.6, 0.02) = 0.32;
uniform float border_glow_boost : hint_range(1.0, 2.0, 0.05) = 1.35;
uniform float vignette_desaturation : hint_range(0.0, 0.5, 0.02) = 0.12;

// ------------------------------------------------------------------------------
// DYNAMIC BATTLE INTENSITY STROBE (FRONTLINES)
// ------------------------------------------------------------------------------
uniform float battle_intensity : hint_range(0.0, 1.0, 0.05) = 0.85;
uniform float battle_strobe_speed : hint_range(1.0, 25.0, 0.5) = 12.0;
uniform vec4 battle_strobe_color : source_color = vec4(1.00, 0.12, 0.08, 1.0);
uniform vec4 battle_warning_amber : source_color = vec4(1.00, 0.72, 0.12, 1.0);

// ------------------------------------------------------------------------------
// REBELLION & UNREST PROCEDURAL HATCHING
// ------------------------------------------------------------------------------
uniform bool enable_rebellion_hatching = true;
uniform float rebellion_unrest_threshold : hint_range(0.0, 1.0, 0.05) = 0.70;
uniform float hatching_density : hint_range(4.0, 64.0, 1.0) = 16.0;
uniform float hatching_stripe_ratio : hint_range(0.1, 0.9, 0.05) = 0.35;
uniform float hatching_speed : hint_range(0.0, 40.0, 1.0) = 8.0;
uniform vec4 rebellion_hatch_color : source_color = vec4(0.95, 0.18, 0.12, 0.55);
uniform vec4 strike_hatch_color : source_color = vec4(0.98, 0.78, 0.12, 0.45);

// Dashed State Borders (Tactical Separation of Internal Regions)
uniform bool enable_dashed_state_borders = true;
uniform float state_border_dash_scale : hint_range(10.0, 200.0, 5.0) = 80.0;
uniform float state_border_dash_ratio : hint_range(0.1, 0.9, 0.05) = 0.55;

// Sub-pixel Anti-Aliased Border Edges
uniform bool enable_antialiased_borders = true;

// Dynamic Sovereignty Focus (Selected / Hovered Nation Halo Flare)
uniform int focused_country_id = 0;
uniform float focused_border_pulse_speed : hint_range(1.0, 10.0, 0.5) = 4.0;
uniform vec4 focused_border_color : source_color = vec4(1.00, 0.92, 0.35, 1.0); // Radiant Gold/Amber

// ------------------------------------------------------------------------------
// 5. COLOR PALETTES & PHOSPHOR GLOW
// ------------------------------------------------------------------------------
uniform vec4 default_color : source_color = vec4(0.08, 0.10, 0.12, 1.0);
uniform vec4 water_color : source_color = vec4(0.03, 0.05, 0.08, 1.0);

// Topographical Relief & Normal Map Hillshading
uniform bool enable_relief_hillshade = true;
uniform float relief_intensity : hint_range(0.0, 2.0, 0.05) = 0.65;
uniform vec3 light_direction = vec3(-0.55, -0.55, 0.62);

// Hydrography (Rivers)
uniform bool enable_rivers = true;
uniform vec4 river_color : source_color = vec4(0.08, 0.72, 0.95, 0.95);
uniform float river_glow_intensity : hint_range(0.0, 2.0, 0.05) = 0.60;

// Ocean Bathymetry & Coastal Shelf
uniform bool enable_ocean_bathymetry = true;
uniform vec4 deep_water_color : source_color = vec4(0.02, 0.04, 0.07, 1.0);
uniform vec4 shelf_water_color : source_color = vec4(0.04, 0.14, 0.22, 1.0);

// Border colors (Authentic TNO CRT Phosphor Palette)
uniform vec4 national_border_color : source_color = vec4(0.20, 1.00, 0.40, 0.95);  // Phosphor Green #33ff66
uniform vec4 state_border_color : source_color = vec4(0.12, 0.65, 0.85, 0.65);     // Cyan-teal state line
uniform vec4 province_border_color : source_color = vec4(0.15, 0.42, 0.35, 0.40);  // Subtle tactical grid
uniform vec4 coastline_color : source_color = vec4(0.00, 0.90, 1.00, 0.92);        // Maritime neon cyan
uniform vec4 frontline_border_color : source_color = vec4(1.00, 0.25, 0.12, 1.00); // Combat alert red/amber
uniform vec4 player_border_glow_color : source_color = vec4(0.10, 0.95, 0.85, 1.00); // Sovereign pulse

uniform float phosphor_glow_intensity : hint_range(0.0, 2.0, 0.05) = 0.55;
uniform float frontline_pulse_speed : hint_range(1.0, 15.0, 0.5) = 6.5;

// Selection & Hover
uniform vec4 hover_color : source_color = vec4(1.0, 1.0, 1.0, 0.35);
uniform vec4 select_color : source_color = vec4(0.2, 0.95, 0.85, 0.45);
uniform bool enable_hover_highlight = true;
uniform bool enable_selection_highlight = true;
uniform float hover_pulse_speed : hint_range(0.0, 10.0, 0.1) = 3.0;

// ------------------------------------------------------------------------------
// 6. TACTICAL GRID & RADAR RECON SWEEP
// ------------------------------------------------------------------------------
uniform bool enable_tactical_grid = false;
uniform float grid_spacing = 32.0;
uniform vec4 grid_color : source_color = vec4(0.2, 0.8, 0.6, 0.18);

uniform bool enable_radar_sweep = false;
uniform vec2 radar_center = vec2(0.5, 0.5);
uniform float radar_speed = 1.2;
uniform float radar_radius : hint_range(0.05, 1.0, 0.05) = 0.35;
uniform vec4 radar_sweep_color : source_color = vec4(0.2, 0.95, 0.7, 0.25);

// ------------------------------------------------------------------------------
// 7. RULER DOMAIN FOCUS & SOVEREIGNTY PULSE
// ------------------------------------------------------------------------------
uniform bool ruler_domain_focus = false;
uniform float ruler_dim_factor : hint_range(0.05, 1.0, 0.05) = 0.30;
uniform bool enable_sovereignty_pulse = false;
uniform float sovereignty_pulse_speed : hint_range(0.5, 10.0, 0.1) = 3.5;
uniform vec4 player_domain_color : source_color = vec4(0.0, 0.0, 0.0, 0.0);

// CRT scanline emulation
uniform bool enable_crt_scanlines = true;
uniform float scanline_strength : hint_range(0.0, 0.2, 0.01) = 0.04;


// ==============================================================================
// INTERNAL DATA STRUCTURES & UNPACKING
// ==============================================================================
struct ProvinceMeta {
	int country_id;
	int state_id;
	bool is_water;
	bool is_player;
	bool is_frontline;
	bool is_coastal;
	bool is_fortified;
	bool is_dmz;
};

/**
 * Decodes RGB pixel channels into 24-bit Province ID.
 */
int decode_province_id(vec4 col) {
	ivec3 rgb = ivec3(round(col.rgb * 255.0));
	return rgb.r | (rgb.g << 8) | (rgb.b << 16);
}

/**
 * Calculates 1D/2D LUT texture coordinates from integer ID.
 */
ivec2 get_lut_coords(int id, ivec2 lut_size) {
	if (lut_size.y == 1) {
		return ivec2(id, 0);
	}
	return ivec2(id % lut_size.x, id / lut_size.x);
}

/**
 * Unpacks ownership & border metadata from ownership_lut texture:
 * - Channel R: country_id (0..255, 0 = neutral/water)
 * - Channel G: state_id low byte (state_id & 0xFF)
 * - Channel B: state_id high byte ((state_id >> 8) & 0xFF)
 * - Channel A: Bitmask flags (1=water, 2=player, 4=frontline, 8=coastal, 16=fortified, 32=dmz)
 */
ProvinceMeta sample_province_meta(int id) {
	ProvinceMeta m;
	m.country_id = 0;
	m.state_id = 0;
	m.is_water = false;
	m.is_player = false;
	m.is_frontline = false;
	m.is_coastal = false;
	m.is_fortified = false;
	m.is_dmz = false;

	if (id <= 0) {
		m.is_water = true;
		return m;
	}

	ivec2 lut_size = textureSize(ownership_lut, 0);
	if (lut_size.x <= 0 || lut_size.y <= 0) {
		return m;
	}

	ivec2 coord = get_lut_coords(id, lut_size);
	if (coord.y >= lut_size.y) {
		return m;
	}

	vec4 raw = texelFetch(ownership_lut, coord, 0);
	ivec4 bytes = ivec4(round(raw * 255.0));

	m.country_id = bytes.r;
	m.state_id = bytes.g | (bytes.b << 8);
	int flags = bytes.a;
	m.is_water = (flags & 1) != 0;
	m.is_player = (flags & 2) != 0;
	m.is_frontline = (flags & 4) != 0;
	m.is_coastal = (flags & 8) != 0;
	m.is_fortified = (flags & 16) != 0;
	m.is_dmz = (flags & 32) != 0;

	return m;
}

/**
 * Samples political owner color from lut_palette.
 */
vec4 sample_political_color(int id) {
	if (id <= 0) return default_color;
	ivec2 lut_size = textureSize(lut_palette, 0);
	if (lut_size.x <= 0 || lut_size.y <= 0) return default_color;

	ivec2 coord = get_lut_coords(id, lut_size);
	if (coord.y < lut_size.y) {
		return texelFetch(lut_palette, coord, 0);
	}
	return default_color;
}

/**
 * Samples packed scalar parameters from data_lut_texture:
 * R: Industrial Capacity (0..1)
 * G: Unrest / Secession Risk (0..1)
 * B: Infrastructure level (0..1)
 * A: Sphere code (0..1)
 */
vec4 sample_region_data(int id) {
	if (id <= 0) return vec4(0.0);
	ivec2 lut_size = textureSize(data_lut_texture, 0);
	if (lut_size.x <= 0 || lut_size.y <= 0) return vec4(0.0);

	ivec2 coord = get_lut_coords(id, lut_size);
	if (coord.y < lut_size.y) {
		return texelFetch(data_lut_texture, coord, 0);
	}
	return vec4(0.0);
}

/**
 * Calculates display color based on active Map Mode.
 */
vec4 get_map_mode_color(int id, vec4 pol_color, bool is_water) {
	if (id <= 0 || is_water) return water_color;

	// Mode 0: Political Sovereignty
	if (map_mode == 0) {
		return pol_color;
	}

	vec4 reg_data = sample_region_data(id);

	// Mode 1: Economic / Industrial Capacity (Phosphor Green/Amber gradation)
	if (map_mode == 1) {
		float ic = clamp(reg_data.r, 0.0, 1.0);
		vec4 low_ic = vec4(0.06, 0.12, 0.09, 1.0);
		vec4 mid_ic = vec4(0.15, 0.65, 0.35, 1.0);
		vec4 high_ic = vec4(0.95, 0.85, 0.25, 1.0);

		if (ic < 0.5) {
			return mix(low_ic, mid_ic, ic * 2.0);
		} else {
			return mix(mid_ic, high_ic, (ic - 0.5) * 2.0);
		}
	}

	// Mode 2: Unrest & Secession Risk Heatmap (Teal calm -> Warning Red)
	if (map_mode == 2) {
		float unrest = clamp(reg_data.g, 0.0, 1.0);
		vec4 calm_col = vec4(0.08, 0.22, 0.25, 1.0);
		vec4 alert_col = vec4(0.90, 0.22, 0.15, 1.0);
		return mix(calm_col, alert_col, unrest);
	}

	// Mode 3: Diplomacy & Global Spheres of Influence
	if (map_mode == 3) {
		float sphere = reg_data.a;
		if (sphere > 0.85) return vec4(0.85, 0.20, 0.20, 1.0); // Russia / Sovereign Space (Red)
		if (sphere > 0.65) return vec4(0.90, 0.48, 0.15, 1.0); // Co-Prosperity Sphere (Gold/Orange)
		if (sphere > 0.42) return vec4(0.38, 0.42, 0.48, 1.0); // Einheitspakt (Steel Gray)
		if (sphere > 0.28) return vec4(0.15, 0.68, 0.45, 1.0); // Triumvirate (Emerald Green)
		if (sphere > 0.12) return vec4(0.20, 0.52, 0.90, 1.0); // OFN (Atlantic Blue)
		return vec4(0.15, 0.18, 0.17, 1.0);                     // Unaligned / Non-Aligned
	}

	return pol_color;
}

/**
 * Returns discrete bloc/sphere index:
 * 5 = Russia / Sovereign Core, 4 = Co-Prosperity Sphere, 3 = Unity-Pakt, 2 = Triumvirate, 1 = OFN, 0 = Non-aligned
 */
int get_sphere_bucket(float sphere) {
	if (sphere > 0.85) return 5;
	if (sphere > 0.65) return 4;
	if (sphere > 0.42) return 3;
	if (sphere > 0.28) return 2;
	if (sphere > 0.12) return 1;
	return 0;
}


/**
 * Returns distinct CRT neon color for alliance/sphere borders.
 */
vec4 get_sphere_glow_color(int bucket) {
	if (bucket == 5) return vec4(1.00, 0.25, 0.25, 1.0); // Russia / Sovereign (Soviet Neon Red)
	if (bucket == 4) return vec4(1.00, 0.50, 0.20, 1.0); // Co-Prosperity Sphere (Rising Sun Amber)
	if (bucket == 3) return vec4(0.35, 0.75, 0.95, 1.0); // Unity-Pakt (Teal/Iron Grey)
	if (bucket == 2) return vec4(0.20, 0.85, 0.50, 1.0); // Triumvirate (Emerald Green)
	if (bucket == 1) return vec4(0.20, 0.60, 1.00, 1.0); // OFN (Democracy Neon Blue)
	return vec4(0.25, 0.85, 0.55, 0.7);                  // Non-aligned (Emerald)
}


// ==============================================================================
// FRAGMENT SHADING PIPELINE
// ==============================================================================
void fragment() {
	vec2 mask_size = vec2(textureSize(provinces_mask, 0));
	vec2 texel = 1.0 / mask_size;

	vec4 mask_col = texture(provinces_mask, UV);
	int center_id = decode_province_id(mask_col);
	float zoom_comp = max(zoom_level * 0.55, 0.35);

	// 1. Fetch metadata and base colors
	ProvinceMeta center_meta = sample_province_meta(center_id);
	vec4 political_col = sample_political_color(center_id);
	vec4 final_color = get_map_mode_color(center_id, political_col, center_meta.is_water);
	vec4 reg_data = sample_region_data(center_id);

	bool is_player = center_meta.is_player || ((center_id > 0) && (reg_data.a >= 0.90) || (player_domain_color.a > 0.0 && distance(political_col.rgb, player_domain_color.rgb) < 0.05));

	// 1.1 Ruler Domain Focus (Dim external non-player territories)
	if (ruler_domain_focus && center_id > 0 && !center_meta.is_water && !is_player) {
		final_color.rgb = mix(vec3(0.025, 0.045, 0.055), final_color.rgb, ruler_dim_factor);
	}

	// 1.2 Topographical Relief / Normal Map Hillshading
	if (enable_relief_hillshade && !center_meta.is_water && center_id > 0) {
		vec3 normal_raw = texture(world_normal, UV).rgb;
		if (length(normal_raw) > 0.05) {
			vec3 norm = normalize(normal_raw * 2.0 - 1.0);
			float n_dot_l = dot(norm, normalize(light_direction));
			float hillshade = clamp(0.62 + 0.50 * n_dot_l, 0.38, 1.40);
			final_color.rgb = mix(final_color.rgb, final_color.rgb * hillshade, relief_intensity);
		}
	}

	// 1.3 Ocean Bathymetry & Tactical Radar Sonar Waves
	if (center_meta.is_water) {
		if (enable_ocean_bathymetry) {
			float sonar_dist = length(UV - radar_center) * 60.0;
			float sonar_ripple = sin(sonar_dist - TIME * 2.8);
			float ripple_boost = smoothstep(0.82, 1.0, sonar_ripple) * 0.045;
			float bathy_wave = sin(UV.y * 1400.0 + UV.x * 550.0 + TIME * 0.6) * 0.012;
			final_color = mix(deep_water_color, shelf_water_color, 0.28 + bathy_wave);
			final_color.rgb += vec3(0.02, 0.09, 0.15) * ripple_boost;
		} else {
			final_color = water_color;
		}
	}

	// 1.4 Hydrographic Rivers Network
	if (enable_rivers && !center_meta.is_water && center_id > 0) {
		float r_sample = texture(rivers_mask, UV).r;
		if (r_sample > 0.05) {
			float r_alpha = (enable_antialiased_borders ? smoothstep(0.05, 0.60, r_sample) : r_sample) * river_color.a;
			final_color = mix(final_color, river_color, r_alpha);
			final_color.rgb += river_color.rgb * (r_sample * river_glow_intensity * phosphor_glow_intensity);
		}
	}

	// --------------------------------------------------------------------------
	// 2. MULTI-LAYERED HIERARCHICAL BORDER DETECTION
	// --------------------------------------------------------------------------
	if (enable_borders && border_thickness > 0.0 && center_id > 0) {
		// Zoom compensation: maintains constant readable line width in screen pixels
		float zoom_comp = max(zoom_level * 0.55, 0.35);
		float base_unit = border_thickness / zoom_comp;

		// Direction vectors (4-way orthogonal + 4-way diagonal)
		const vec2 kernel_dirs[8] = vec2[](
			vec2(1.0, 0.0), vec2(-1.0, 0.0), vec2(0.0, 1.0), vec2(0.0, -1.0),
			vec2(0.7071, 0.7071), vec2(-0.7071, 0.7071), vec2(0.7071, -0.7071), vec2(-0.7071, -0.7071)
		);

		// Dynamic edge weights and flags
		float national_hit = 0.0;
		float inner_glow_hit = 0.0;
		float state_hit = 0.0;
		float prov_hit = 0.0;
		float coast_hit = 0.0;
		float frontline_hit = 0.0;
		float player_hit = 0.0;
		float dmz_hit = 0.0;
		float fort_hit = 0.0;
		float bloc_inner_hit = 0.0;
		float bloc_outer_hit = 0.0;
		int center_bloc = get_sphere_bucket(reg_data.a);

		// Test distances for hierarchical boundaries
		float r_nat = base_unit * national_border_width;
		float r_inner = base_unit * inner_border_glow_width;
		float r_state = base_unit * state_border_width;
		float r_prov = base_unit * province_border_width;
		float r_coast = base_unit * coastline_width;

		// Tactical province border fade factor (fades in when camera zooms in)
		float prov_zoom_fade = smoothstep(province_border_zoom_threshold, province_border_zoom_threshold + 0.8, zoom_level);

		// Sample multi-kernel neighborhood
		for (int i = 0; i < 8; i++) {
			vec2 dir = kernel_dirs[i];

			// 0. Inner Territorial Glow & Political Vignette Falloff Sampling
			if ((enable_inner_border_glow || enable_political_vignette) && !center_meta.is_water) {
				vec2 uv_inner = UV + dir * r_inner * texel;
				int n_id_inner = decode_province_id(texture(provinces_mask, uv_inner));
				if (n_id_inner != center_id) {
					ProvinceMeta n_meta_inner = sample_province_meta(n_id_inner);
					if (n_meta_inner.is_water || n_meta_inner.country_id != center_meta.country_id) {
						inner_glow_hit += (i < 4 ? 1.0 : 0.7071);
					}
				} else if (r_inner >= r_nat) {
					// Optimization: If the outermost probe is already inside the same province,
					// all intermediate hierarchical probes (national, state, provincial) along this ray are identical.
					continue;
				}
			}

			// Sample at national/coastline radius
			vec2 uv_nat = UV + dir * r_nat * texel;
			int n_id_nat = decode_province_id(texture(provinces_mask, uv_nat));

			if (n_id_nat != center_id) {
				ProvinceMeta n_meta = sample_province_meta(n_id_nat);
				vec4 n_reg_data = sample_region_data(n_id_nat);

				// 1. Coastline detection (Land vs Water boundary)
				if (center_meta.is_water != n_meta.is_water) {
					if (show_coastlines) {
						coast_hit += (i < 4 ? 1.0 : 0.707);
					}
				}
				// 2. Both are land or both are water
				else if (!center_meta.is_water) {
					// Disputed DMZ / Smuta Warlord Contested Border
					if ((center_meta.is_dmz || n_meta.is_dmz) ||
						(border_rendering_mode == 2 && (center_meta.is_frontline || n_meta.is_frontline || reg_data.g > 0.40))) {
						dmz_hit += 1.0;
					}

					// Active Frontline / War contested border
					if (enable_frontline_pulse && (center_meta.is_frontline || n_meta.is_frontline) && (center_meta.country_id != n_meta.country_id)) {
						frontline_hit += 1.0;
					}

					// Player sovereign perimeter
					if ((is_player != n_meta.is_player) && (center_meta.country_id != n_meta.country_id)) {
						player_hit += 1.0;
					}

					// International border (Different country)
					if (show_national_borders && (center_meta.country_id != n_meta.country_id)) {
						national_hit += 1.0;

						// Blocs & Spheres of Influence tracking
						int n_bloc = get_sphere_bucket(n_reg_data.a);
						if (center_bloc == n_bloc && center_bloc > 0) {
							bloc_inner_hit += 1.0;
						} else {
							bloc_outer_hit += 1.0;
						}
					}

					// Fortification barrier detection
					if (enable_fortifications && (center_meta.is_fortified || n_meta.is_fortified || reg_data.b > 0.35)) {
						fort_hit += 1.0;
					}
				}
			} else if (r_nat >= r_state && r_nat >= r_prov) {
				// Optimization: If national radius is already within the province,
				// intermediate state and province probes along this ray are inside the same province.
				continue;
			}

			// Sample at state radius
			if (show_state_borders && !center_meta.is_water) {
				vec2 uv_state = UV + dir * r_state * texel;
				int n_id_state = decode_province_id(texture(provinces_mask, uv_state));

				if (n_id_state != center_id) {
					ProvinceMeta n_meta_state = sample_province_meta(n_id_state);
					if (!n_meta_state.is_water && center_meta.country_id == n_meta_state.country_id && center_meta.state_id != n_meta_state.state_id) {
						state_hit += (i < 4 ? 1.0 : 0.707);
					}
				}
			}

			// Sample at province radius (only if zoomed in sufficiently)
			if (show_province_borders && prov_zoom_fade > 0.01 && !center_meta.is_water) {
				vec2 uv_prov = UV + dir * r_prov * texel;
				int n_id_prov = decode_province_id(texture(provinces_mask, uv_prov));

				if (n_id_prov != center_id) {
					ProvinceMeta n_meta_prov = sample_province_meta(n_id_prov);
					if (!n_meta_prov.is_water && center_meta.country_id == n_meta_prov.country_id && center_meta.state_id == n_meta_prov.state_id) {
						prov_hit += 1.0;
					}
				}
			}
		}

		// Normalize hits
		inner_glow_hit = clamp(inner_glow_hit / 4.0, 0.0, 1.0);
		national_hit = clamp(national_hit / 4.0, 0.0, 1.0);
		coast_hit = clamp(coast_hit / 3.5, 0.0, 1.0);
		state_hit = clamp(state_hit / 3.5, 0.0, 1.0);
		prov_hit = clamp(prov_hit / 3.0, 0.0, 1.0) * prov_zoom_fade;
		frontline_hit = clamp(frontline_hit / 2.0, 0.0, 1.0);
		player_hit = clamp(player_hit / 3.0, 0.0, 1.0);
		dmz_hit = clamp(dmz_hit / 2.5, 0.0, 1.0);
		fort_hit = clamp(fort_hit / 2.5, 0.0, 1.0);
		bloc_inner_hit = clamp(bloc_inner_hit / 4.0, 0.0, 1.0);
		bloc_outer_hit = clamp(bloc_outer_hit / 4.0, 0.0, 1.0);

		// Blending in order of priority: Vignette -> Inner Glow -> Province -> State -> Coastline -> National -> Focus -> Fortifications -> Player -> Frontline -> DMZ

		// 0.0 TNO Political Vignette & Inner Shadow (Border Glow vs Inner Core Falloff)
		if (enable_political_vignette && !center_meta.is_water && center_id > 0 && map_mode == 0) {
			float border_prox = clamp(inner_glow_hit, 0.0, 1.0);
			float vig_factor = mix(1.0 - inner_falloff_dim, border_glow_boost, smoothstep(0.04, 0.85, border_prox));
			final_color.rgb *= vig_factor;
			float core_gray = dot(final_color.rgb, vec3(0.299, 0.587, 0.114));
			final_color.rgb = mix(vec3(core_gray), final_color.rgb, mix(1.0 - vignette_desaturation, 1.0, border_prox));
		}

		// 0.1 Inner Territorial Glow / Border Feathering
		if (enable_inner_border_glow && inner_glow_hit > 0.02 && !center_meta.is_water) {
			float glow_alpha = (enable_antialiased_borders ? smoothstep(0.02, 0.85, inner_glow_hit) : inner_glow_hit) * inner_border_glow_intensity;
			vec3 glow_tint_rgb;
			if (inner_border_glow_tint.a > 0.05) {
				glow_tint_rgb = inner_border_glow_tint.rgb;
			} else {
				glow_tint_rgb = mix(political_col.rgb * 1.55 + vec3(0.04), national_border_color.rgb, 0.30);
			}
			final_color.rgb = mix(final_color.rgb, glow_tint_rgb, glow_alpha);
			final_color.rgb += glow_tint_rgb * (glow_alpha * phosphor_glow_intensity * 0.35);
		}

		// 1. Tactical Province Borders (Subtle grid)
		if (prov_hit > 0.05) {
			float p_alpha = (enable_antialiased_borders ? smoothstep(0.05, 0.70, prov_hit) : prov_hit) * province_border_color.a;
			final_color = mix(final_color, province_border_color, p_alpha);
		}

		// 2. Internal Regional / State Borders (Tactical Dashed or Solid)
		if (state_hit > 0.05) {
			float state_visibility = 1.0;
			if (enable_dashed_state_borders) {
				vec2 screen_pix = UV * mask_size;
				float dash_period = max(state_border_dash_scale / zoom_comp, 8.0);
				float dash_val = mod(screen_pix.x + screen_pix.y, dash_period);
				float dash_len = dash_period * state_border_dash_ratio;
				if (dash_val > dash_len) {
					state_visibility = 0.0;
				}
			}
			if (state_visibility > 0.0) {
				float s_alpha = (enable_antialiased_borders ? smoothstep(0.05, 0.70, state_hit) : state_hit) * state_border_color.a;
				final_color = mix(final_color, state_border_color, s_alpha);
			}
		}

		// 3. Coastlines & Maritime Contours (Contrast Shelf Darkening + Neon Cyan Wave Shimmer)
		if (coast_hit > 0.05) {
			if (center_meta.is_water) {
				// Contrast shelf darkening on water side
				vec4 trench = mix(deep_water_color * 0.35, vec4(0.01, 0.02, 0.035, 1.0), 0.85);
				float t_alpha = (enable_antialiased_borders ? smoothstep(0.05, 0.70, coast_hit) : coast_hit) * 0.90;
				final_color = mix(final_color, trench, t_alpha);
			} else {
				// Neon cyan maritime edge with subtle CRT wave shimmer
				float shimmer = 1.0 + 0.08 * sin(UV.y * 1200.0 + TIME * 2.0);
				float c_alpha = (enable_antialiased_borders ? smoothstep(0.05, 0.70, coast_hit) : coast_hit) * coastline_color.a;
				vec4 c_col = coastline_color * shimmer;
				final_color = mix(final_color, c_col, c_alpha);
				final_color.rgb += c_col.rgb * (coast_hit * phosphor_glow_intensity * 0.55);
			}
		}

		// 4. National Sovereign Borders (Standard / Blocs / Dark-Core)
		if (national_hit > 0.05) {
			float nat_alpha = (enable_antialiased_borders ? smoothstep(0.05, 0.70, national_hit) : national_hit) * national_border_color.a;
			vec4 active_nat_color = national_border_color;

			// Mode 1: Spheres of Influence / Blocs
			if (border_rendering_mode == 1) {
				if (bloc_inner_hit > 0.05 && bloc_outer_hit <= 0.05) {
					// Internal alliance border is smoothed & dimmed
					nat_alpha *= 0.30;
					active_nat_color = mix(political_col, national_border_color, 0.30);
				} else {
					// External bloc frontier: amplified glow with bloc signature color
					vec4 bloc_color = get_sphere_glow_color(center_bloc);
					active_nat_color = mix(national_border_color, bloc_color, 0.75);
					nat_alpha = min(nat_alpha * 1.3, 1.0);
				}
			} else if (border_color_mode == 1) {
				// Mode 1: Dual-Hue Ribbon (Country Color Blend)
				vec4 ribbon_col = mix(political_col, national_border_color, 0.45);
				ribbon_col.rgb += national_border_color.rgb * 0.25;
				active_nat_color = mix(ribbon_col, national_border_color, clamp((national_hit - 0.40) * 2.0, 0.0, 1.0));
			} else if (border_color_mode == 2) {
				// Mode 2: High-Contrast Dark Core with Neon Center
				vec4 dark_rim = vec4(0.02, 0.03, 0.04, 0.95);
				active_nat_color = mix(dark_rim, national_border_color, clamp((national_hit - 0.35) * 2.0, 0.0, 1.0));
			}

			final_color = mix(final_color, active_nat_color, nat_alpha);
			// CRT Phosphor Bloom / Luminescence
			final_color.rgb += active_nat_color.rgb * (national_hit * phosphor_glow_intensity);
		}

		// 4.1 Dynamic Sovereignty Focus (Selected / Hovered Country Halo Flare)
		if (focused_country_id > 0 && center_meta.country_id == focused_country_id && national_hit > 0.05) {
			float f_pulse = 0.70 + 0.30 * sin(TIME * focused_border_pulse_speed);
			float f_alpha = (enable_antialiased_borders ? smoothstep(0.05, 0.60, national_hit) : national_hit) * focused_border_color.a * f_pulse;
			final_color = mix(final_color, focused_border_color, f_alpha);
			final_color.rgb += focused_border_color.rgb * (national_hit * phosphor_glow_intensity * 1.6 * f_pulse);
		}

		// 4.2 Fortifications & Tactical Barriers (Crenelated teeth / notches)
		if (enable_fortifications && fort_hit > 0.05 && (national_hit > 0.05 || frontline_hit > 0.05)) {
			vec2 screen_pix = UV * mask_size;
			float fort_period = max(fortification_spacing / zoom_comp, 8.0);
			float fort_val = mod(screen_pix.x + screen_pix.y, fort_period);
			if (fort_val < max(fortification_notch_width / zoom_comp, 2.0)) {
				float fort_alpha = smoothstep(0.05, 0.65, max(national_hit, frontline_hit)) * fortification_color.a;
				final_color = mix(final_color, fortification_color, fort_alpha);
				final_color.rgb += fortification_color.rgb * (phosphor_glow_intensity * 0.95);
			}
		}

		// 5. Active Player Sovereignty Halo Pulse
		if (player_hit > 0.05 && enable_sovereignty_pulse) {
			float sov_pulse = 0.65 + 0.35 * sin(TIME * sovereignty_pulse_speed);
			float sov_alpha = (enable_antialiased_borders ? smoothstep(0.05, 0.65, player_hit) : player_hit) * player_border_glow_color.a * sov_pulse;
			final_color = mix(final_color, player_border_glow_color, sov_alpha);
			final_color.rgb += player_border_glow_color.rgb * (player_hit * sov_pulse * phosphor_glow_intensity * 1.2);
		}

		// 6. Active Combat Frontlines (Dynamic Battle Intensity Strobe)
		if (frontline_hit > 0.05) {
			float strobe_wave = sin(TIME * battle_strobe_speed);
			float strobe_flash = pow(max(0.0, strobe_wave), 2.5);
			float alt_phase = 0.5 + 0.5 * sin(TIME * (battle_strobe_speed * 0.5));
			vec4 active_strobe_col = mix(frontline_border_color, mix(battle_warning_amber, battle_strobe_color, alt_phase), battle_intensity);

			float fl_pulse = 0.65 + 0.35 * sin(TIME * frontline_pulse_speed) + 0.40 * strobe_flash * battle_intensity;
			float fl_alpha = (enable_antialiased_borders ? smoothstep(0.05, 0.65, frontline_hit) : frontline_hit) * active_strobe_col.a * min(fl_pulse, 1.0);
			final_color = mix(final_color, active_strobe_col, fl_alpha);
			final_color.rgb += active_strobe_col.rgb * (frontline_hit * (1.0 + 1.8 * strobe_flash * battle_intensity) * phosphor_glow_intensity * 1.8);
		}

		// 7. DMZ / Smuta Warlord Disputed Lines (Pulsating Red Dashed Warning)
		if (dmz_hit > 0.05) {
			vec2 screen_pix = UV * mask_size;
			float dmz_period = max(dmz_dash_scale / zoom_comp, 12.0);
			float dmz_val = mod(screen_pix.x + screen_pix.y + TIME * 14.0, dmz_period);
			if (dmz_val < dmz_period * 0.55) {
				float dmz_pulse = 0.65 + 0.35 * sin(TIME * dmz_pulse_speed);
				float dmz_alpha = (enable_antialiased_borders ? smoothstep(0.05, 0.65, dmz_hit) : dmz_hit) * dmz_border_color.a * dmz_pulse;
				final_color = mix(final_color, dmz_border_color, dmz_alpha);
				final_color.rgb += dmz_border_color.rgb * (dmz_hit * dmz_pulse * phosphor_glow_intensity * 1.8);
			}
		}
	}

	// --------------------------------------------------------------------------
	// 2.5 REBELLION & UNREST PROCEDURAL DIAGONAL HATCHING
	// --------------------------------------------------------------------------
	if (enable_rebellion_hatching && !center_meta.is_water && center_id > 0) {
		if (reg_data.g >= rebellion_unrest_threshold || (center_meta.is_dmz && reg_data.g > 0.45)) {
			vec2 screen_pix = UV * mask_size;
			float hatch_period = max(hatching_density / zoom_comp, 6.0);
			float hatch_val = mod(screen_pix.x + screen_pix.y - TIME * hatching_speed, hatch_period);
			if (hatch_val < hatch_period * hatching_stripe_ratio) {
				float urgency = clamp((reg_data.g - rebellion_unrest_threshold) / max(0.01, 1.0 - rebellion_unrest_threshold), 0.0, 1.0);
				vec4 hatch_col = mix(strike_hatch_color, rebellion_hatch_color, urgency);
				float hatch_pulse = 0.80 + 0.20 * sin(TIME * 6.0 + float(center_id));
				float h_alpha = hatch_col.a * hatch_pulse;
				final_color = mix(final_color, hatch_col, h_alpha);
				final_color.rgb += hatch_col.rgb * (phosphor_glow_intensity * 0.45 * hatch_pulse);
			}
		}
	}

	// --------------------------------------------------------------------------
	// 3. INTERACTIVE SELECTION & HOVER
	// --------------------------------------------------------------------------
	if (enable_selection_highlight && center_id > 0 && center_id == selected_province_id) {
		final_color = mix(final_color, select_color, select_color.a);
	}

	if (enable_hover_highlight && center_id > 0 && center_id == hovered_province_id) {
		float pulse = 0.5 + 0.5 * sin(TIME * hover_pulse_speed);
		float alpha = hover_color.a * (0.8 + 0.2 * pulse);
		final_color = mix(final_color, hover_color, alpha);
	}

	// --------------------------------------------------------------------------
	// 4. CRT TACTICAL GRID
	// --------------------------------------------------------------------------
	if (enable_tactical_grid && grid_spacing > 4.0) {
		vec2 pixel_coord = UV * mask_size;
		vec2 grid_pos = mod(pixel_coord, grid_spacing);
		if (grid_pos.x < 1.0 || grid_pos.y < 1.0) {
			final_color = mix(final_color, grid_color, grid_color.a);
		}
		// Coordinate Reticle Crosses
		if ((grid_pos.x < 3.0 && grid_pos.y < 3.0) || (grid_pos.x < 3.0 && grid_pos.y > grid_spacing - 3.0)) {
			final_color = mix(final_color, grid_color * 1.5, 0.4);
		}
	}

	// --------------------------------------------------------------------------
	// 5. RADAR RECONNAISSANCE SWEEP
	// --------------------------------------------------------------------------
	if (enable_radar_sweep) {
		vec2 dir = UV - radar_center;
		float dist = length(dir);
		if (dist <= radar_radius) {
			float angle = atan(dir.y, dir.x);
			float sweep_angle = mod(TIME * radar_speed, 6.28318) - 3.14159;
			float diff = mod(sweep_angle - angle + 3.14159, 6.28318) - 3.14159;

			if (diff >= 0.0 && diff < 0.6) {
				float sweep_intensity = (1.0 - (diff / 0.6)) * radar_sweep_color.a;
				float dist_attenuation = smoothstep(radar_radius, 0.0, dist);
				final_color += radar_sweep_color * (sweep_intensity * dist_attenuation);
			}
		}
	}

	// --------------------------------------------------------------------------
	// 6. CRT SCANLINE POST-PROCESSING
	// --------------------------------------------------------------------------
	if (enable_crt_scanlines) {
		float scan = 1.0 - scanline_strength * (0.5 + 0.5 * sin(UV.y * mask_size.y * 3.14159));
		final_color.rgb *= scan;
	}

	COLOR = final_color;
}
