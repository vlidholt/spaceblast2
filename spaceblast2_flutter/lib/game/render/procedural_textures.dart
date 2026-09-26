import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/gpu.dart' show SamplerAddressMode;
import 'package:flutter_scene/scene.dart';

/// Small effect textures generated at startup instead of shipped as files.
class ProceduralTextures {
  static const _sampling = TextureSampling(
    addressMode: SamplerAddressMode.clampToEdge,
  );

  static Future<Texture2D> _build(
    int w,
    int h,
    double Function(double u, double v) alpha, {
    double Function(double u, double v)? value,
  }) async {
    final px = Uint8List(w * h * 4);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final u = (x + 0.5) / w * 2.0 - 1.0;
        final v = (y + 0.5) / h * 2.0 - 1.0;
        final a = alpha(u, v).clamp(0.0, 1.0);
        final c = (value?.call(u, v) ?? 1.0).clamp(0.0, 1.0);
        final o = (y * w + x) * 4;
        final cv = (c * 255).round();
        px[o] = cv;
        px[o + 1] = cv;
        px[o + 2] = cv;
        px[o + 3] = (a * 255).round();
      }
    }
    return Texture2D.fromPixels(px, w, h, sampling: _sampling);
  }

  /// A soft round glow with a hot center.
  static Future<Texture2D> glow() => _build(64, 64, (u, v) {
    final r2 = u * u + v * v;
    if (r2 >= 1.0) return 0.0;
    final falloff = math.exp(-r2 * 4.5) * (1.0 - r2);
    return falloff + math.exp(-r2 * 40.0) * 0.6;
  });

  /// A billowy puff for smoke and fire.
  static Future<Texture2D> puff() {
    final rnd = math.Random(7);
    final blobs = List.generate(
      9,
      (_) => (
        rnd.nextDouble() * 1.0 - 0.5,
        rnd.nextDouble() * 1.0 - 0.5,
        0.25 + rnd.nextDouble() * 0.3,
      ),
    );
    return _build(64, 64, (u, v) {
      double d = 0.0;
      for (final (bx, by, br) in blobs) {
        final dx = u - bx, dy = v - by;
        final t = 1.0 - (dx * dx + dy * dy) / (br * br);
        if (t > 0) d += t * t * 0.55;
      }
      final r2 = u * u + v * v;
      final edge = (1.0 - r2).clamp(0.0, 1.0);
      return (d * edge * 1.3).clamp(0.0, 1.0);
    });
  }

  /// A thin bright streak along V, used for velocity-stretched sparks.
  static Future<Texture2D> spark() => _build(16, 64, (u, v) {
    final across = math.exp(-u * u * 9.0);
    final along = (1.0 - v.abs()).clamp(0.0, 1.0);
    return across * math.pow(along, 0.6);
  });

  /// An engine flame: wide at the base (top of the texture), tapering to a
  /// soft tip at the bottom.
  static Future<Texture2D> flame() => _build(32, 128, (u, v) {
    final t = (v + 1.0) / 2.0; // 0 at the base, 1 at the tip
    // A rounded, feathered body rather than a hard cone.
    final width = 0.78 * math.pow(1.0 - t, 0.5) + 0.14;
    final across = math.exp(-math.pow(u / width, 2) * 1.6);
    final baseFade = math.pow((t / 0.12).clamp(0.0, 1.0), 0.7).toDouble();
    final along = math.pow(1.0 - t, 1.4).toDouble();
    return across * along * baseFade;
  });

  /// A soft motion-blur streak: uniform along its length with soft ends.
  static Future<Texture2D> streak() => _build(16, 64, (u, v) {
    final across = math.exp(-u * u * 5.0);
    final ends = ((1.0 - v.abs()) / 0.35).clamp(0.0, 1.0);
    return across * ends * ends * (3 - 2 * ends);
  });

  /// A crisp shockwave ring.
  static Future<Texture2D> ring() => _build(128, 128, (u, v) {
    final r = math.sqrt(u * u + v * v);
    final d = (r - 0.82).abs();
    return math.exp(-d * d * 400.0) + math.exp(-d * d * 40.0) * 0.25;
  });

  /// A four-point twinkle.
  static Future<Texture2D> twinkle() => _build(64, 64, (u, v) {
    final r2 = u * u + v * v;
    final core = math.exp(-r2 * 30.0);
    final rayX = math.exp(-v * v * 900.0) * (1.0 - u.abs()).clamp(0.0, 1.0);
    final rayY = math.exp(-u * u * 900.0) * (1.0 - v.abs()).clamp(0.0, 1.0);
    return core + (rayX + rayY) * 0.9;
  });

  /// A small hexagonal cell pattern disc for the shield.
  static Future<Texture2D> shield() => _build(128, 128, (u, v) {
    final r = math.sqrt(u * u + v * v);
    if (r > 1.0) return 0.0;
    // Fresnel-like rim.
    final rim = math.pow(r, 6.0).toDouble() * 0.9;
    // Hex grid lines.
    const scale = 7.0;
    final q = u * scale * 2 / math.sqrt(3);
    final rr = v * scale - u * scale / math.sqrt(3);
    double hexDist(double a, double b) {
      final fa = a - a.floorToDouble() - 0.5;
      final fb = b - b.floorToDouble() - 0.5;
      final fc = -fa - fb;
      return math.max(fa.abs(), math.max(fb.abs(), fc.abs()));
    }

    final h = hexDist(q, rr);
    final line = math.exp(-math.pow((h - 0.5) * 14.0, 2).toDouble());
    final edgeFade = (1.0 - r) * 12.0;
    return (rim + line * 0.18 * r) * edgeFade.clamp(0.0, 1.0) + 0.04;
  });
}
