// ============================================================
//  Immersive Identification -- glitch/pixelate/black redaction
//  SHADERTOY PREVIEW (GLSL ES 3.0)
// ------------------------------------------------------------
//  Paste into https://www.shadertoy.com/new to preview the look.
//  It mirrors gamedata/shaders/r3/ii_glitch.ps (HLSL). Since the
//  game feeds it the real scene RT + per-corpse boxes + depth,
//  this standalone version fakes those:
//    * "scene" = iChannel0 if you attach an image/webcam, else a
//      built-in test pattern (set USE_TEXTURE below).
//    * one centred box stands in for a corpse's head/body rect.
//    * no depth test (the game uses it only to skip the viewmodel).
//
//  Switch MODE to preview: 0 = glitch, 1 = pixelate, 2 = black.
//  The glitch tuning constants match the .ps exactly -- tweak here
//  to preview, then copy the values back into ii_glitch.ps.
// ============================================================

#define MODE        0     // 0 glitch, 1 pixelate, 2 black
#define USE_TEXTURE 0     // 1 = sample iChannel0 (attach an image/webcam), 0 = test pattern
#define INTENSITY   1.0   // 0..1 master strength (game: redact_strength)

// --- box (normalised screen rect standing in for a corpse) ---
const vec2 RECT_MIN = vec2(0.34, 0.16);
const vec2 RECT_MAX = vec2(0.66, 0.84);

float ii_hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

// Stand-in "scene". Plug iChannel0 for a real image, or a procedural test grid.
vec3 sceneColor(vec2 uv)
{
#if USE_TEXTURE
	return texture(iChannel0, uv).rgb;
#else
	vec3 base = mix(vec3(0.10, 0.12, 0.14), vec3(0.55, 0.5, 0.42), uv.y);
	float grid = step(0.5, fract(uv.x * 12.0)) * step(0.5, fract(uv.y * 12.0));
	base += 0.10 * grid;
	// a couple of shapes so the tear/aberration is visible
	base += 0.4 * smoothstep(0.06, 0.0, distance(uv, vec2(0.5, 0.55)));
	base += vec3(0.3, 0.1, 0.1) * smoothstep(0.03, 0.0, distance(uv, vec2(0.42, 0.4)));
	return base;
#endif
}

// ---- mode 0: blocky/twitchy glitch (mirrors ii_glitch in the .ps) ----
vec3 ii_glitch(vec2 uv, vec2 luv, vec2 span, float intensity, float t)
{
	const float BLOCKS_X  = 6.0;
	const float BLOCKS_Y  = 9.0;
	const float SCANLINES = 7.0;
	const float TEAR      = 0.55;
	const float VJUMP     = 0.10;
	const float CHROMA    = 0.014;
	const float NOISE     = 0.35;
	const float SCANDARK  = 0.5;

	float bucket = floor(t * 22.0);
	float burst  = step(0.7, ii_hash(vec2(bucket, 9.0)));

	float bx = floor(luv.x * BLOCKS_X);
	float by = floor(luv.y * BLOCKS_Y);

	float r      = ii_hash(vec2(by, bucket));
	float active = step(0.45 - 0.25 * burst, ii_hash(vec2(bucket, by + 1.0)));
	float shove  = (r - 0.5) * 2.0 * TEAR * intensity * active;

	float vjump = (ii_hash(vec2(bx * 3.1 + by, bucket)) - 0.5) * VJUMP * intensity
	            * step(0.82, ii_hash(vec2(bucket, bx + by * 2.0)));

	vec2 duv = clamp(vec2(uv.x + shove * span.x, uv.y + vjump * span.y), 0.0, 1.0);

	float ca = CHROMA * span.x * (1.0 + abs(shove) * 5.0 + burst) * intensity;
	vec3 col;
	col.r = sceneColor(clamp(duv + vec2(ca, 0.0), 0.0, 1.0)).r;
	col.g = sceneColor(duv).g;
	col.b = sceneColor(clamp(duv - vec2(ca, 0.0), 0.0, 1.0)).b;

	float drop = step(0.82 - 0.15 * burst, ii_hash(vec2(bx + by * 7.0 + 5.0, bucket)));
	col = mix(col, 1.0 - col, drop * 0.6 * intensity);
	col *= mix(1.0, 0.15, drop * intensity);

	float scan  = 1.0 - SCANDARK * intensity * step(0.5, fract(luv.y * SCANLINES + t * 2.0));
	float noise = ii_hash(vec2(bx, by) + bucket);
	col *= scan;
	col += (noise - 0.5) * NOISE * intensity;

	return mix(col, col * vec3(0.7, 1.05, 1.2), 0.4 * intensity);
}

// ---- mode 1: pixelate (mosaic censor) ----
vec3 ii_pixelate(vec2 rect_xy, vec2 span, vec2 luv)
{
	const float CELLS = 10.0;
	vec2 cell = (floor(luv * CELLS) + 0.5) / CELLS;
	vec2 suv  = clamp(rect_xy + cell * span, 0.0, 1.0);
	return sceneColor(suv);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord)
{
	vec2 uv = fragCoord / iResolution.xy;
	uv.y = 1.0 - uv.y;   // Shadertoy origin is bottom-left; flip to match the game's top-left
	float t = iTime;

	vec3 scene = sceneColor(uv);
	vec2 span = max(RECT_MAX - RECT_MIN, vec2(1e-4));
	vec2 luv  = (uv - RECT_MIN) / span;

	if (luv.x < 0.0 || luv.x > 1.0 || luv.y < 0.0 || luv.y > 1.0)
	{
		fragColor = vec4(scene, 1.0);
		return;
	}

	float edge = smoothstep(0.0, 0.08, luv.x) * smoothstep(0.0, 0.08, 1.0 - luv.x)
	           * smoothstep(0.0, 0.08, luv.y) * smoothstep(0.0, 0.08, 1.0 - luv.y);

	vec3 effect;
	float blend;
	if (MODE == 2)      { effect = vec3(0.0);                         blend = edge * INTENSITY; }
	else if (MODE == 1) { effect = ii_pixelate(RECT_MIN, span, luv);  blend = edge * INTENSITY; }
	else                { effect = ii_glitch(uv, luv, span, INTENSITY, t); blend = edge; }

	fragColor = vec4(mix(scene, effect, blend), 1.0);
}
