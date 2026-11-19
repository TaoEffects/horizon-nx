#version 120

uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D colortex2;
uniform sampler2D depthtex0;
uniform sampler2D depthtex1;
uniform sampler2D shadowtex0;

uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;

uniform vec3 shadowLightPosition;
uniform vec3 sunPosition;
uniform vec3 skyColor;
uniform vec3 fogColor;
uniform float sunAngle;
uniform float rainStrength;

varying vec2 texcoord;

vec3 viewPosFromDepth(vec2 uv, float depth) {
    vec4 clip = vec4(uv * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    vec4 view = gbufferProjectionInverse * clip;
    return view.xyz / view.w;
}

vec3 projectToScreen(vec3 viewPos) {
    vec4 clip = gbufferProjection * vec4(viewPos, 1.0);
    return (clip.xyz / clip.w) * 0.5 + 0.5;
}

float sampleShadow(vec3 worldPos, float ndl) {
    vec4 shadowClip = shadowProjection * (shadowModelView * vec4(worldPos, 1.0));
    float dist = length(shadowClip.xy);
    float distortFactor = mix(1.0, dist, 0.82);
    shadowClip.xy /= distortFactor;
    shadowClip.z *= 0.2;
    vec3 sc = shadowClip.xyz * 0.5 + 0.5;

    if (sc.x < 0.002 || sc.x > 0.998 || sc.y < 0.002 || sc.y > 0.998 || sc.z > 0.999) {
        return 1.0;
    }

    float bias = mix(0.0022, 0.0005, clamp(ndl, 0.0, 1.0));
    float texel = 1.0 / 1024.0;
    float vis = 0.0;
    vis += step(sc.z - bias, texture2D(shadowtex0, sc.xy).r);
    vis += step(sc.z - bias, texture2D(shadowtex0, sc.xy + vec2(texel, texel)).r);
    vis += step(sc.z - bias, texture2D(shadowtex0, sc.xy + vec2(-texel, texel)).r);
    vis += step(sc.z - bias, texture2D(shadowtex0, sc.xy + vec2(texel, -texel)).r);
    vis += step(sc.z - bias, texture2D(shadowtex0, sc.xy + vec2(-texel, -texel)).r);
    return vis * 0.2;
}

vec3 computeWaterSSR(vec3 viewPos, vec3 viewNormal, vec3 viewDir) {
    vec3 reflDir = reflect(viewDir, viewNormal);
    vec3 skyFallback = mix(fogColor, skyColor * 1.15, clamp(reflDir.y * 0.5 + 0.5, 0.0, 1.0));

    // Raymarch in view space (16 fast steps, tuned for Switch 2 60-120 fps)
    vec3 rayPos = viewPos + viewNormal * 0.06;
    float stepSize = 0.45;
    for (int i = 0; i < 16; i++) {
        rayPos += reflDir * stepSize;
        stepSize *= 1.18;
        vec3 sp = projectToScreen(rayPos);
        if (sp.x < 0.0 || sp.x > 1.0 || sp.y < 0.0 || sp.y > 1.0 || sp.z > 1.0) {
            break;
        }
        float sceneD = texture2D(depthtex1, sp.xy).r;
        if (sceneD < 0.9999 && sp.z > sceneD) {
            vec3 hitView = viewPosFromDepth(sp.xy, sceneD);
            float dz = abs(rayPos.z - hitView.z);
            if (dz < stepSize * 2.5) {
                vec2 edge = abs(sp.xy * 2.0 - 1.0);
                float fade = clamp(1.0 - max(edge.x, edge.y), 0.0, 1.0);
                fade = smoothstep(0.0, 0.2, fade);
                vec3 hitColor = texture2D(colortex0, sp.xy).rgb;
                return mix(skyFallback, hitColor, fade);
            }
        }
    }
    return skyFallback;
}

/* DRAWBUFFERS:0 */
void main() {
    vec4 albedo = texture2D(colortex0, texcoord);
    float depth0 = texture2D(depthtex0, texcoord).r;

    // Sky passthrough
    if (depth0 >= 0.9999) {
        gl_FragData[0] = albedo;
        return;
    }

    vec4 normMat = texture2D(colortex1, texcoord);
    vec2 lm = texture2D(colortex2, texcoord).rg;
    vec3 viewNormal = normalize(normMat.rgb * 2.0 - 1.0);
    float matFlag = normMat.a;

    vec3 viewPos = viewPosFromDepth(texcoord, depth0);
    vec3 viewDir = normalize(viewPos);
    vec3 worldPos = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz;
    vec3 worldNormal = normalize((gbufferModelViewInverse * vec4(viewNormal, 0.0)).xyz);

    vec3 lightDir = normalize(shadowLightPosition);
    float ndl = dot(viewNormal, lightDir);
    bool isFoliage = (matFlag > 0.15 && matFlag < 0.45);
    bool isWater = (matFlag > 0.6);

    // Day/night factor
    float sunHeight = clamp(normalize((gbufferModelViewInverse * vec4(sunPosition, 0.0)).xyz).y, -0.3, 1.0);
    float dayFactor = smoothstep(-0.1, 0.25, sunHeight);
    float sunsetFactor = smoothstep(0.0, 0.25, 1.0 - abs(sunHeight * 3.0)) * dayFactor;

    // Shadow map lookup (skip in rain or fully shaded sky)
    float shadow = 1.0;
    if (lm.y > 0.05 && (ndl > 0.0 || isFoliage)) {
        vec3 shadowOrigin = worldPos + worldNormal * 0.05;
        shadow = sampleShadow(shadowOrigin, max(ndl, 0.1));
    }
    shadow = mix(shadow, 1.0, rainStrength * 0.75);

    // Lightweight GI: warm direct sun + cool sky hemisphere + subtle ground bounce + warm torch
    vec3 sunCol = mix(vec3(1.12, 1.04, 0.92), vec3(1.35, 0.72, 0.36), sunsetFactor);
    vec3 moonCol = vec3(0.24, 0.34, 0.56);
    vec3 directCol = mix(moonCol, sunCol, dayFactor);

    float directTerm = isFoliage ? mix(0.45, 1.0, clamp(ndl * 0.5 + 0.5, 0.0, 1.0)) : max(ndl, 0.0);
    vec3 directLight = directCol * directTerm * shadow * (0.25 + 0.75 * lm.y);

    // Sky hemisphere + soft ground bounce GI
    float upFactor = worldNormal.y * 0.5 + 0.5;
    vec3 skyBounce = mix(vec3(0.14, 0.17, 0.24), vec3(0.32, 0.42, 0.58), dayFactor);
    vec3 groundBounce = mix(vec3(0.08, 0.09, 0.11), vec3(0.22, 0.20, 0.16), dayFactor);
    vec3 giAmbient = mix(groundBounce, skyBounce, upFactor) * (0.18 + 0.82 * lm.y);

    // Warm torch / blocklight
    float blockLight = pow(clamp(lm.x, 0.0, 1.0), 2.1);
    vec3 torchCol = vec3(1.35, 0.78, 0.38) * blockLight * 1.15;

    // Minimum readable cave ambient
    vec3 totalLight = directLight + giAmbient + torchCol + vec3(0.035, 0.04, 0.055);
    vec3 lit = albedo.rgb * totalLight;

    // Water: depth absorption + Schlick Fresnel + Screen-Space Reflections + sun specular
    if (isWater) {
        float depth1 = texture2D(depthtex1, texcoord).r;
        vec3 backViewPos = viewPosFromDepth(texcoord, depth1);
        float waterThickness = clamp(length(backViewPos - viewPos), 0.0, 16.0);
        float absorb = 1.0 - exp(-waterThickness * 0.24);
        vec3 deepWater = vec3(0.02, 0.14, 0.22) * (0.3 + 0.7 * dayFactor);
        vec3 waterBase = mix(lit, deepWater, absorb * 0.72);

        float ndv = clamp(dot(viewNormal, -viewDir), 0.0, 1.0);
        float fresnel = 0.04 + 0.96 * pow(1.0 - ndv, 4.0);
        vec3 refl = computeWaterSSR(viewPos, viewNormal, viewDir);

        // Crisp sun specular highlight on ripples
        vec3 halfVec = normalize(lightDir - viewDir);
        float spec = pow(max(dot(viewNormal, halfVec), 0.0), 96.0) * shadow * dayFactor;
        vec3 specCol = sunCol * spec * 1.4;

        lit = mix(waterBase, refl, clamp(fresnel * 0.85, 0.06, 0.92)) + specCol;
    }

    gl_FragData[0] = vec4(lit, 1.0);
}
