#version 440
// Macintosh wallpaper: renders a 512x342 1-bit scene texture as a plane of chunky,
// gapped black pixel tiles with soft drop shadows over a coloured gradient, viewed
// by a tilted perspective camera.
//
// All motion is evaluated here from 'clock' (program time in seconds), which is
// advanced by a render-thread UniformAnimator, so GUI-thread stalls in plasmashell
// cannot cause stutter. The interpreter only uploads tween descriptions
// (from, to, startTime, duration) + an easing id when a command starts.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 resolution;     // item size (only the aspect ratio matters)
    vec2 sceneSize;      // 512 x 342
    float clock;         // program time, seconds
    vec4 twScale;        // (from, to, t0, duration)
    vec4 twRoll;
    vec4 twTilt;
    vec4 twScrollX;
    vec4 twScrollY;
    vec4 curvesA;        // easing ids: scale, roll, tilt, scrollX
    float curveScrollY;
    float persp;         // tan(vertical fov / 2)
    vec4 bgTop;          // fixed palette (spectrum = 0)
    vec4 bgBottom;
    vec4 inkColor;
    float spectrum;      // 1 = background hue cycles
    float hueBase;
    float hueRate;       // hue turns per clock second
    float hueOffset;     // per-screen offset
    float bgDim;         // 1 = light, <1 darker appearance
    vec2 rampFrom;       // background gradient direction (screen space, y down)
    vec2 rampTo;
    float rampT0;
    float fadeOutStart;  // clock time the program finished (ink fades out)
    float fadeDur;
    float gap;
    float shadowAmt;
    float shadowBlur;
};
layout(binding = 1) uniform sampler2D source;
layout(binding = 2) uniform sampler2D invertMask;

const float PI = 3.14159265358979;

float ease(float id, float t)
{
    t = clamp(t, 0.0, 1.0);
    if (id < 0.5) return t;                                   // linear
    if (id < 1.5) return t * t * t;                           // easein
    if (id < 2.5) return 1.0 - pow(1.0 - t, 3.0);             // easeout
    return t < 0.5 ? 4.0 * t * t * t : 1.0 - pow(-2.0 * t + 2.0, 3.0) / 2.0; // easeinout
}

float tween(vec4 tw, float id)
{
    float p = tw.w > 0.0 ? (clock - tw.z) / tw.w : 1.0;
    return mix(tw.x, tw.y, ease(id, p));
}

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

// 0 at the light end of the gradient, 1 at the deep end. Zero vector = gentle vertical.
float rampAmount(vec2 v, vec2 sp)
{
    float l = length(v);
    vec2 dir = l > 0.05 ? v / l : vec2(0.0, 1.0);
    float amt = l > 0.05 ? 1.0 : 0.75;
    return clamp(0.5 + dot(sp - 0.5, dir) * amt, 0.0, 1.0);
}

vec3 hsv2rgb(vec3 c)
{
    vec3 p = abs(fract(c.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
    return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

void main()
{
    vec2 sp = qt_TexCoord0;                       // 0..1, y down
    float aspect = resolution.x / max(resolution.y, 1.0);

    // ---- background: gradient along the program's ramp direction, cross-faded on change
    float gFrom = rampAmount(rampFrom, sp);
    float gTo = rampAmount(rampTo, sp);
    float g = mix(gFrom, gTo, smoothstep(0.0, 1.0, (clock - rampT0) / 2.5));
    vec3 top, bottom;
    if (spectrum > 0.5) {
        float h = fract(hueBase + clock * hueRate + hueOffset);
        top = hsv2rgb(vec3(h, 0.62, 0.98));
        bottom = hsv2rgb(vec3(fract(h + 0.03), 0.92, 0.93));
    } else {
        top = bgTop.rgb;
        bottom = bgBottom.rgb;
    }
    vec3 bg = mix(top, bottom, g) * bgDim;

    // ---- camera, evaluated from the tweens
    float e = clamp(tween(twScale, curvesA.x), 0.0, 1.0);
    float rollDeg = tween(twRoll, curvesA.y);
    float tiltDeg = tween(twTilt, curvesA.z);
    vec2 scroll = vec2(tween(twScrollX, curvesA.w), tween(twScrollY, curveScrollY));
    float outH = min(sceneSize.y, sceneSize.x / aspect);           // whole screen, cover-fit
    float inH = 160.0 / max(aspect, 1.0);                          // ~160 px across the long edge
    float viewHeight = exp(mix(log(outH), log(inH), e));
    vec2 center = mix(sceneSize * 0.5, scroll, e);
    float roll = -rollDeg * e * PI / 180.0;                        // camera -22.5 => rows rise to the right
    float tilt = abs(tiltDeg) * e * PI / 180.0;

    vec2 p = vec2(sp.x * 2.0 - 1.0, 1.0 - sp.y * 2.0);
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

    // ---- tiles with analytic anti-aliasing (gap fades out when pixels get tiny)
    vec2 fw = max(fwidth(uv), vec2(1e-4));
    float tiny = smoothstep(0.18, 0.45, max(fw.x, fw.y));
    float gg = gap * 0.5 * (1.0 - tiny);
    vec2 cell = floor(uv);
    vec2 f = uv - cell;
    vec2 h2 = fw * 0.5;
    vec2 lo = smoothstep(vec2(gg) - h2, vec2(gg) + h2, f);
    vec2 hi = 1.0 - smoothstep(vec2(1.0 - gg) - h2, vec2(1.0 - gg) + h2, f);
    float ink = inkAt(cell) * lo.x * lo.y * hi.x * hi.y;

    // ---- soft drop shadow (screen-down direction projected onto the plane)
    float sh = 0.0;
    if (shadowAmt > 0.0) {
        vec2 q = uv - 0.3 * vec2(sin(roll), cos(roll));
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

    float fade = min(clamp(clock / fadeDur, 0.0, 1.0),
                     clamp(1.0 - (clock - fadeOutStart) / fadeDur, 0.0, 1.0));
    vec3 col = bg * (1.0 - shadowAmt * sh * fade);
    col = mix(col, inkColor.rgb, ink * fade * inkColor.a);
    fragColor = vec4(col, 1.0) * qt_Opacity;
}
