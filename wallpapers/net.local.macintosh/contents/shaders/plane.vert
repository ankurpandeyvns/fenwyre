#version 440
// Pass-through vertex shader (shares the uniform block with plane.frag).
layout(location = 0) in vec4 qt_Vertex;
layout(location = 1) in vec2 qt_MultiTexCoord0;
layout(location = 0) out vec2 qt_TexCoord0;
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
void main()
{
    qt_TexCoord0 = qt_MultiTexCoord0;
    gl_Position = qt_Matrix * qt_Vertex;
}
