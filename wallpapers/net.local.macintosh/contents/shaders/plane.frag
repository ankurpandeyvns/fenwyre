#version 440
// Macintosh wallpaper: renders a 512x342 1-bit scene texture as a plane of chunky,
// gapped pixel tiles with soft drop shadows, viewed by a tilted perspective camera.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 resolution;     // item size (only the aspect ratio matters)
    vec2 sceneSize;      // 512 x 342
    vec2 center;         // look-at point, image pixels
    float roll;          // in-plane rotation, radians
    float tilt;          // plane tilt away from viewer, radians
    float viewHeight;    // image pixels spanning the screen height at the look-at point
    float persp;         // tan(vertical fov / 2)
    vec4 bgTop;
    vec4 bgBottom;
    vec4 inkColor;
    vec2 rampDir;        // spectrum hue gradient (screen space, y down)
    vec2 shadowOffset;   // image pixels
    float hueBase;
    float hueSpan;
    float spectrum;      // 1 = rainbow ink
    float spectrumSat;
    float spectrumVal;
    float inkFade;
    float gap;           // gap between tiles (fraction of a pixel)
    float shadowAmt;
    float shadowBlur;
};
layout(binding = 1) uniform sampler2D source;
layout(binding = 2) uniform sampler2D invertMask;

float inkAt(vec2 cell)
{
    if (cell.x < 0.0 || cell.y < 0.0 || cell.x >= sceneSize.x || cell.y >= sceneSize.y)
        return 0.0;
    vec2 tc = (cell + 0.5) / sceneSize;
    vec4 s = texture(source, tc);
    float k = (s.a > 0.5 && s.r < 0.5) ? 1.0 : 0.0;
    float m = texture(invertMask, tc).a > 0.5 ? 1.0 : 0.0;
    return abs(k - m);
}

vec3 hsv2rgb(vec3 c)
{
    vec3 p = abs(fract(c.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
    return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

void main()
{
    vec2 sp = qt_TexCoord0;                       // 0..1, y down
    vec3 bg = mix(bgTop.rgb, bgBottom.rgb, sp.y);

    // Perspective ray / tilted plane intersection. Camera at origin looking down -z,
    // plane passes through (0,0,-1); its "up" axis recedes by 'tilt'.
    vec2 p = vec2(sp.x * 2.0 - 1.0, 1.0 - sp.y * 2.0);
    float aspect = resolution.x / max(resolution.y, 1.0);
    vec2 d = vec2(p.x * aspect * persp, p.y * persp);
    float ct = cos(tilt), st = sin(tilt);
    float denom = ct - d.y * st;
    if (denom <= 0.01) {
        fragColor = vec4(bg, 1.0) * qt_Opacity;
        return;
    }
    float b = d.y / denom;
    float a = (1.0 + b * st) * d.x;
    float k = (viewHeight * 0.5) / persp;
    vec2 w = vec2(a, b) * k;
    float cr = cos(roll), sr = sin(roll);
    vec2 wr = vec2(cr * w.x - sr * w.y, sr * w.x + cr * w.y);
    vec2 uv = center + vec2(wr.x, -wr.y);

    // Tile coverage with analytic anti-aliasing. When pixels get tiny the gap fades
    // out to avoid moire.
    vec2 fw = max(fwidth(uv), vec2(1e-4));
    float tiny = smoothstep(0.18, 0.45, max(fw.x, fw.y));
    float g = gap * 0.5 * (1.0 - tiny);
    vec2 cell = floor(uv);
    vec2 f = uv - cell;
    vec2 h = fw * 0.5;
    vec2 lo = smoothstep(vec2(g) - h, vec2(g) + h, f);
    vec2 hi = 1.0 - smoothstep(vec2(1.0 - g) - h, vec2(1.0 - g) + h, f);
    float tile = lo.x * lo.y * hi.x * hi.y;
    float ink = inkAt(cell) * tile;

    // Soft drop shadow: nearest 2x2 tiles around the shadow-offset position.
    float sh = 0.0;
    if (shadowAmt > 0.0) {
        vec2 q = uv - shadowOffset;
        vec2 base = floor(q - 0.5);
        float gs = gap * 0.5;
        for (int j = 0; j < 2; ++j) {
            for (int i = 0; i < 2; ++i) {
                vec2 c = base + vec2(float(i), float(j));
                if (inkAt(c) > 0.5) {
                    vec2 dd = max(max(c + gs - q, q - (c + 1.0 - gs)), vec2(0.0));
                    sh = max(sh, 1.0 - smoothstep(0.0, shadowBlur, length(dd)));
                }
            }
        }
        sh *= (1.0 - tiny * 0.7);
    }

    vec3 col = bg * (1.0 - shadowAmt * sh);
    vec3 inkc = inkColor.rgb;
    if (spectrum > 0.5) {
        // Rainbow runs top-to-bottom across the screen (as in Apple's stills); the
        // program's ramp direction adds a secondary drift.
        float hue = fract(hueBase - (sp.y - 0.5) * hueSpan + dot(sp - 0.5, rampDir) * 0.25);
        inkc = hsv2rgb(vec3(hue, spectrumSat, spectrumVal));
    }
    col = mix(col, inkc, ink * inkFade);
    fragColor = vec4(col, 1.0) * qt_Opacity;
}
