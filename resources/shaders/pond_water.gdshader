shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_schlick_ggx;

// The pond used to be a flat translucent plane: readable as water only because
// it was blue. Two crossed sine waves give it moving highlights and a normal
// that catches the sun, with no texture asset and no per-frame script cost.
uniform vec4 water_color : source_color = vec4(0.10, 0.33, 0.46, 0.88);
uniform vec3 shallow_color : source_color = vec3(0.26, 0.53, 0.55);
uniform float ripple_scale : hint_range(0.1, 12.0) = 1.5;
uniform float ripple_speed : hint_range(0.0, 4.0) = 0.45;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	float t = TIME * ripple_speed;
	float a = sin(p.x * ripple_scale + t) * cos(p.y * ripple_scale * 0.83 - t * 0.72);
	float b = sin((p.x + p.y) * ripple_scale * 1.7 - t * 1.25);
	float ripple = a * 0.7 + b * 0.3;

	vec3 n = normalize(vec3(
		-cos(p.x * ripple_scale + t) * 0.16,
		1.0,
		sin(p.y * ripple_scale * 0.83 - t * 0.72) * 0.14
	));
	NORMAL = n;
	ALBEDO = mix(water_color.rgb, shallow_color, clamp(ripple * 0.14 + 0.16, 0.0, 0.4));
	ALPHA = water_color.a;
	ROUGHNESS = 0.13;
	METALLIC = 0.0;
	SPECULAR = 0.85;
	EMISSION = water_color.rgb * (ripple * 0.02 + 0.01);
}
