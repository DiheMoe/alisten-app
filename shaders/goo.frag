#version 460 core

#include <flutter/runtime_effect.glsl>

// 两个圆角矩形按距离场平滑地融成一体：相互靠近时之间长出圆润的颈。坐标都是
// 画布的本地坐标。

precision highp float;

// 中心和半宽高。
uniform vec4 uBody;
uniform float uBodyRadius;
uniform vec4 uDrop;
// 颈能伸多远；为 0 时两者只是叠在一起。
uniform float uBlend;
// 一个物理像素有多少本地单位，边缘按它抗锯齿。
uniform float uPixel;
// 预乘透明度的颜色。
uniform vec4 uColor;

out vec4 fragColor;

float roundedBox(vec2 point, vec2 extent, float radius) {
  float corner = min(radius, min(extent.x, extent.y));
  vec2 q = abs(point) - extent + corner;
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - corner;
}

float smoothUnion(float a, float b, float blend) {
  if (blend <= 0.0) {
    return min(a, b);
  }
  float h = clamp(0.5 + 0.5 * (b - a) / blend, 0.0, 1.0);
  return mix(b, a, h) - blend * h * (1.0 - h);
}

void main() {
  vec2 point = FlutterFragCoord().xy;
  float body = roundedBox(point - uBody.xy, uBody.zw, uBodyRadius);
  float drop = roundedBox(
    point - uDrop.xy,
    uDrop.zw,
    min(uDrop.z, uDrop.w)
  );
  float edge = smoothUnion(body, drop, uBlend);
  fragColor = uColor * clamp(0.5 - edge / uPixel, 0.0, 1.0);
}
