shader_type canvas_item;

/**
 * 1960s-70s Military Bunker CRT Terminal Post-Processing Shader (Godot 4)
 * ------------------------------------------------------------------------
 * - CRT Barrel / Lens Curvature
 * - Horizontal Scanlines & Mask
 * - Chromatic Aberration (RGB Fringe)
 * - Phosphor Green/Cyan/Amber tint & Glow
 * - Screen Vignette & subtle analog flicker
 */

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

// 1. Distortion & Curvature
uniform float curvature : hint_range(0.0, 0.25, 0.01) = 0.04;
uniform float vignette_strength : hint_range(0.0, 2.0, 0.05) = 0.85;
uniform float aspect_ratio : hint_range(0.5, 3.5, 0.01) = 1.777778;

// 2. Scanlines & Grid
uniform float scanline_count : hint_range(100.0, 2160.0, 10.0) = 540.0;
uniform float scanline_intensity : hint_range(0.0, 1.0, 0.05) = 0.18;

// 3. Chromatic Aberration & Glow
uniform float chromatic_aberration : hint_range(0.0, 0.02, 0.001) = 0.003;
uniform vec4 phosphor_tint : source_color = vec4(0.95, 1.0, 0.98, 1.0);
uniform float brightness_boost : hint_range(0.8, 1.5, 0.05) = 1.08;

// 4. Analog Noise & Flicker
uniform float flicker_speed : hint_range(0.0, 30.0, 1.0) = 8.0;
uniform float flicker_strength : hint_range(0.0, 0.1, 0.005) = 0.015;
uniform float phosphor_noise_strength : hint_range(0.0, 0.1, 0.005) = 0.025;
uniform float beam_sweep_speed : hint_range(0.0, 5.0, 0.1) = 0.8;
uniform float beam_sweep_intensity : hint_range(0.0, 0.2, 0.01) = 0.04;


float pseudo_noise(vec2 co) {
    return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453);
}

vec2 curve_uv(vec2 uv) {
    vec2 delta = uv - 0.5;
    // Коррекция соотношения сторон для сохранения сферической формы линзы на 21:9, 16:10 и 4:3
    delta.x *= (aspect_ratio / 1.7777778);
    float dist_sqr = dot(delta, delta);
    return uv + (uv - 0.5) * (dist_sqr * curvature);
}

void fragment() {
    vec2 curved_uv = curve_uv(SCREEN_UV);

    // Render black outside tube borders
    if (curved_uv.x < 0.0 || curved_uv.x > 1.0 || curved_uv.y < 0.0 || curved_uv.y > 1.0) {
        COLOR = vec4(0.02, 0.03, 0.03, 1.0);
    } else {
        // Chromatic aberration (RGB shift)
        float r = texture(screen_texture, curved_uv + vec2(chromatic_aberration, 0.0)).r;
        float g = texture(screen_texture, curved_uv).g;
        float b = texture(screen_texture, curved_uv - vec2(chromatic_aberration, 0.0)).b;
        vec3 col = vec3(r, g, b);

        // Scanlines
        float scanline = sin(curved_uv.y * scanline_count * 3.14159);
        col -= scanline * scanline_intensity * 0.5;

        // Phosphor Grain / Analog Noise
        float noise = (pseudo_noise(curved_uv + vec2(TIME * 0.1, TIME * 0.05)) - 0.5) * phosphor_noise_strength;
        col += noise;

        // CRT Beam Sweep Line (Phosphor persistence sweep)
        float beam_pos = fract(TIME * beam_sweep_speed);
        float beam_dist = abs(curved_uv.y - beam_pos);
        if (beam_dist < 0.06) {
            float sweep = (1.0 - (beam_dist / 0.06)) * beam_sweep_intensity;
            col += sweep;
        }

        // Vignette
        vec2 uv_offset = (curved_uv - 0.5) * 2.0;
        float vignette = 1.0 - dot(uv_offset, uv_offset) * (vignette_strength * 0.35);
        col *= clamp(vignette, 0.0, 1.0);

        // Subtle CRT flicker
        float flicker = 1.0 + sin(TIME * flicker_speed) * flicker_strength;
        col *= flicker;

        // Tint & Brightness
        col *= phosphor_tint.rgb * brightness_boost;

        COLOR = vec4(col, 1.0);
    }
}
