shader_type canvas_item;

// The frost bands along the screen edges, as fractions of the screen:
// left, top, right, bottom. See SnowAccumulation (scenes/game/core).
uniform vec4 edges = vec4(0.0);
uniform vec2 screen_size = vec2(1920.0, 1080.0);

// The opacity at the very edge; the frost is translucent so that the player
// can still see through it.
uniform float max_alpha = 0.78;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x),
		u.y
	);
}

float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 4; i++) {
		value += amplitude * noise(p);
		p *= 2.0;
		amplitude *= 0.5;
	}
	return value;
}

float band(float depth, float distance_to_edge, float wobble) {
	if (depth < 0.001) {
		return 0.0;
	}
	float edge = depth + wobble * depth;
	return 1.0 - smoothstep(edge * 0.35, edge, distance_to_edge);
}

void fragment() {
	float aspect = screen_size.x / screen_size.y;
	float n = fbm(UV * vec2(aspect, 1.0) * 6.0);
	float wobble = (n - 0.5) * 0.5;

	float coverage = band(edges.x, UV.x, wobble);
	coverage = max(coverage, band(edges.y, UV.y, wobble));
	coverage = max(coverage, band(edges.z, 1.0 - UV.x, wobble));
	coverage = max(coverage, band(edges.w, 1.0 - UV.y, wobble));

	float sparkle = step(0.985, hash(floor(UV * screen_size / 3.0))) * 0.6;
	vec3 frost = mix(vec3(0.8, 0.89, 1.0), vec3(1.0), clamp(n * 0.8 + sparkle, 0.0, 1.0));
	COLOR = vec4(frost, coverage * max_alpha);
}
