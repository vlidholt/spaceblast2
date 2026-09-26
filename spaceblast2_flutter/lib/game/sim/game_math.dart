import 'dart:math' as math;
import 'dart:typed_data';

// Random helpers, identical in behavior to SpriteWidget's util.dart.

final math.Random _random = math.Random();

/// Returns a random double in the range of 0.0 to 1.0.
double randomDouble() => _random.nextDouble();

/// Returns a random double in the range of -1.0 to 1.0.
double randomSignedDouble() => _random.nextDouble() * 2.0 - 1.0;

/// Returns a random int from 0 to max - 1.
int randomInt(int max) => _random.nextInt(max);

/// Returns either true or false.
bool randomBool() => _random.nextDouble() < 0.5;

double radians(double degrees) => degrees * (math.pi / 180.0);
double degrees(double radians) => radians * (180.0 / math.pi);

class _Atan2Constants {
  _Atan2Constants() {
    for (int i = 0; i <= size; i++) {
      final f = i.toDouble() / size.toDouble();
      ppy[i] = math.atan(f) * stretch / math.pi;
      ppx[i] = stretch * 0.5 - ppy[i];
      pny[i] = -ppy[i];
      pnx[i] = ppy[i] - stretch * 0.5;
      npy[i] = stretch - ppy[i];
      npx[i] = ppy[i] + stretch * 0.5;
      nny[i] = ppy[i] - stretch;
      nnx[i] = -stretch * 0.5 - ppy[i];
    }
  }

  static const int size = 1024;
  static const double stretch = math.pi;
  static const int ezis = -size;

  final Float64List ppy = Float64List(size + 1);
  final Float64List ppx = Float64List(size + 1);
  final Float64List pny = Float64List(size + 1);
  final Float64List pnx = Float64List(size + 1);
  final Float64List npy = Float64List(size + 1);
  final Float64List npx = Float64List(size + 1);
  final Float64List nny = Float64List(size + 1);
  final Float64List nnx = Float64List(size + 1);
}

/// The approximations the original game used for its math. Ported as-is so
/// collisions and aiming behave exactly like the 2D version.
class GameMath {
  static final _Atan2Constants _atan2 = _Atan2Constants();

  /// Table based atan2, less accurate than math.atan2.
  static double atan2(double y, double x) {
    if (x >= 0) {
      if (y >= 0) {
        if (x >= y) {
          return _atan2.ppy[(_Atan2Constants.size * y / x + 0.5).toInt()];
        } else {
          return _atan2.ppx[(_Atan2Constants.size * x / y + 0.5).toInt()];
        }
      } else {
        if (x >= -y) {
          return _atan2.pny[(_Atan2Constants.ezis * y / x + 0.5).toInt()];
        } else {
          return _atan2.pnx[(_Atan2Constants.ezis * x / y + 0.5).toInt()];
        }
      }
    } else {
      if (y >= 0) {
        if (-x >= y) {
          return _atan2.npy[(_Atan2Constants.ezis * y / x + 0.5).toInt()];
        } else {
          return _atan2.npx[(_Atan2Constants.ezis * x / y + 0.5).toInt()];
        }
      } else {
        if (x <= y) {
          return _atan2.nny[(_Atan2Constants.size * y / x + 0.5).toInt()];
        } else {
          return _atan2.nnx[(_Atan2Constants.size * x / y + 0.5).toInt()];
        }
      }
    }
  }

  /// Approximates the distance between two points (up to 6% off).
  static double distanceBetweenPoints(
    double ax,
    double ay,
    double bx,
    double by,
  ) {
    double dx = ax - bx;
    double dy = ay - by;
    if (dx < 0.0) dx = -dx;
    if (dy < 0.0) dy = -dy;
    if (dx > dy) {
      return dx + dy / 2.0;
    } else {
      return dy + dx / 2.0;
    }
  }

  static double filter(double a, double b, double filterFactor) =>
      (a * (1 - filterFactor)) + b * filterFactor;
}

/// Eases [src] toward [dst] (both in degrees) along the shortest arc.
double dampenRotation(double src, double dst, double? dampening) {
  if (dampening == null) return dst;

  double delta = dst - src;
  while (delta > 180.0) {
    delta -= 360;
  }
  while (delta < -180) {
    delta += 360;
  }
  delta *= dampening;

  return src + delta;
}
