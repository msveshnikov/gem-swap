shader_type canvas_item;
// Gem sprite: white flash, diagonal shine sweep, and a hue-cycling tint for the prism.

uniform float flash = 0.0;
uniform float shine = -1.0;     // sweep position -0.5..1.5, < -0.9 = off
uniform float rainbow = 0.0;
uniform float frames = 8.0;
uniform float dim = 0.0;

vec3 hsv2rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(0.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	vec2 luv = vec2(fract(UV.x * frames), UV.y);
	if (rainbow > 0.0) {
		float ang = atan(luv.y - 0.5, luv.x - 0.5) / 6.2831 + TIME * 0.35;
		vec3 rb = hsv2rgb(vec3(fract(ang), 0.55, 1.0));
		c.rgb = mix(c.rgb, c.rgb * rb * 1.35, rainbow);
	}
	if (shine > -0.9) {
		float d = (luv.x + luv.y) * 0.5 - shine;
		float band = smoothstep(0.09, 0.0, abs(d));
		c.rgb += vec3(1.0) * band * 0.75 * c.a;
	}
	c.rgb = mix(c.rgb, vec3(1.0), flash);
	c.rgb *= 1.0 - dim;
	COLOR = c * COLOR;
}
