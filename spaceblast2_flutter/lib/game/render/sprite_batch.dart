import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_scene/scene.dart';

/// One instanced draw of camera-facing quads sharing a texture. Everything
/// that uses the texture in a frame (lasers, particles, glows) appends to it
/// between [begin] and [end].
class SpriteBatch {
  SpriteBatch(
    TextureSource? texture, {
    bool additive = true,
    this.capacity = 1024,
    BillboardFacing facing = BillboardFacing.spherical,
    double velocityStretch = 0.0,
  }) : geometry = BillboardGeometry(capacity: capacity) {
    geometry.facing = facing;
    geometry.velocityStretch = velocityStretch;
    material = SpriteMaterial(colorTexture: texture)
      ..blendMode = additive ? SpriteBlendMode.additive : SpriteBlendMode.alpha;
    node = Node(mesh: Mesh(geometry, material))..frustumCulled = false;
  }

  final int capacity;
  final BillboardGeometry geometry;
  late final SpriteMaterial material;
  late final Node node;

  int _count = 0;
  int get count => _count;

  void begin() => _count = 0;

  void end() => geometry.commit(_count);

  /// Appends one quad. Rotation is in radians, counter-clockwise on screen.
  void add(
    double x,
    double y,
    double z,
    double width,
    double height,
    double rotation,
    double r,
    double g,
    double b,
    double a, {
    double vx = 0.0,
    double vy = 0.0,
    double vz = 0.0,
  }) {
    if (_count >= capacity) return;
    final d = geometry.instanceData;
    final o = _count * BillboardGeometry.floatsPerInstance;
    d[o] = x;
    d[o + 1] = y;
    d[o + 2] = z;
    d[o + 3] = width;
    d[o + 4] = height;
    // The billboard shader rotates clockwise on screen; callers pass
    // counter-clockwise angles (the usual math convention).
    d[o + 5] = -rotation;
    d[o + 6] = r;
    d[o + 7] = g;
    d[o + 8] = b;
    d[o + 9] = a;
    d[o + 10] = 0.0;
    d[o + 11] = vx;
    d[o + 12] = vy;
    d[o + 13] = vz;
    _count++;
  }
}

/// A color keyframe ramp with three stops at 0, [mid] and 1.
class ColorRamp {
  const ColorRamp(this.start, this.middle, this.end, {this.mid = 0.5});

  const ColorRamp.fade(List<double> color)
    : start = color,
      middle = color,
      end = const [0, 0, 0, 0],
      mid = 0.5;

  final List<double> start;
  final List<double> middle;
  final List<double> end;
  final double mid;
}

/// CPU particles written into a [SpriteBatch] each frame. Positions are world
/// units, times are seconds.
class ParticleLayer {
  ParticleLayer(this.batch, {this.capacity = 512})
    : _x = Float32List(capacity),
      _y = Float32List(capacity),
      _z = Float32List(capacity),
      _vx = Float32List(capacity),
      _vy = Float32List(capacity),
      _vz = Float32List(capacity),
      _age = Float32List(capacity),
      _life = Float32List(capacity),
      _s0 = Float32List(capacity),
      _s1 = Float32List(capacity),
      _aspect = Float32List(capacity),
      _rot = Float32List(capacity),
      _rotV = Float32List(capacity),
      _drag = Float32List(capacity),
      _gravity = Float32List(capacity),
      _mid = Float32List(capacity),
      _c = Float32List(capacity * 12),
      _alignToVelocity = Uint8List(capacity);

  final SpriteBatch batch;
  final int capacity;

  final Float32List _x, _y, _z, _vx, _vy, _vz, _age, _life;
  final Float32List _s0, _s1, _aspect, _rot, _rotV, _drag, _gravity, _mid;
  final Float32List _c;
  final Uint8List _alignToVelocity;

  int _n = 0;
  int get count => _n;

  void clear() => _n = 0;

  void spawn({
    required double x,
    required double y,
    double z = 0.0,
    double vx = 0.0,
    double vy = 0.0,
    double vz = 0.0,
    required double life,
    required double size,
    double? endSize,
    double aspect = 1.0,
    double rotation = 0.0,
    double spin = 0.0,
    double drag = 0.0,
    double gravity = 0.0,
    bool alignToVelocity = false,
    required ColorRamp color,
  }) {
    if (life <= 0) return;
    int i;
    if (_n < capacity) {
      i = _n++;
    } else {
      // Recycle the oldest-looking slot.
      i = 0;
    }
    _x[i] = x;
    _y[i] = y;
    _z[i] = z;
    _vx[i] = vx;
    _vy[i] = vy;
    _vz[i] = vz;
    _age[i] = 0;
    _life[i] = life;
    _s0[i] = size;
    _s1[i] = endSize ?? size;
    _aspect[i] = aspect;
    _rot[i] = rotation;
    _rotV[i] = spin;
    _drag[i] = drag;
    _gravity[i] = gravity;
    _mid[i] = color.mid;
    _alignToVelocity[i] = alignToVelocity ? 1 : 0;
    final o = i * 12;
    for (int k = 0; k < 4; k++) {
      _c[o + k] = color.start[k];
      _c[o + 4 + k] = color.middle[k];
      _c[o + 8 + k] = color.end[k];
    }
  }

  void _kill(int i) {
    final last = --_n;
    if (i == last) return;
    _x[i] = _x[last];
    _y[i] = _y[last];
    _z[i] = _z[last];
    _vx[i] = _vx[last];
    _vy[i] = _vy[last];
    _vz[i] = _vz[last];
    _age[i] = _age[last];
    _life[i] = _life[last];
    _s0[i] = _s0[last];
    _s1[i] = _s1[last];
    _aspect[i] = _aspect[last];
    _rot[i] = _rot[last];
    _rotV[i] = _rotV[last];
    _drag[i] = _drag[last];
    _gravity[i] = _gravity[last];
    _mid[i] = _mid[last];
    _alignToVelocity[i] = _alignToVelocity[last];
    for (int k = 0; k < 12; k++) {
      _c[i * 12 + k] = _c[last * 12 + k];
    }
  }

  void update(double dt) {
    for (int i = _n - 1; i >= 0; i--) {
      final age = _age[i] + dt;
      if (age >= _life[i]) {
        _kill(i);
        continue;
      }
      _age[i] = age;
      final damp = _drag[i] > 0 ? math.exp(-_drag[i] * dt) : 1.0;
      _vx[i] *= damp;
      _vy[i] = _vy[i] * damp - _gravity[i] * dt;
      _vz[i] *= damp;
      _x[i] += _vx[i] * dt;
      _y[i] += _vy[i] * dt;
      _z[i] += _vz[i] * dt;
      _rot[i] += _rotV[i] * dt;
    }
  }

  void write() {
    for (int i = 0; i < _n; i++) {
      final t = _age[i] / _life[i];
      final size = _s0[i] + (_s1[i] - _s0[i]) * t;
      final o = i * 12;
      final mid = _mid[i];
      double r, g, b, a;
      if (t < mid) {
        final k = t / mid;
        r = _c[o] + (_c[o + 4] - _c[o]) * k;
        g = _c[o + 1] + (_c[o + 5] - _c[o + 1]) * k;
        b = _c[o + 2] + (_c[o + 6] - _c[o + 2]) * k;
        a = _c[o + 3] + (_c[o + 7] - _c[o + 3]) * k;
      } else {
        final k = (t - mid) / (1.0 - mid);
        r = _c[o + 4] + (_c[o + 8] - _c[o + 4]) * k;
        g = _c[o + 5] + (_c[o + 9] - _c[o + 5]) * k;
        b = _c[o + 6] + (_c[o + 10] - _c[o + 6]) * k;
        a = _c[o + 7] + (_c[o + 11] - _c[o + 7]) * k;
      }
      double rot = _rot[i];
      if (_alignToVelocity[i] == 1) {
        // Quad's long (V) axis follows the on-screen velocity.
        rot += math.atan2(_vy[i], _vx[i]) - math.pi / 2;
      }
      batch.add(
        _x[i],
        _y[i],
        _z[i],
        size,
        size * _aspect[i],
        rot,
        r,
        g,
        b,
        a,
        vx: _vx[i],
        vy: _vy[i],
        vz: _vz[i],
      );
    }
  }
}
