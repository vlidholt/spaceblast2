import 'dart:ui';

/// Virtual joystick with the same geometry and response as SpriteWidget's
/// VirtualJoystick: a 160x160 touch area centered horizontally, 20 units above
/// the bottom of the screen. Dragging 80 units deflects it fully, and holding
/// it fires.
class Joystick {
  static const double size = 160.0;
  static const double bottomMargin = 20.0;
  static const double travel = 80.0;

  /// Deflection, each axis in -1..1.
  Offset value = Offset.zero;

  /// True while a pointer is holding the joystick.
  bool isDown = false;

  int? _pointer;
  Offset? _pointerDownAt;

  /// Where the handle is drawn, relative to the joystick center.
  Offset get handleTarget => Offset(value.dx * 40.0, value.dy * 40.0);

  static Rect area(double gameHeight) => Rect.fromLTWH(
    160.0 - size / 2.0,
    gameHeight - bottomMargin - size,
    size,
    size,
  );

  static Offset center(double gameHeight) =>
      Offset(160.0, gameHeight - bottomMargin - size / 2.0);

  /// [position] is in game units (320 wide).
  bool pointerDown(int pointer, Offset position, double gameHeight) {
    if (_pointer != null) return false;
    if (!area(gameHeight).contains(position)) return false;
    _pointer = pointer;
    _pointerDownAt = position;
    isDown = true;
    return true;
  }

  void pointerMove(int pointer, Offset position) {
    if (pointer != _pointer || !isDown) return;
    final moved = position - _pointerDownAt!;
    value = Offset(
      (moved.dx / travel).clamp(-1.0, 1.0),
      (moved.dy / travel).clamp(-1.0, 1.0),
    );
  }

  void pointerUp(int pointer) {
    if (pointer != _pointer) return;
    _pointer = null;
    _pointerDownAt = null;
    value = Offset.zero;
    isDown = false;
  }

  void reset() {
    value = Offset.zero;
    isDown = false;
    _pointer = null;
    _pointerDownAt = null;
  }
}
