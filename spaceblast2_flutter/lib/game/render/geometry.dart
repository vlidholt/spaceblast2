import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';

/// A faceted, elongated hexagonal gem (the collectible crystals), centered on
/// the origin with its long axis along +Y and a height of 1.
Geometry buildGemGeometry() {
  const sides = 6;
  const tip = 0.5;
  const shoulder = 0.22;
  const radius = 0.22;

  final top = Vector3(0, tip, 0);
  final bottom = Vector3(0, -tip, 0);
  final upper = <Vector3>[];
  final lower = <Vector3>[];
  for (int i = 0; i < sides; i++) {
    final a = i / sides * math.pi * 2;
    upper.add(Vector3(math.cos(a) * radius, shoulder, math.sin(a) * radius));
    lower.add(Vector3(math.cos(a) * radius, -shoulder, math.sin(a) * radius));
  }

  final builder = GeometryBuilder();
  void face(List<Vector3> pts) {
    // Wind counter-clockwise around the outward normal.
    final center = pts.reduce((a, b) => a + b) / pts.length.toDouble();
    var n = (pts[1] - pts[0]).cross(pts[2] - pts[0]);
    if (n.dot(center) < 0) {
      pts = pts.reversed.toList();
      n = -n;
    }
    n.normalize();
    builder.normal(n);
    final idx = [for (final p in pts) builder.addVertex(p)];
    for (int i = 1; i < idx.length - 1; i++) {
      builder.addTriangle(idx[0], idx[i], idx[i + 1]);
    }
  }

  for (int i = 0; i < sides; i++) {
    final j = (i + 1) % sides;
    face([top, upper[i], upper[j]]);
    face([upper[i], lower[i], lower[j], upper[j]]);
    face([bottom, lower[j], lower[i]]);
  }
  return builder.build();
}

/// The power-up pickup: a hexagonal table-cut gem (pointy-top hexagon in
/// the XY plane) whose table faces -Z (toward the camera). The crown facets
/// cycle through the crystals' violet-to-cyan palette via vertex colors, the
/// table is dark glass for the icon to sit on. Width is 1.
Geometry buildBadgeGemGeometry() {
  const girdle = 0.5; // outer radius
  const table = 0.34; // table radius
  const crownHeight = 0.16;
  const pavilionDepth = 0.28;

  Vector3 ring(double r, int i, double z) => Vector3(
    r * math.sin(i * math.pi / 3),
    r * math.cos(i * math.pi / 3),
    z,
  );

  // Linear-space colors (sRGB values squared is close enough here).
  Vector4 lin(int rgb) {
    double c(int v) => math.pow(v / 255.0, 2.2).toDouble();
    return Vector4(c(rgb >> 16 & 0xff), c(rgb >> 8 & 0xff), c(rgb & 0xff), 1);
  }

  // A light, friendly pastel take on the crystal palette.
  final crownColors = [
    lin(0xE6FBFF),
    lin(0xA8EEFF),
    lin(0x86C8FF),
    lin(0x9FA8FF),
    lin(0xC3A6FF),
    lin(0xE8D2FF),
  ];
  final tableColor = lin(0x6A9CF0);
  final pavilionColor = lin(0x5A64D0);

  final builder = GeometryBuilder();
  void face(List<Vector3> pts, Vector4 color) {
    final center = pts.reduce((a, b) => a + b) / pts.length.toDouble();
    var n = (pts[1] - pts[0]).cross(pts[2] - pts[0]);
    if (n.dot(center) < 0) {
      pts = pts.reversed.toList();
      n = -n;
    }
    n.normalize();
    builder.normal(n);
    builder.color(color);
    final idx = [for (final p in pts) builder.addVertex(p)];
    for (int i = 1; i < idx.length - 1; i++) {
      builder.addTriangle(idx[0], idx[i], idx[i + 1]);
    }
  }

  final top = [for (int i = 0; i < 6; i++) ring(table, i, -crownHeight)];
  final mid = [for (int i = 0; i < 6; i++) ring(girdle, i, 0)];
  final culet = Vector3(0, 0, pavilionDepth);

  face(top, tableColor);
  for (int i = 0; i < 6; i++) {
    final j = (i + 1) % 6;
    face([top[i], mid[i], mid[j], top[j]], crownColors[i]);
    face([mid[i], culet, mid[j]], pavilionColor);
  }
  return builder.build();
}
