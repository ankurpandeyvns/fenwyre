#version 440
// Liquid-glass digits: sharp glyph mask -> rounded (disk-blurred + thresholded) shape,
// frosted backdrop, milky vertical gradient, bright inner rim, soft edge.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 texel;        // 1 / mask size in pixels
    float radius;      // rounding radius, px
    float rimWidth;    // px
    float hasBackdrop;
};
layout(binding = 1) uniform sampler2D mask;
layout(binding = 2) uniform sampler2D backdrop;

float softAt(vec2 uv, float r)
{
    // 24-tap disk average of the glyph alpha
    float s = texture(mask, uv).a;
    float n = 1.0;
    for (int ring = 1; ring <= 3; ++ring) {
        float rr = r * float(ring) / 3.0;
        int taps = ring * 4 + 4;
        for (int i = 0; i < 16; ++i) {
            if (i >= taps) break;
            float a = 6.2831853 * (float(i) + 0.5 * float(ring)) / float(taps);
            s += texture(mask, uv + vec2(cos(a), sin(a)) * rr * texel).a;
            n += 1.0;
        }
    }
    return s / n;
}

void main()
{
    vec2 uv = qt_TexCoord0;
    float soft = softAt(uv, radius);
    float aa = 0.06;
    float inside = smoothstep(0.5 - aa, 0.5 + aa, soft);
    if (inside <= 0.0) { fragColor = vec4(0.0); return; }

    // distance-ish to the edge from a tighter blur: 1 deep inside, ~0.5 at the edge
    float near = softAt(uv, rimWidth);
    float rim = 1.0 - smoothstep(0.60, 0.80, near);         // bright band just inside the edge
    float topLight = 1.0 - smoothstep(0.0, 1.0, uv.y);      // brighter towards the top

    vec3 behind = hasBackdrop > 0.5 ? texture(backdrop, uv).rgb : vec3(0.75, 0.8, 0.9);
    // clear glass: lifted, slightly cool-tinted backdrop
    float l = dot(behind, vec3(0.299, 0.587, 0.114));
    behind = mix(vec3(l), behind, 0.8) * vec3(0.93, 0.97, 1.06);
    vec3 glass = mix(behind, vec3(0.94, 0.96, 1.0), 0.14 + 0.12 * topLight);
    // refraction darkening just inside the rim, then a crisp bright rim line
    float band = 1.0 - smoothstep(0.70, 0.98, softAt(uv, rimWidth * 2.2));
    glass *= 1.0 - 0.10 * band * (1.0 - rim);
    glass = mix(glass, vec3(1.0), rim * (0.70 + 0.30 * topLight));
    float alpha = inside * (0.74 + 0.26 * rim);
    fragColor = vec4(glass * alpha, alpha) * qt_Opacity;
}
