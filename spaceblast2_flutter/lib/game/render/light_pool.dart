import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';

class _Request {
  double x = 0, y = 0, z = 0;
  double r = 0, g = 0, b = 0;
  double intensity = 0;
  double range = 0;
  double priority = 0;
}

class _Slot {
  _Slot(this.node, this.light);
  final Node node;
  final PointLight light;
}

/// A fixed set of point lights handed out every frame to whatever glows the
/// most: explosions, fires, lasers, engines, pickups. Anything that emits
/// light calls [request] between [begin] and [end]; the brightest requests
/// win. flutter_scene culls lights per object by range, so unused lights are
/// given a tiny range and cost nothing.
class LightPool {
  LightPool(Scene scene, {int size = 24}) {
    for (int i = 0; i < size; i++) {
      final light = PointLight(intensity: 0, range: _offRange);
      final node = Node()..addComponent(PointLightComponent(light));
      scene.add(node);
      _slots.add(_Slot(node, light));
    }
  }

  // A range of 0 means infinite in flutter_scene, so "off" is just tiny.
  static const double _offRange = 0.001;

  final List<_Slot> _slots = [];
  final List<_Request> _pool = [];
  int _count = 0;

  void begin() => _count = 0;

  /// Asks for a light at a world position. [range] is in world units.
  void request(
    double x,
    double y,
    double z,
    double r,
    double g,
    double b,
    double intensity,
    double range,
  ) {
    if (intensity <= 0.01 || range <= 0.01) return;
    if (_count == _pool.length) _pool.add(_Request());
    final q = _pool[_count++];
    q
      ..x = x
      ..y = y
      ..z = z
      ..r = r
      ..g = g
      ..b = b
      ..intensity = intensity
      ..range = range
      ..priority = intensity * range * range;
  }

  void end() {
    final active = _pool.sublist(0, _count)
      ..sort((a, b) => b.priority.compareTo(a.priority));
    for (int i = 0; i < _slots.length; i++) {
      final slot = _slots[i];
      if (i < active.length) {
        final q = active[i];
        slot.node.position = Vector3(q.x, q.y, q.z);
        slot.light
          ..color = Vector3(q.r, q.g, q.b)
          ..intensity = q.intensity
          ..range = q.range;
      } else if (slot.light.intensity != 0) {
        slot.light
          ..intensity = 0
          ..range = _offRange;
      }
    }
  }
}
