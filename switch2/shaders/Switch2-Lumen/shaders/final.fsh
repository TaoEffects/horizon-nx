#version 120

uniform sampler2D colortex0;
uniform float viewWidth;
uniform float viewHeight;

varying vec2 texcoord;

vec3 acesToneMap(vec3 x) {
    const float a = 2.51;
    const float b = 0.03;
    const float c = 2.43;
    const float d = 0.59;
    const float e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);
}

void main() {
    vec3 color = texture2D(colortex0, texcoord).rgb;

    // Lightweight 4-tap bloom on bright highlights (sun, torches, water specular)
    vec2 px = vec2(2.0 / max(viewWidth, 1.0), 2.0 / max(viewHeight, 1.0));
    vec3 b0 = texture2D(colortex0, texcoord + vec2( px.x,  px.y)).rgb;
    vec3 b1 = texture2D(colortex0, texcoord + vec2(-px.x,  px.y)).rgb;
    vec3 b2 = texture2D(colortex0, texcoord + vec2( px.x, -px.y)).rgb;
    vec3 b3 = texture2D(colortex0, texcoord + vec2(-px.x, -px.y)).rgb;
    vec3 avg = (b0 + b1 + b2 + b3) * 0.25;
    vec3 bloom = max(avg - vec3(0.85), vec3(0.0)) * 0.28;

    color += bloom;
    color = acesToneMap(color * 1.05);

    // Subtle vibrancy boost
    float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
    color = mix(vec3(luma), color, 1.12);

    gl_FragColor = vec4(color, 1.0);
}
