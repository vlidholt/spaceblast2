import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';

/// A perspective projection with a lens shift (an off-axis frustum).
///
/// The image plane stays parallel to the gameplay plane, so the playfield maps
/// linearly onto the screen exactly like the 2D game, while the camera itself
/// sits south of the screen center and sees every model at an angle. Extends
/// [PerspectiveProjection] so the engine's perspective-only effects (depth of
/// field, shadows) stay enabled.
class ShiftedPerspectiveProjection extends PerspectiveProjection {
  ShiftedPerspectiveProjection({
    super.fovRadiansY,
    super.near,
    super.far,
    this.shiftX = 0.0,
    this.shiftY = 0.0,
  });

  /// Lens shift in normalized device coordinates.
  double shiftX;
  double shiftY;

  @override
  Matrix4 getProjectionMatrix(double aspectRatio, {Vector2? jitter}) {
    final m = super.getProjectionMatrix(aspectRatio, jitter: jitter);
    // Column 2 rows 0/1 add a z-proportional offset to x/y, which after the
    // perspective divide is a constant shift of the image.
    m.storage[8] += shiftX;
    m.storage[9] += shiftY;
    return m;
  }
}

/// The camera used for everything: menu shots and gameplay. Plain
/// eye/target/up values so different shots can be blended.
class GameCamera extends Camera {
  GameCamera();

  final ShiftedPerspectiveProjection _projection = ShiftedPerspectiveProjection(
    fovRadiansY: 40 * degrees2Radians,
    near: 0.5,
    far: 400.0,
  );

  final Vector3 eye = Vector3(0, 0, -6);
  final Vector3 target = Vector3(0, 0, 0);
  final Vector3 upVector = Vector3(0, 1, 0);

  @override
  Vector3 get position => eye;

  @override
  Vector3 get forward => (target - eye).normalized();

  @override
  Vector3 get up => upVector;

  @override
  CameraProjection get projection => _projection;

  ShiftedPerspectiveProjection get lens => _projection;

  void apply(CameraShot shot) {
    eye.setFrom(shot.eye);
    target.setFrom(shot.target);
    upVector.setFrom(shot.up);
    _projection.fovRadiansY = shot.fovY;
    _projection.shiftX = shot.shiftX;
    _projection.shiftY = shot.shiftY;
  }

  @override
  Matrix4 getViewMatrix() {
    final Vector3 f = (target - eye).normalized();
    final Vector3 r = upVector.cross(f).normalized();
    final Vector3 u = f.cross(r).normalized();
    return Matrix4(
      r.x,
      u.x,
      f.x,
      0.0,
      r.y,
      u.y,
      f.y,
      0.0,
      r.z,
      u.z,
      f.z,
      0.0,
      -r.dot(eye),
      -u.dot(eye),
      -f.dot(eye),
      1.0,
    );
  }
}

/// A blendable camera setup.
class CameraShot {
  CameraShot({
    required this.eye,
    required this.target,
    required this.up,
    required this.fovY,
    this.shiftX = 0.0,
    this.shiftY = 0.0,
  });

  final Vector3 eye;
  final Vector3 target;
  final Vector3 up;
  final double fovY;
  final double shiftX;
  final double shiftY;

  /// Blends two shots. The look direction is interpolated separately from the
  /// eye so a sweeping move keeps its subject framed.
  static CameraShot lerp(CameraShot a, CameraShot b, double t) {
    final dirA = (a.target - a.eye).normalized();
    final dirB = (b.target - b.eye).normalized();
    final eye = a.eye + (b.eye - a.eye) * t;
    final dir = _slerpDirection(dirA, dirB, t);
    final up = (a.up + (b.up - a.up) * t).normalized();
    return CameraShot(
      eye: eye,
      target: eye + dir,
      up: up,
      fovY: a.fovY + (b.fovY - a.fovY) * t,
      shiftX: a.shiftX + (b.shiftX - a.shiftX) * t,
      shiftY: a.shiftY + (b.shiftY - a.shiftY) * t,
    );
  }

  static Vector3 _slerpDirection(Vector3 a, Vector3 b, double t) {
    final dot = a.dot(b).clamp(-1.0, 1.0);
    final theta = math.acos(dot);
    if (theta < 1e-4) return (a + (b - a) * t).normalized();
    final s = math.sin(theta);
    return (a * (math.sin((1 - t) * theta) / s) + b * (math.sin(t * theta) / s))
        .normalized();
  }
}
