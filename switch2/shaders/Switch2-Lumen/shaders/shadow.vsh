#version 120

attribute vec4 mc_Entity;
uniform float frameTimeCounter;
uniform vec3 cameraPosition;
uniform mat4 shadowModelViewInverse;

varying vec2 texcoord;
varying vec4 glcolor;

void main() {
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    glcolor = gl_Color;

    vec4 pos = gl_Vertex;
    int id = int(mc_Entity.x + 0.5);
    if (id == 10001 || id == 10002) {
        vec3 worldPos = (shadowModelViewInverse * (gl_ModelViewMatrix * pos)).xyz + cameraPosition;
        float t = frameTimeCounter * 2.4;
        float amp = (id == 10002) ? 0.045 : 0.065;
        pos.x += sin(t + worldPos.x * 1.3 + worldPos.z * 0.9) * amp;
        pos.z += cos(t * 0.85 + worldPos.z * 1.1 + worldPos.y * 0.7) * amp * 0.75;
    }

    gl_Position = gl_ModelViewProjectionMatrix * pos;
    // Slight shadow map distortion to concentrate resolution near the player
    float dist = length(gl_Position.xy);
    float distortFactor = mix(1.0, dist, 0.82);
    gl_Position.xy /= distortFactor;
    gl_Position.z *= 0.2;
}
