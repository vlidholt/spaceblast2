import 'dart:math' as math;
import 'dart:ui';

import 'game_math.dart';

/// The subset of SpriteWidget's motion system that drives gameplay: enemy
/// flight paths. Timing semantics (first tick, repeat wrapping) match the
/// original so enemies trace the same paths at the same speed.
abstract class Motion {
  bool _finished = false;
  double get duration;

  void step(double dt);
  void update(double t) {}
  void _reset() => _finished = false;
}

abstract class MotionInterval extends Motion {
  MotionInterval(this._duration);

  final double _duration;
  bool _firstTick = true;
  double _elapsed = 0.0;

  @override
  double get duration => _duration;

  @override
  void step(double dt) {
    if (_firstTick) {
      _firstTick = false;
    } else {
      _elapsed += dt;
    }
    final t = _duration == 0.0 ? 1.0 : (_elapsed / _duration).clamp(0.0, 1.0);
    update(t);
    if (t >= 1.0) _finished = true;
  }

  @override
  void _reset() {
    super._reset();
    _firstTick = true;
    _elapsed = 0.0;
  }
}

class MotionRepeatForever extends Motion {
  MotionRepeatForever(this.motion);

  final MotionInterval motion;
  double _elapsedInMotion = 0.0;

  @override
  double get duration => double.infinity;

  @override
  void step(double dt) {
    _elapsedInMotion += dt;
    while (_elapsedInMotion > motion.duration) {
      _elapsedInMotion -= motion.duration;
      if (!motion._finished) motion.update(1.0);
      motion._reset();
    }
    _elapsedInMotion = math.max(_elapsedInMotion, 0.0);

    final t = motion.duration == 0.0
        ? 1.0
        : (_elapsedInMotion / motion.duration).clamp(0.0, 1.0);
    motion.update(t);
  }
}

typedef PointSetter = void Function(double x, double y);

Offset _cardinalSplineAt(
  Offset p0,
  Offset p1,
  Offset p2,
  Offset p3,
  double tension,
  double t,
) {
  final t2 = t * t;
  final t3 = t2 * t;
  final s = (1.0 - tension) / 2.0;

  final b1 = s * ((-t3 + (2.0 * t2)) - t);
  final b2 = s * (-t3 + t2) + (2.0 * t3 - 3.0 * t2 + 1.0);
  final b3 = s * (t3 - 2.0 * t2 + t) + (-2.0 * t3 + 3.0 * t2);
  final b4 = s * (t3 - t2);

  return Offset(
    p0.dx * b1 + p1.dx * b2 + p2.dx * b3 + p3.dx * b4,
    p0.dy * b1 + p1.dy * b2 + p2.dy * b3 + p3.dy * b4,
  );
}

/// Evaluates a cardinal spline through [points] at [t] in 0..1.
Offset splinePoint(List<Offset> points, double tension, double t) {
  final segment = 1.0 / (points.length - 1.0);
  int p;
  double lt;
  if (t < 0.0) t = 0.0;
  if (t >= 1.0) {
    p = points.length - 1;
    lt = 1.0;
  } else {
    p = (t / segment).floor();
    lt = (t - segment * p) / segment;
  }
  final last = points.length - 1;
  return _cardinalSplineAt(
    points[(p - 1).clamp(0, last)],
    points[(p + 0).clamp(0, last)],
    points[(p + 1).clamp(0, last)],
    points[(p + 2).clamp(0, last)],
    tension,
    lt,
  );
}

class MotionSpline extends MotionInterval {
  MotionSpline(this.setter, this.points, double duration) : super(duration);

  final PointSetter setter;
  final List<Offset> points;
  double tension = 0.5;

  @override
  void update(double t) {
    final p = splinePoint(points, tension, t);
    setter(p.dx, p.dy);
  }
}

class ActionCircularMove extends MotionInterval {
  ActionCircularMove(
    this.setter,
    this.center,
    this.radius,
    this.startAngle,
    this.clockWise,
    double duration,
  ) : super(duration);

  final PointSetter setter;
  final Offset center;
  final double radius;
  final double startAngle;
  final bool clockWise;

  @override
  void update(double t) {
    if (!clockWise) t = -t;
    final rad = radians(startAngle + t * 360.0);
    setter(
      center.dx + math.cos(rad) * radius,
      center.dy + math.sin(rad) * radius,
    );
  }
}

class ActionOscillate extends MotionInterval {
  ActionOscillate(this.setter, this.center, this.radius, double duration)
    : super(duration);

  final PointSetter setter;
  final Offset center;
  final double radius;

  @override
  void update(double t) {
    final rad = radians(t * 360.0);
    setter(center.dx + math.sin(rad) * radius, center.dy);
  }
}
