shader_type canvas_item;
// Painted backdrops (2:3 portrait art). Portrait screens: cover. Wide screens: the whole painting in the middle over a
// mirrored, softened continuation of itself. A slow drift keeps it alive; `mixv` cross-fades from the previous painting.

uniform sampler2D tex_a : filter_linear_mipmap, repeat_disable;   // previous
uniform sampler2D tex_b : filter_linear_mipmap, repeat_disable;   // current
uniform float mixv = 1.0;
uniform vec2 screen = vec2(720.0, 1280.0);
uniform float img_aspect = 0.6667;
uniform float dim = 0.0;
uniform vec4 tint : source_color = vec4(1.0);

vec3 painting(sampler2D t, vec2 uv, float zoom, vec2 drift) {
	float sa = screen.x / screen.y;
	vec2 c = (uv - 0.5) / zoom + drift;
	// cover
	vec2 cuv = c;
	if (sa > img_aspect) cuv.y *= img_aspect / sa; else cuv.x *= sa / img_aspect;
	cuv += 0.5;
	vec3 cover = texture(t, cuv).rgb;
	// wide: contain + blurred cover behind
	vec2 kuv = (uv - 0.5) / zoom + drift;
	kuv.x *= sa / img_aspect;
	kuv += 0.5;
	// outside the painting: its mirror image, softened and a little darker, so the frame continues to the screen edge
	vec2 muv = vec2(1.0 - abs(mod(kuv.x, 2.0) - 1.0), clamp(kuv.y, 0.0, 1.0));
	float side = clamp(max(-kuv.x, kuv.x - 1.0) * 3.0, 0.0, 1.0);
	vec3 mirror = textureLod(t, muv, 1.5 + 2.0 * side).rgb * (0.82 - 0.2 * side);
	vec3 sharp = texture(t, clamp(kuv, 0.0, 1.0)).rgb;
	float inside = smoothstep(-0.04, 0.05, kuv.x) * smoothstep(1.04, 0.95, kuv.x);
	vec3 wide = mix(mirror, sharp, inside);
	float w = smoothstep(img_aspect * 1.2, img_aspect * 1.6, sa);
	return mix(cover, wide, w);
}

void fragment() {
	float tm = TIME * 0.05;
	float zoom = 1.035 + 0.025 * sin(tm);
	vec2 drift = vec2(sin(tm * 0.7), cos(tm * 0.9)) * 0.008;
	vec3 a = painting(tex_a, UV, zoom, drift);
	vec3 b = painting(tex_b, UV, zoom, drift);
	vec3 col = mix(a, b, mixv);
	// soft vignette, plus the per-screen dim that keeps the gems readable
	vec2 d = UV - 0.5;
	col *= 1.0 - 0.35 * dot(d, d) * 2.0;
	col *= 1.0 - dim;
	COLOR = vec4(col * tint.rgb, 1.0);
}
