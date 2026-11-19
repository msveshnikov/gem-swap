shader_type canvas_item;
// Procedural, animated world backdrops (one style per world). Applied to a full-screen ColorRect.

uniform int style = 0;
uniform vec2 aspect = vec2(0.5625, 1.0);   // width/height of the screen, height = 1
uniform float fade = 1.0;
uniform vec4 tint : source_color = vec4(0.7, 0.5, 1.0, 1.0);

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 5; i++) { v += a * noise(p); p = p * 2.03 + vec2(1.7, 9.2); a *= 0.5; }
	return v;
}
float stars(vec2 p, float dens, float t) {
	vec2 g = floor(p * dens);
	vec2 f = fract(p * dens) - 0.5;
	float h = hash(g);
	if (h > 0.9) {
		vec2 o = vec2(hash(g + 3.1), hash(g + 7.7)) - 0.5;
		float d = length(f - o * 0.6);
		float tw = 0.5 + 0.5 * sin(t * (1.0 + h * 3.0) + h * 40.0);
		return smoothstep(0.08, 0.0, d) * tw + smoothstep(0.25, 0.0, d) * 0.15 * tw;
	}
	return 0.0;
}
// sharp crystal spikes rising from a baseline; returns 0..1 coverage and edge glow
vec2 spikes(float x, float y, float scale, float seed, float height) {
	float cx = x * scale + seed;
	float id = floor(cx);
	float fx = fract(cx) - 0.5;
	float hgt = height * (0.35 + 0.65 * hash(vec2(id, seed)));
	float wdt = 0.28 + 0.18 * hash(vec2(id + 1.0, seed));
	float lean = (hash(vec2(id, seed + 2.0)) - 0.5) * 0.5;
	float edge = abs(fx - lean * (y / max(hgt, 0.001))) - wdt * (1.0 - y / max(hgt, 0.001));
	float cov = step(edge, 0.0) * step(y, hgt);
	float glow = smoothstep(0.06, 0.0, abs(edge)) * step(y, hgt);
	return vec2(cov, glow);
}

void fragment() {
	vec2 uv = UV;                    // 0..1, y down
	vec2 p = vec2(uv.x * aspect.x / aspect.y, uv.y);
	float t = TIME;
	vec3 col = vec3(0.0);
	float center = smoothstep(0.55, 0.05, abs(uv.y - 0.5)) * smoothstep(0.7, 0.1, abs(uv.x - 0.5));

	if (style == 0) {
		// Crystal Caves
		col = mix(vec3(0.10, 0.03, 0.20), vec3(0.03, 0.01, 0.08), uv.y);
		col += vec3(0.25, 0.10, 0.45) * fbm(p * 3.0 + vec2(0.0, t * 0.02)) * 0.5;
		// back crystals bottom
		for (int k = 0; k < 3; k++) {
			float fk = float(k);
			vec2 s = spikes(p.x, 1.0 - uv.y, 3.0 + fk * 2.5, fk * 13.0, 0.42 - fk * 0.1);
			vec3 cc = mix(vec3(0.35, 0.15, 0.75), vec3(0.15, 0.75, 0.95), fk * 0.5);
			float shade = 0.35 + 0.65 * fract(p.x * (3.0 + fk * 2.5) + fk * 13.0);
			col = mix(col, cc * (0.25 + 0.35 * shade) * (0.6 + 0.4 * fk), s.x * (0.75 + 0.1 * fk));
			col += cc * s.y * (0.6 + 0.3 * sin(t * 1.5 + fk * 2.0 + p.x * 6.0));
			// stalactites
			vec2 s2 = spikes(p.x + 0.37, uv.y, 2.5 + fk * 2.0, fk * 7.0 + 3.0, 0.22 - fk * 0.05);
			col = mix(col, cc * 0.22, s2.x * 0.8);
			col += cc * s2.y * 0.5;
		}
		col += vec3(0.8, 0.9, 1.0) * stars(p + vec2(0.0, t * 0.01), 26.0, t * 2.0) * 0.8;
	} else if (style == 1) {
		// Sunken Temple
		col = mix(vec3(0.03, 0.40, 0.48), vec3(0.01, 0.06, 0.16), pow(uv.y, 0.7));
		float ang = (p.x - 0.4) / (uv.y + 0.25);
		float rays = 0.0;
		rays += sin(ang * 9.0 + t * 0.4) * 0.5 + 0.5;
		rays *= sin(ang * 23.0 - t * 0.3) * 0.5 + 0.5;
		col += vec3(0.3, 0.9, 0.8) * rays * (1.0 - uv.y) * 0.35;
		vec2 q = p * 6.0;
		float c1 = fbm(q + vec2(t * 0.25, t * 0.1));
		float c2 = fbm(q * 1.3 - vec2(t * 0.2, -t * 0.15) + c1);
		float caust = pow(1.0 - abs(c1 - c2) * 2.0, 8.0);
		col += vec3(0.4, 1.0, 0.95) * caust * 0.25 * (1.0 - uv.y * 0.6);
		// pillars at the sides, ruins at the bottom
		float px = abs(uv.x - 0.5);
		float pil = step(0.40, px) * step(px, 0.47) * step(0.15, uv.y);
		col = mix(col, vec3(0.02, 0.10, 0.14), pil * 0.85);
		float steps = step(1.0 - uv.y, 0.08 + 0.03 * floor(abs(uv.x - 0.5) * 8.0) * 0.0 + 0.02 * step(0.3, px));
		col = mix(col, vec3(0.02, 0.07, 0.10), steps);
		col += vec3(0.2, 0.9, 0.9) * smoothstep(0.004, 0.0, abs(px - 0.40)) * step(0.15, uv.y) * 0.3;
	} else if (style == 2) {
		// Golden Dunes at sunset
		col = mix(vec3(0.95, 0.55, 0.30), vec3(0.32, 0.10, 0.35), pow(1.0 - uv.y, 1.3));
		col = mix(col, vec3(0.12, 0.04, 0.22), smoothstep(0.35, 0.0, uv.y));
		vec2 sun = vec2(0.5 * aspect.x / aspect.y, 0.22);
		float d = length(p - sun);
		col += vec3(1.0, 0.75, 0.35) * smoothstep(0.09, 0.07, d);
		col += vec3(1.0, 0.55, 0.25) * exp(-d * 6.0) * 0.6;
		col += vec3(0.9, 0.8, 1.0) * stars(p, 30.0, t) * smoothstep(0.25, 0.0, uv.y);
		// pyramid
		float py = 0.72 - abs(p.x - sun.x - 0.12) * 0.9;
		col = mix(col, vec3(0.35, 0.14, 0.18), step(py, uv.y) * step(uv.y, 0.82) * 0.8);
		for (int k = 0; k < 4; k++) {
			float fk = float(k);
			float base = 0.74 + fk * 0.07;
			float dune = base + sin(p.x * (3.0 + fk) + fk * 2.0 + t * 0.03 * (fk + 1.0)) * 0.025 + sin(p.x * 9.0 + fk) * 0.008;
			vec3 dc = mix(vec3(0.85, 0.45, 0.25), vec3(0.30, 0.10, 0.18), fk / 3.0);
			float m = smoothstep(dune, dune + 0.004, uv.y);
			col = mix(col, dc * (1.0 - (uv.y - dune) * 1.5), m);
			col += vec3(1.0, 0.8, 0.5) * smoothstep(0.006, 0.0, abs(uv.y - dune)) * 0.25;
		}
		col += vec3(1.0, 0.7, 0.4) * fbm(p * 4.0 + vec2(t * 0.15, 0.0)) * 0.08;
	} else if (style == 3) {
		// Firefly Forest
		col = mix(vec3(0.05, 0.16, 0.18), vec3(0.01, 0.04, 0.04), uv.y);
		vec2 moon = vec2(0.72 * aspect.x / aspect.y, 0.12);
		float d = length(p - moon);
		col += vec3(0.7, 1.0, 0.85) * (smoothstep(0.05, 0.045, d) * 0.6 + exp(-d * 8.0) * 0.25);
		for (int k = 0; k < 3; k++) {
			float fk = float(k);
			float sc = 4.0 + fk * 3.0;
			float cx = p.x * sc + fk * 5.0;
			float id = floor(cx);
			float fx = fract(cx) - 0.5;
			float wob = (noise(vec2(id, uv.y * 3.0)) - 0.5) * 0.15;
			float trunk = step(abs(fx + wob), 0.08 + 0.05 * hash(vec2(id, fk))) * step(0.5, hash(vec2(id, fk + 9.0)));
			float edgeMask = smoothstep(0.30, 0.45, abs(uv.x - 0.5));
			vec3 tc = vec3(0.01, 0.05, 0.04) + vec3(0.02, 0.08, 0.05) * fk;
			col = mix(col, tc, trunk * mix(edgeMask, 1.0, step(0.85, uv.y)) * 0.9);
			// canopy blobs top
			float can = fbm(vec2(p.x * sc * 0.6, uv.y * 4.0) + fk * 3.0);
			col = mix(col, tc * 1.2, smoothstep(0.55, 0.6, can) * smoothstep(0.30 - fk * 0.06, 0.0, uv.y));
		}
		float mist = fbm(p * 2.5 + vec2(t * 0.04, 0.0));
		col += vec3(0.25, 0.55, 0.45) * mist * smoothstep(0.5, 1.0, uv.y) * 0.4;
		col = mix(col, vec3(0.02, 0.07, 0.04), smoothstep(0.9, 1.0, uv.y));
		// grass tips
		float gr = step(1.0 - uv.y, 0.03 + 0.03 * abs(sin(p.x * 60.0)) * noise(vec2(p.x * 20.0, 1.0)));
		col = mix(col, vec3(0.02, 0.12, 0.06), gr);
	} else if (style == 4) {
		// Fire Forge
		col = mix(vec3(0.16, 0.03, 0.03), vec3(0.04, 0.01, 0.02), smoothstep(0.0, 0.7, uv.y));
		float smoke = fbm(p * 3.0 + vec2(t * 0.05, t * 0.08));
		col += vec3(0.25, 0.08, 0.06) * smoke * smoothstep(0.6, 0.0, uv.y);
		// lava field at the bottom
		vec2 q = p * vec2(5.0, 9.0) + vec2(0.0, -t * 0.05);
		float n1 = fbm(q);
		float ridge = 1.0 - abs(n1 * 2.0 - 1.0);
		ridge = pow(ridge, 10.0);
		float lavaMask = smoothstep(0.70, 0.88, uv.y);
		col = mix(col, vec3(0.08, 0.02, 0.02), lavaMask);
		col += vec3(1.0, 0.35, 0.05) * ridge * lavaMask * (0.9 + 0.3 * sin(t * 2.0 + n1 * 10.0));
		col += vec3(1.0, 0.5, 0.1) * lavaMask * fbm(q * 0.5 + t * 0.1) * 0.25;
		// glowing cracks on the dark rock at the sides
		float sideMask = smoothstep(0.38, 0.5, abs(uv.x - 0.5));
		float cr = pow(1.0 - abs(fbm(p * 7.0) * 2.0 - 1.0), 16.0);
		col += vec3(1.0, 0.3, 0.05) * cr * sideMask * 0.8;
		col += vec3(1.0, 0.45, 0.1) * exp(-(1.0 - uv.y) * 6.0) * 0.35;
	} else {
		// Star Crown (cosmos)
		vec2 q = p * 2.2;
		float n1 = fbm(q + vec2(t * 0.01, 0.0));
		float n2 = fbm(q * 1.7 + n1 * 1.5 - vec2(0.0, t * 0.015));
		col = vec3(0.02, 0.01, 0.06);
		col += vec3(0.65, 0.12, 0.55) * smoothstep(0.45, 0.9, n2) * 0.8;
		col += vec3(0.15, 0.30, 0.90) * smoothstep(0.4, 0.8, n1) * 0.5;
		col += vec3(1.0, 0.6, 0.3) * smoothstep(0.7, 0.95, n2 * n1 * 1.6) * 0.4;
		float band = exp(-pow((uv.y - 0.35 - p.x * 0.4) * 5.0, 2.0));
		col += vec3(0.5, 0.4, 0.9) * band * fbm(p * 12.0) * 0.4;
		col += vec3(1.0) * stars(p, 40.0, t * 1.5);
		col += vec3(0.8, 0.9, 1.0) * stars(p + 0.37, 18.0, t) * 1.2;
	}
	// keep the middle calm for the board, vignette the edges
	col *= 1.0 - center * 0.35;
	float vig = smoothstep(1.25, 0.35, length((uv - 0.5) * vec2(1.3, 1.0)));
	col *= mix(0.55, 1.0, vig);
	col = mix(col, col * tint.rgb * 1.4, 0.08);
	COLOR = vec4(col * fade, 1.0);
}
