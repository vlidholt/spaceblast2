// Diagnostic entry point (development only): runs the game and every few
// seconds posts a screenshot and the log, tagged with the user agent, to a
// local receiver. Used to inspect browsers that cannot be driven directly.
import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import '../game/game_controller.dart';
import '../game/sim/power_up_type.dart';
import '../main.dart' as app;
import 'post_png_stub.dart' if (dart.library.js_interop) 'post_png_web.dart';

final List<String> _log = [];

void _add(String line) {
  _log.add(line);
  if (_log.length > 400) _log.removeAt(0);
}

void main() {
  final original = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    _add(message ?? '');
    original(message, wrapWidth: wrapWidth);
  };
  FlutterError.onError = (details) {
    _add('FlutterError: ${details.exceptionAsString()}\n${details.stack}');
  };
  runZonedGuarded(
    () {
      app.main();
      Timer.periodic(const Duration(seconds: 4), (_) => _report());
      // ?autoplay=1 starts a shielded run once loaded (for devices that
      // cannot be tapped remotely).
      if (Uri.base.queryParameters['autoplay'] == '1') {
        Timer.periodic(const Duration(milliseconds: 500), (timer) {
          final c = GameController.current;
          if (c == null || c.phase != GamePhase.menu) return;
          timer.cancel();
          Timer(const Duration(seconds: 3), () {
            c.play();
            for (int i = 0; i < 30; i++) {
              c.world.playerState.activatePowerUp(PowerUpType.shield);
            }
            c.world.joystick.isDown = true;
          });
        });
      }
    },
    (e, st) => _add('Uncaught: $e\n$st'),
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) {
        _add(line);
        parent.print(zone, line);
      },
    ),
  );
}

Future<void> _report() async {
  final c = GameController.current;
  final text = [
    'UA: ${userAgent()}',
    'phase: ${c?.phase.name} fps: ${c?.fps}',
    ..._log,
  ].join('\n');
  try {
    await postText('http://127.0.0.1:8765/log', text);
    final view = RendererBinding.instance.renderViews.first;
    // ignore: invalid_use_of_protected_member
    final layer = view.layer! as OffsetLayer;
    final image = await layer.toImage(view.paintBounds, pixelRatio: 0.6);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await postPng('http://127.0.0.1:8765/snap', data!.buffer.asUint8List());
  } catch (e) {
    _add('report failed: $e');
  }
}
