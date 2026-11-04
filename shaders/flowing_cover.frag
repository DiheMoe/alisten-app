#version 460 core

#include <flutter/runtime_effect.glsl>

precision mediump float;

uniform vec2 uSize;
uniform float uAngleA;
uniform float uAngleB;
uniform float uAngleC;
uniform float uWarp;
uniform float uMix;
uniform float uAlpha;
uniform sampler2D uFrom;
uniform sampler2D uTo;

out vec4 fragColor;

mat2 rotation(float angle) {
  float c = cos(angle);
  float s = sin(angle);
  return mat2(c, -s, s, c);
}

// 旋转后超出封面的坐标镜像取样，边界才没有硬边。
vec2 mirrored(vec2 uv) {
  return abs(mod(uv + 1.0, 2.0) - 1.0);
}

vec3 cover(vec2 uv) {
  return mix(texture(uFrom, uv).rgb, texture(uTo, uv).rgb, uMix);
}

vec3 layer(vec2 p, vec2 center, float scale, float angle) {
  vec2 local = rotation(angle) * ((p - center) / scale);
  return cover(mirrored(local * 0.5 + 0.5));
}

float blob(vec2 p, vec2 center) {
  return 1.0 - smoothstep(0.2, 0.75, length(p - center));
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  // 按长边归一化到 [-1, 1]，封面不被拉伸。
  vec2 p = (frag - 0.5 * uSize) / (0.5 * max(uSize.x, uSize.y));
  p += uWarp * 0.2 * vec2(sin(p.y * 2.5 + uAngleA * 3.0),
                          sin(p.x * 2.0 - uAngleB * 2.0));

  vec3 color = layer(p, vec2(0.0), 1.4, uAngleA);
  vec2 second = vec2(-0.25, 0.15);
  vec2 third = rotation(uAngleA) * vec2(0.7, 0.7);
  color = mix(color, layer(p, second, 0.7, uAngleB), blob(p, second));
  color = mix(color, layer(p, third, 0.7, uAngleC), blob(p, third));

  float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
  color = mix(vec3(luma), color, 2.0);

  // 暗色渐变在 8 位屏幕上会出现色带。
  // 坐标先取模：`mediump` 下乘积在高屏幕的下方会溢出。
  vec2 grain = mod(frag, 256.0);
  float noise = fract(sin(dot(grain, vec2(12.9898, 78.233))) * 43758.5453);
  color += (noise - 0.5) / 255.0;

  fragColor = vec4(clamp(color, 0.0, 1.0) * uAlpha, uAlpha);
}
