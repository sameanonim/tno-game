shader_type canvas_item;

/**
 * shaders/terminal_map.gdshader
 * ==============================================================================
 * 1960-70s MILITARY CRT TERMINAL STRATEGIC MAP (TNO COLD WAR WAR ROOM)
 * ==============================================================================
 * High-performance 2D CanvasItem shader for Grand Strategy map rendering:
 * 1. O(1) integer 24-bit province ID decoding from lossless raster mask.
 * 2. Hierarchical Edge Detection (Kernel 4-way/8-way):
 *    - National sovereign borders (thick 2-3px, high phosphor brightness).
 *    - State / Regional boundaries (medium width, semi-transparent).
 *    - Tactical province divisions (thin, dynamic fade out at macro zoom).
 *    - High-contrast coastlines and maritime shelves.
 * 3. Volumetric Cell Inner Falloff (Political Vignette): edges glow +35% brighter,
 *    center smoothly dims by ~35%, recreating CRT phosphor display cells.
 * 4. Topographical Isohypses: contour lines via procedural modulo on 8-bit heightmap.
 * 5. Biome & Terrain Dithering: Bayer 4x4 matrix phosphor half-toning.
 * 6. Tactical Hydro-Barriers: rivers with neon phosphor luminescence.
 * 7. Multi-Mode Data Visualization (Political, Economy/IC, Unrest, Spheres).
 * 8. Rebellion Procedural Diagonal Hatching on high-unrest territories.
 * 9. Frontline Combat Strobe modulation based on battle intensity.
 * 10. Sinusoidal hover/selection pulsing & CRT phosphor scanline rasterization.
 */

// ==============================================================================
// 1. UNIFORMS & SAMPLERS
// ==============================================================================
uniform sampler2D provinces_mask : filter_nearest, repeat_disable;
uniform sampler2D lut_palette : filter_nearest, repeat_disable;
uniform sampler2D data_lut_texture : filter_nearest, repeat_disable;
uniform sampler2D height_map : filter_linear, repeat_disable;
uniform sampler2D rivers_mask : filter_nearest, repeat_disable;
uniform sampler2D ownership_lut : filter_nearest, repeat_disable;

// Map Modes: 0 = Political, 1 = Economy (IC), 2 = Unrest, 3 = Spheres of Influence
uniform int map_mode = 0;
uniform int hovered_province_id = 0;
uniform int selected_province_id = 0;
uniform float zoom_level = 1.0;
uniform vec3 phosphor_color : source_color = vec3(0.20, 1.00, 0.40); // Base terminal glow (#33ff66)

// ==============================================================================
// 2. BORDER HIERARCHY & STYLING
// ==============================================================================
uniform bool enable_borders = true;
uniform float border_scale : hint_range(0.5, 3.0, 0.1) = 1.0;
uniform float national_border_width : hint_range(0.5, 6.0, 0.1) = 2.4;
uniform float state_border_width : hint_range(0.2, 4.0, 0.1) = 1.2;
uniform float province_border_width : hint_range(0.1, 2.5, 0.1) = 0.6;
uniform float coastline_width : hint_range(0.5, 5.0, 0.1) = 1.8;
uniform float province_border_zoom_threshold : hint_range(0.5, 4.0, 0.1) = 1.5;

uniform vec4 national_border_color : source_color = vec4(0.25, 1.00, 0.45, 0.95);
uniform vec4 state_border_color : source_color = vec4(0.15, 0.70, 0.85, 0.65);
uniform vec4 province_border_color : source_color = vec4(0.18, 0.45, 0.38, 0.35);
uniform vec4 coastline_color : source_color = vec4(0.00, 0.90, 1.00, 0.95);

// ==============================================================================
// 3. INNER FALLOFF (POLITICAL VIGNETTE) & CRT AESTHETICS
// ==============================================================================
uniform bool enable_political_vignette = true;
uniform bool enable_inner_falloff = true;
uniform float inner_falloff_dim : hint_range(0.0, 0.6, 0.02) = 0.32;
uniform float border_glow_boost : hint_range(1.0, 2.0, 0.05) = 1.35;

uniform bool enable_isohypses = true;
uniform float isohypse_density : hint_range(5.0, 50.0, 1.0) = 20.0;
uniform float isohypse_width : hint_range(0.01, 0.20, 0.01) = 0.08;
uniform vec3 isohypse_color : source_color = vec3(0.06, 0.28, 0.16);

uniform bool enable_biome_dithering = true;
uniform float dither_intensity : hint_range(0.0, 0.5, 0.02) = 0.18;

uniform bool enable_rivers = true;
uniform vec4 river_color : source_color = vec4(0.08, 0.85, 1.00, 0.95);
uniform float river_glow_intensity : hint_range(0.0, 2.5, 0.05) = 1.15;

// Dynamic Battle Strobe & Rebellion Hatching
uniform float battle_intensity : hint_range(0.0, 1.0, 0.02) = 0.0;
uniform bool enable_rebellion_hatching = true;
uniform float rebellion_unrest_threshold : hint_range(0.5, 0.95, 0.05) = 0.70;

uniform bool enable_crt_scanlines = true;
uniform float scanline_strength : hint_range(0.0, 0.25, 0.01) = 0.05;

// ==============================================================================
// 4. BAYER 4x4 MATRIX (HALF-TONING FOR BIOMES)
// ==============================================================================
const float bayer4[16] = float[16](
	 0.0 / 16.0,  8.0 / 16.0,  2.0 / 16.0, 10.0 / 16.0,
	12.0 / 16.0,  4.0 / 16.0, 14.0 / 16.0,  6.0 / 16.0,
	 3.0 / 16.0, 11.0 / 16.0,  1.0 / 16.0,  9.0 / 16.0,
	15.0 / 16.0,  7.0 / 16.0, 13.0 / 16.0,  5.0 / 16.0
);

// ==============================================================================
// 5. HELPER FUNCTIONS
// ==============================================================================

/**
 * Decodes 24-bit Province ID from RGB mask texel:
 * ID = R | (G << 8) | (B << 16)
 */
int decode_province_id(vec4 col) {
	ivec3 rgb = ivec3(round(col.rgb * 255.0));
	return rgb.r | (rgb.g << 8) | (rgb.b << 16);
}

/**
 * Maps 1D Province ID to 1D/2D LUT texture coordinates.
 */
ivec2 get_lut_coords(int id, ivec2 lut_size) {
	if (lut_size.y <= 1) {
		return ivec2(id, 0);
	}
	return ivec2(id % lut_size.x, id / lut_size.x);
}

/**
 * Samples political color from lut_palette.
 */
vec4 sample_political_color(int id) {
	if (id <= 0) {
		return vec4(0.02, 0.04, 0.06, 1.0); // Ocean / Unclaimed
	}
	ivec2 lut_size = textureSize(lut_palette, 0);
	if (lut_size.x <= 0 || lut_size.y <= 0) {
		return vec4(0.12, 0.14, 0.16, 1.0);
	}
	ivec2 coord = get_lut_coords(id, lut_size);
	if (coord.y < lut_size.y) {
		return texelFetch(lut_palette, coord, 0);
	}
	return vec4(0.12, 0.14, 0.16, 1.0);
}

/**
 * Samples scalar data from data_lut_texture:
 * R = Industrial Capacity (0..1)
 * G = Unrest / Secession Risk (0..1)
 * B = Terrain Biome / Infra (0..1)
 * A = Sphere of Influence Code (0..1)
 */
vec4 sample_scalar_data(int id) {
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
 * Samples ownership & state hierarchy metadata.
 * Returns: ivec4(country_id, state_id, is_water, is_frontline)
 */
ivec4 sample_province_hierarchy(int id) {
	if (id <= 0) return ivec4(0, 0, 1, 0);
	ivec2 lut_size = textureSize(ownership_lut, 0);
	if (lut_size.x > 0 && lut_size.y > 0) {
		ivec2 coord = get_lut_coords(id, lut_size);
		if (coord.y < lut_size.y) {
			vec4 raw = texelFetch(ownership_lut, coord, 0);
			ivec4 b = ivec4(round(raw * 255.0));
			int cid = b.r;
			int sid = b.g | (b.b << 8);
			int flags = b.a;
			int water = (flags & 1);
			int frontline = ((flags & 4) != 0) ? 1 : 0;
			return ivec4(cid, sid, water, frontline);
		}
	}
	// Fallback when ownership_lut is absent
	vec4 p_col = sample_political_color(id);
	int pseudo_owner = int(round(p_col.r * 100.0 + p_col.g * 10.0 + p_col.b * 1.0));
	return ivec4(pseudo_owner, id, (id <= 0 ? 1 : 0), 0);
}

// ==============================================================================
// 6. FRAGMENT SHADER LOGIC
// ==============================================================================
void fragment() {
	vec2 tex_size = vec2(textureSize(provinces_mask, 0));
	vec2 pixel_size = 1.0 / tex_size;

	// 1. Center province sampling
	vec4 center_raw = texture(provinces_mask, UV);
	int center_id = decode_province_id(center_raw);
	ivec4 center_hier = sample_province_hierarchy(center_id);
	int center_owner = center_hier.x;
	int center_state = center_hier.y;
	bool center_is_water = (center_hier.z != 0) || (center_id <= 0);
	bool center_is_frontline = (center_hier.w != 0);

	// 2. Base Color Resolution by Map Mode
	vec4 base_color = vec4(0.02, 0.05, 0.08, 1.0); // Maritime dark abyss
	vec4 data_val = vec4(0.0);

	if (!center_is_water) {
		data_val = sample_scalar_data(center_id);

		switch (map_mode) {
			case 0: { // Political Sovereignty
				base_color = sample_political_color(center_id);
				break;
			}
			case 1: { // Economic / Industrial Capacity (IC) Heatmap
				float ic = clamp(data_val.r, 0.0, 1.0);
				vec3 cold_ic = vec3(0.04, 0.18, 0.10);
				vec3 mid_ic  = vec3(0.15, 0.75, 0.35);
				vec3 hot_ic  = vec3(0.95, 0.85, 0.20);
				vec3 ic_rgb = mix(cold_ic, mid_ic, smoothstep(0.0, 0.5, ic));
				ic_rgb = mix(ic_rgb, hot_ic, smoothstep(0.5, 1.0, ic));
				base_color = vec4(ic_rgb, 1.0);
				break;
			}
			case 2: { // Unrest & Secession Threat Heatmap
				float unrest = clamp(data_val.g, 0.0, 1.0);
				vec3 calm_rgb = vec3(0.08, 0.16, 0.14);
				vec3 warn_rgb = vec3(0.90, 0.65, 0.10);
				vec3 alert_rgb = vec3(0.95, 0.15, 0.10);
				vec3 u_rgb = mix(calm_rgb, warn_rgb, smoothstep(0.1, 0.6, unrest));
				u_rgb = mix(u_rgb, alert_rgb, smoothstep(0.6, 1.0, unrest));
				if (unrest >= 0.70) {
					float u_pulse = 0.5 + 0.5 * sin(TIME * 6.0);
					u_rgb = mix(u_rgb, vec3(1.0, 0.2, 0.1), 0.3 * u_pulse);
				}
				base_color = vec4(u_rgb, 1.0);
				break;
			}
			case 3: { // Spheres of Influence & Blocs
				float sphere = data_val.a;
				if (sphere > 0.85) {
					base_color = vec4(0.85, 0.20, 0.20, 1.0); // Russian / Sovereign Core (Crimson)
				} else if (sphere > 0.65) {
					base_color = vec4(0.90, 0.48, 0.15, 1.0); // Co-Prosperity Sphere (Gold/Amber)
				} else if (sphere > 0.42) {
					base_color = vec4(0.38, 0.42, 0.48, 1.0); // Unity-Pakt (Steel Gray)
				} else if (sphere > 0.28) {
					base_color = vec4(0.15, 0.68, 0.45, 1.0); // Triumvirate (Emerald Green)
				} else if (sphere > 0.12) {
					base_color = vec4(0.20, 0.52, 0.90, 1.0); // OFN (Atlantic Blue)
				} else {
					base_color = vec4(0.12, 0.14, 0.15, 1.0); // Non-aligned
				}
				break;
			}

			default:
				base_color = sample_political_color(center_id);
				break;
		}
	}

	// 3. Hierarchical Edge Detection & Volumetric Inner Falloff
	vec2 offsets[4] = vec2[](
		vec2( 1.0,  0.0),
		vec2(-1.0,  0.0),
		vec2( 0.0,  1.0),
		vec2( 0.0, -1.0)
	);

	bool is_national_edge = false;
	bool is_state_edge = false;
	bool is_province_edge = false;
	bool is_coast_edge = false;

	float same_province_count = 0.0;
	float effective_thickness = max(1.0, border_scale);

	for (int i = 0; i < 4; i++) {
		vec2 sample_uv = UV + offsets[i] * pixel_size * effective_thickness;
		vec4 n_raw = texture(provinces_mask, sample_uv);
		int n_id = decode_province_id(n_raw);

		if (n_id == center_id) {
			same_province_count += 1.0;
		} else {
			ivec4 n_hier = sample_province_hierarchy(n_id);
			bool n_is_water = (n_hier.z != 0) || (n_id <= 0);

			if (center_is_water != n_is_water) {
				is_coast_edge = true;
			} else if (!center_is_water) {
				if (center_owner != n_hier.x) {
					is_national_edge = true;
				} else if (center_state != n_hier.y) {
					is_state_edge = true;
				} else {
					is_province_edge = true;
				}
			}
		}
	}

	// Volumetric cell gradient (Inner Falloff / Political Vignette)
	float edge_proximity = 1.0 - (same_province_count / 4.0);
	if ((enable_inner_falloff || enable_political_vignette) && !center_is_water) {
		float cell_vignette = mix(1.0 - inner_falloff_dim, border_glow_boost, clamp(edge_proximity * 1.4, 0.0, 1.0));
		base_color.rgb *= cell_vignette;
	}

	// 4. Biome Matrix Dithering (Bayer 4x4)
	if (enable_biome_dithering && !center_is_water) {
		ivec2 p_coord = ivec2(int(FRAGCOORD.x) % 4, int(FRAGCOORD.y) % 4);
		float dither = bayer4[p_coord.y * 4 + p_coord.x] - 0.5;
		float terrain_factor = mix(0.5, 1.2, data_val.b);
		base_color.rgb += base_color.rgb * (dither * dither_intensity * terrain_factor);
	}

	// 5. Procedural Rebellion Hatching (Diagonal Hazard Stripes)
	if (enable_rebellion_hatching && !center_is_water && data_val.g >= rebellion_unrest_threshold) {
		float hatch_coord = (FRAGCOORD.x + FRAGCOORD.y) * 0.15 + (TIME * 4.0);
		float hatch = step(0.65, fract(hatch_coord));
		vec3 hatch_col = vec3(0.95, 0.18, 0.12);
		base_color.rgb = mix(base_color.rgb, hatch_col, hatch * 0.45);
	}

	// 6. Topographical Isohypses (Contour Lines from Heightmap)
	if (enable_isohypses) {
		float elevation = texture(height_map, UV).r;
		float iso_mod = mod(elevation * isohypse_density, 1.0);
		float isohypse_line = smoothstep(isohypse_width, isohypse_width * 0.35, iso_mod);
		vec3 iso_tint = isohypse_color * (center_is_water ? 0.3 : 1.0);
		base_color.rgb += iso_tint * (isohypse_line * 0.85);
	}

	// 7. Hydrography & River Barriers (Neon Luminescence)
	if (enable_rivers) {
		float river_val = texture(rivers_mask, UV).r;
		if (river_val > 0.05) {
			float r_intensity = clamp(river_val * 1.5, 0.4, 1.5);
			float flow_pulse = 1.0 + 0.25 * sin(TIME * 3.0 + UV.x * 25.0 + UV.y * 25.0);
			vec3 r_glow = river_color.rgb * (r_intensity * flow_pulse * river_glow_intensity);
			base_color.rgb = mix(base_color.rgb, r_glow, smoothstep(0.05, 0.3, river_val));
		}
	}

	// 8. Dynamic Battle Intensity Strobe (Active Frontlines)
	if (battle_intensity > 0.0 && center_is_frontline) {
		float strobe = 0.5 + 0.5 * sin(TIME * 12.0 * battle_intensity);
		vec3 strobe_col = mix(vec3(1.0, 0.7, 0.1), vec3(1.0, 0.15, 0.1), strobe);
		base_color.rgb = mix(base_color.rgb, strobe_col, 0.35 * battle_intensity);
	}

	// 9. Interactive Hover & Selection Pulsing
	if (center_id > 0) {
		if (center_id == hovered_province_id) {
			float hover_wave = 0.5 + 0.5 * sin(TIME * 6.0);
			base_color.rgb += phosphor_color * (0.32 * hover_wave);
		}
		if (center_id == selected_province_id) {
			float select_wave = 0.7 + 0.3 * sin(TIME * 4.0);
			base_color.rgb = mix(base_color.rgb, phosphor_color * 1.35, 0.38 * select_wave);
		}
	}

	// 10. Border Overlay Composite (Hierarchy Order)
	if (enable_borders) {
		if (is_coast_edge) {
			base_color = mix(base_color, coastline_color, coastline_color.a);
		} else if (is_national_edge) {
			vec4 nat_col = national_border_color;
			nat_col.rgb *= 1.35;
			base_color = mix(base_color, nat_col, nat_col.a);
		} else if (is_state_edge) {
			base_color = mix(base_color, state_border_color, state_border_color.a);
		} else if (is_province_edge && zoom_level >= province_border_zoom_threshold) {
			float zoom_fade = smoothstep(province_border_zoom_threshold, province_border_zoom_threshold + 0.5, zoom_level);
			base_color = mix(base_color, province_border_color, province_border_color.a * zoom_fade);
		}
	}

	// 11. CRT Raster Scanline Modulation
	if (enable_crt_scanlines) {
		float scanline = 1.0 - scanline_strength * (0.5 + 0.5 * sin(FRAGCOORD.y * 3.14159));
		base_color.rgb *= scanline;
	}

	COLOR = vec4(base_color.rgb, 1.0);
}
