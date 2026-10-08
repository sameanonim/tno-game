shader_type canvas_item;

// TNO Focus Perimeter Glow Shader
// Creates a running neon beam around the border of the active focus node.

uniform vec4 border_color : source_color = vec4(0.2, 0.9, 0.4, 1.0);
uniform vec4 glow_color : source_color = vec4(0.0, 1.0, 0.6, 1.0);
uniform vec4 bg_color : source_color = vec4(0.02, 0.05, 0.03, 0.85);
uniform float border_width : hint_range(0.005, 0.1) = 0.025;
uniform float corner_radius : hint_range(0.0, 0.2) = 0.05;
uniform float beam_length : hint_range(0.05, 0.5) = 0.25;
uniform float speed : hint_range(0.1, 5.0) = 1.0;
uniform bool is_active = false;
uniform bool is_completed = false;

// Calculate distance to rounded rectangle border
float rounded_box_dist(vec2 p, vec2 b, float r) {
    vec2 q = abs(p) - b + vec2(r);
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

// Map 2D UV around rectangular perimeter to 1D scalar in [0, 1]
float perimeter_coord(vec2 uv) {
    if (uv.y <= 0.05) return uv.x * 0.25; // Top edge: 0.0 to 0.25
    if (uv.x >= 0.95) return 0.25 + uv.y * 0.25; // Right edge: 0.25 to 0.5
    if (uv.y >= 0.95) return 0.5 + (1.0 - uv.x) * 0.25; // Bottom edge: 0.5 to 0.75
    return 0.75 + (1.0 - uv.y) * 0.25; // Left edge: 0.75 to 1.0
}

void fragment() {
    vec2 uv = UV;
    vec2 p = uv - vec2(0.5);
    vec2 half_size = vec2(0.5) - vec2(border_width * 0.5);
    float d = rounded_box_dist(p, half_size, corner_radius);

    // Interior vs Border
    float border_mask = smoothstep(0.0, 0.005, abs(d) - border_width * 0.5);
    vec4 final_color = bg_color;

    if (d < 0.0) {
        // Interior scanline effect
        float scanline = sin(uv.y * 120.0 + TIME * 2.0) * 0.04;
        final_color.rgb += vec3(scanline);
    }

    if (border_mask < 1.0) {
        float edge_factor = 1.0 - border_mask;
        vec4 edge_col = border_color;

        if (is_completed) {
            edge_col = vec4(0.85, 0.75, 0.2, 1.0); // Gold for completed
        }

        if (is_active) {
            float p_coord = perimeter_coord(uv);
            float beam_pos = fract(TIME * speed * 0.5);
            float dist_to_beam = abs(fract(p_coord - beam_pos + 0.5) - 0.5);
            float beam_intensity = smoothstep(beam_length, 0.0, dist_to_beam);

            edge_col = mix(edge_col, glow_color * 1.5, beam_intensity);
            final_color = mix(final_color, edge_col, edge_factor);
        } else {
            final_color = mix(final_color, edge_col, edge_factor * 0.8);
        }
    }

    COLOR = final_color;
}
