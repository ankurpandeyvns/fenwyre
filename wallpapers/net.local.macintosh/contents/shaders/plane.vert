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
void main()
{
    qt_TexCoord0 = qt_MultiTexCoord0;
    gl_Position = qt_Matrix * qt_Vertex;
}
