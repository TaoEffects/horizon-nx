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
varying vec3 worldPosOut;
varying float isWater;

void main() {
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    lmcoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
    glcolor = gl_Color;
    viewNormal = normalize(gl_NormalMatrix * gl_Normal);

    vec4 viewPos = gl_ModelViewMatrix * gl_Vertex;
    vec4 worldPos = gbufferModelViewInverse * viewPos;
    worldPosOut = worldPos.xyz + cameraPosition;

    int id = int(mc_Entity.x + 0.5);
    isWater = (id == 10003) ? 1.0 : 0.0;
    if (isWater > 0.5) {
        float t = frameTimeCounter * 2.2;
        worldPos.y += sin(t + worldPosOut.x * 1.4 + worldPosOut.z * 1.1) * 0.025
                    + cos(t * 0.8 + worldPosOut.z * 1.7 - worldPosOut.x * 0.9) * 0.018;
        viewPos = gbufferModelView * worldPos;
    }

    gl_Position = gl_ProjectionMatrix * viewPos;
}
