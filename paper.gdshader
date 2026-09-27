shader_type canvas_item;
render_mode unshaded;

// 宣纸质感：暖色渐变 + 云纹 + 细颗粒 + 纸纤维 + 做旧晕影。
// 所有参数都可调，便于在封面与书页上复用同一材质。

uniform vec4 paper_top : source_color = vec4(0.949, 0.898, 0.784, 1.0);
uniform vec4 paper_bottom : source_color = vec4(0.886, 0.824, 0.686, 1.0);
uniform float cloud_strength : hint_range(0.0, 0.15) = 0.035;
uniform float grain_strength : hint_range(0.0, 0.25) = 0.055;
uniform float fiber_strength : hint_range(0.0, 0.10) = 0.014;
uniform float vignette_strength : hint_range(0.0, 0.50) = 0.13;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 345.45));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	vec2 uv = UV;
	vec3 col = mix(paper_top.rgb, paper_bottom.rgb, smoothstep(0.0, 1.0, uv.y));

	// 云纹：大尺度明暗，模拟纸张吸墨不匀
	float cloud = noise(uv * 5.0) * 0.6 + noise(uv * 11.0) * 0.4;
	col += (cloud - 0.5) * cloud_strength;

	// 细颗粒
	col -= (noise(uv * 380.0) - 0.5) * grain_strength;

	// 横向纸纤维
	float fiber = sin(uv.y * 820.0 + noise(uv * 24.0) * 7.0);
	col -= (fiber * 0.5 + 0.5) * fiber_strength;

	// 四周做旧晕影
	vec2 d = uv - 0.5;
	col -= dot(d, d) * vignette_strength;

	COLOR = vec4(clamp(col, vec3(0.0), vec3(1.0)), 1.0);
}
