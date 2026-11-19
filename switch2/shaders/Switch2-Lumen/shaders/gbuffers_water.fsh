#version 120

uniform sampler2D texture;
uniform float frameTimeCounter;
uniform mat4 gbufferModelView;

varying vec2 lmcoord;
varying vec2 texcoord;
varying vec4 glcolor;
varying vec3 viewNormal;
varying vec3 worldPosOut;
varying float isWater;

float waveHeight(vec2 p, float t) {
    float w1 = sin(p.x * 2.3 + t * 2.1 + cos(p.y * 1.7 + t * 1.3)) * 0.5;
    float w2 = cos(p.y * 3.1 - t * 1.8 + sin(p.x * 2.5 - t * 1.5)) * 0.35;
    float w3 = sin((p.x + p.y) * 4.7 + t * 3.0) * 0.15;
    return w1 + w2 + w3;
}

/* DRAWBUFFERS:012 */
void main() {
    vec4 color = texture2D(texture, texcoord) * glcolor;
    vec3 n = normalize(viewNormal);
    float flag = 0.0;

    if (isWater > 0.5) {
        flag = 0.75; // water material flag for SSR + depth tint in composite
        float eps = 0.08;
        vec2 p = worldPosOut.xz;
        float hC = waveHeight(p, frameTimeCounter);
        float hX = waveHeight(p + vec2(eps, 0.0), frameTimeCounter);
        float hZ = waveHeight(p + vec2(0.0, eps), frameTimeCounter);
        vec3 worldRipple = normalize(vec3((hC - hX) * 0.22, 1.0, (hC - hZ) * 0.22));
        n = normalize((gbufferModelView * vec4(worldRipple, 0.0)).xyz);
        // Clean, crisp translucent turquoise-blue tint
        color.rgb = mix(color.rgb, vec3(0.06, 0.32, 0.44), 0.55);
        color.a = 0.62;
    }

    gl_FragData[0] = color;
    gl_FragData[1] = vec4(n * 0.5 + 0.5, flag);
    gl_FragData[2] = vec4(lmcoord, 0.0, 1.0);
}
