// Shared weathering helpers (wave B "materials"). Original project code.
// weather_masks.png channels: R broad blotch, G mid grime, B crack network,
// A vertical streak noise. All tile seamlessly; sample at unrelated scales.
uniform sampler2D weather_masks : filter_linear_mipmap_anisotropic, repeat_enable;

float w_hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 w_rot(vec2 p, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(c * p.x - s * p.y, s * p.x + c * p.y);
}

vec4 w_mask(vec2 uv) {
	return texture(weather_masks, uv);
}

float w_gauss(float x, float sigma) {
	return exp(-(x * x) / (2.0 * sigma * sigma));
}
