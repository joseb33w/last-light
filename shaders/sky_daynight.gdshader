shader_type sky;
// Dual-panorama crossfade sky (dusk -> night). Both panoramas are linear HDR imported with
// hdr_as_srgb = OFF, so we read raw radiance and pre-encode sRGB to cancel the sky pass's
// mandatory srgb_to_linear (engine bug #83788 workaround), giving correct HDR into the tonemapper.
uniform sampler2D dusk_tex : filter_linear, hint_default_black;
uniform sampler2D night_tex : filter_linear, hint_default_black;
uniform float blend : hint_range(0.0, 1.0) = 0.0;
uniform float exposure : hint_range(0.0, 16.0) = 1.0;

vec3 srgb_enc(vec3 rad) {
	vec3 a = vec3(0.055);
	return mix(rad * 12.92,
		(1.0 + a) * pow(max(rad, vec3(0.0)), vec3(1.0 / 2.4)) - a,
		step(vec3(0.0031308), rad));
}

void sky() {
	vec3 d = normalize(EYEDIR);
	vec2 uv = vec2(atan(d.x, d.z) / (2.0 * PI) + 0.5, acos(clamp(d.y, -1.0, 1.0)) / PI);
	vec3 dusk = texture(dusk_tex, uv).rgb;
	vec3 night = texture(night_tex, uv).rgb;
	vec3 rad = mix(dusk, night, blend) * exposure;
	COLOR = srgb_enc(rad);
}
