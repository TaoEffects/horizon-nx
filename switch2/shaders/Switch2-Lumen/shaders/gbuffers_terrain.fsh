#version 120

uniform sampler2D texture;

varying vec2 lmcoord;
varying vec2 texcoord;
varying vec4 glcolor;
varying vec3 viewNormal;
varying float matFlag;

/* DRAWBUFFERS:012 */
void main() {
    vec4 color = texture2D(texture, texcoord) * glcolor;
    if (color.a < 0.1) {
        discard;
    }
    gl_FragData[0] = color;
    gl_FragData[1] = vec4(normalize(viewNormal) * 0.5 + 0.5, matFlag);
    gl_FragData[2] = vec4(lmcoord, 0.0, 1.0);
}
