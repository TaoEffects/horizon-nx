#version 120

attribute vec4 mc_Entity;

uniform float frameTimeCounter;
uniform vec3 cameraPosition;
uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;

varying vec2 lmcoord;
varying vec2 texcoord;
varying vec4 glcolor;
varying vec3 viewNormal;
varying float matFlag;

void main() {
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lmcoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    glcolor = gl_Color;
    viewNormal = normalize(gl_NormalMatrix * gl_Normal);

    vec4 viewPos = gl_ModelViewMatrix * gl_Vertex;
    vec4 worldPos = gbufferModelViewInverse * viewPos;

    int id = int(mc_Entity.x + 0.5);
    matFlag = 0.0;
    if (id == 10001 || id == 10002) {
        matFlag = 0.25; // foliage (subsurface translucency)
        vec3 wp = worldPos.xyz + cameraPosition;
        float t = frameTimeCounter * 2.4;
        float amp = (id == 10002) ? 0.045 : 0.07;
        float gust = 0.75 + 0.25 * sin(frameTimeCounter * 0.7 + wp.x * 0.12);
        worldPos.x += sin(t + wp.x * 1.3 + wp.z * 0.9 + wp.y * 0.5) * amp * gust;
        worldPos.z += cos(t * 0.85 + wp.z * 1.1 + wp.y * 0.7) * amp * 0.75 * gust;
        if (id == 10002) {
            worldPos.y += sin(t * 1.1 + wp.x * 0.8 + wp.z * 0.8) * 0.02;
        }
        viewPos = gbufferModelView * worldPos;
    }

    gl_Position = gl_ProjectionMatrix * viewPos;
}
