shader_type canvas_item;

// Draw a soft, glowing ellipse in the quad of a head: a crisp core ring, a
// wide glow around it, a faint shadow just outside (so that the ring stands out
// on the white snow, too) and a light shimmer which runs around the ring. The
// quad is the ellipse enlarged by `margin`; COLOR (the modulate of the draw
// call) gives the color, and its alpha the strength.

uniform float margin = 1.4;
uniform float core_width = 0.05;
uniform float glow_width = 0.22;
uniform float shimmer_speed = 1.6;
uniform vec4 shadow_color : source_color = vec4(0.12, 0.2, 0.38, 0.35);

void fragment() {
    vec2 p = (UV * 2.0 - 1.0) * margin;
    float r = length(p);
    float core = exp(-pow((r - 1.0) / core_width, 2.0));
    float glow = exp(-pow((r - 1.0) / glow_width, 2.0));
    float shadow = exp(-pow((r - 1.09) / 0.05, 2.0));
    float angle = atan(p.y, p.x);
    float shimmer = 0.65 + 0.35 * sin(angle * 2.0 - TIME * shimmer_speed);

    float light = core * shimmer + glow * 0.45;
    float dark = shadow * shadow_color.a * (1.0 - core);
    vec3 ring = mix(COLOR.rgb, vec3(1.0), core * 0.35);
    float alpha = clamp(light + dark, 0.0, 1.0);
    vec3 color = mix(shadow_color.rgb, ring, light / max(light + dark, 1e-4));
    COLOR = vec4(color, alpha * COLOR.a);
}
