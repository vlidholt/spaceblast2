import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_scene/scene.dart' show Scene;

import '../game/game_controller.dart';
import '../game/render/sprite_batch.dart';
import '../game/sim/game_objects.dart';
import '../game/sim/power_up_type.dart';
import 'post_png_stub.dart' if (dart.library.js_interop) 'post_png_web.dart';

/// Development-only service extensions used to inspect and drive the game
/// from tooling: `ext.spaceblast.snap` captures the screen and posts a PNG to
/// a local receiver, `ext.spaceblast.cmd` pokes the game.
final List<String> _logs = [];

/// Records a line for `ext.spaceblast.logs`.
void devLog(String line) {
  _logs.add(line);
  if (_logs.length > 300) _logs.removeAt(0);
}

void registerDevExtensions() {
  final original = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    _logs.add(message ?? '');
    if (_logs.length > 300) _logs.removeAt(0);
    original(message, wrapWidth: wrapWidth);
  };
  FlutterError.onError = (details) {
    _logs.add('FlutterError: ${details.exceptionAsString()}\n${details.stack}');
    FlutterError.presentError(details);
  };

  // Every client posts its user agent and logs to the local receiver, so
  // several browsers can be inspected at once.
  developer.registerExtension('ext.spaceblast.report', (method, params) async {
    final c = GameController.current;
    final text = [
      'UA: ${userAgent()}',
      'phase: ${c?.phase.name}',
      'fps: ${c?.fps}',
      ..._logs,
    ].join('\n');
    await postText(params['url'] ?? 'http://127.0.0.1:8765/log', text);
    return developer.ServiceExtensionResponse.result('{}');
  });

  developer.registerExtension('ext.spaceblast.logs', (method, params) async {
    final out = jsonEncode({'logs': _logs.join('\n')});
    if (params['clear'] == '1') _logs.clear();
    return developer.ServiceExtensionResponse.result(out);
  });

  developer.registerExtension('ext.spaceblast.snap', (method, params) async {
    try {
      final url = params['url'] ?? 'http://127.0.0.1:8765/snap';
      final scale = double.tryParse(params['scale'] ?? '') ?? 1.0;
      final renderView = RendererBinding.instance.renderViews.first;
      // ignore: invalid_use_of_protected_member
      final layer = renderView.layer! as OffsetLayer;
      final image = await layer.toImage(
        renderView.paintBounds,
        pixelRatio: scale,
      );
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await postPng(url, data!.buffer.asUint8List(), only: params['only']);
      return developer.ServiceExtensionResponse.result(
        jsonEncode({'ok': true, 'w': image.width, 'h': image.height}),
      );
    } catch (e, st) {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        '$e\n$st',
      );
    }
  });

  developer.registerExtension('ext.spaceblast.cmd', (method, params) async {
    final c = GameController.current;
    if (c == null && params['cmd'] != 'reload') {
      return developer.ServiceExtensionResponse.error(
        developer.ServiceExtensionResponse.extensionError,
        'no controller',
      );
    }
    final cmd = params['cmd'];
    if (cmd == 'reload') {
      Future.delayed(const Duration(milliseconds: 100), reloadPage);
      return developer.ServiceExtensionResponse.result('{}');
    }
    if (c == null || c.phase == GamePhase.loading) {
      return developer.ServiceExtensionResponse.result(
        jsonEncode({'phase': 'loading'}),
      );
    }
    final j = c.world.joystick;
    switch (cmd) {
      case 'play':
        c.play();
      case 'joy':
        j.value = ui.Offset(
          double.tryParse(params['x'] ?? '0') ?? 0,
          double.tryParse(params['y'] ?? '0') ?? 0,
        );
        j.isDown = params['fire'] == '1';
      case 'coins':
        c.state.coins += int.tryParse(params['n'] ?? '0') ?? 0;
        c.state.store();
      case 'hideui':
        c.debugHideUi = params['on'] != '0';
      case 'boom':
        final w = c.world;
        final kind = ObjectKind.values.byName(
          params['source'] ?? 'asteroidBig',
        );
        c.renderer.effects.bigExplosion(
          double.tryParse(params['x'] ?? '0') ?? 0,
          w.ship.y - (double.tryParse(params['dy'] ?? '160') ?? 160),
          double.tryParse(params['scale'] ?? '1') ?? 1,
          source: kind,
          variant: 0,
        );
      case 'audio':
        await c.audio.start();
        devLog('audio ready: ${c.audio.ready}');
      case 'orient':
        // Streaks moving right, up-right, up and up-left from above the ship.
        final e = c.renderer.effects;
        final sx = c.world.ship.x * 0.01;
        final sy = -(c.world.ship.y - 200) * 0.01 + c.renderer.originY;
        for (final (vx, vy) in [
          (1.0, 0.0),
          (0.7, 0.7),
          (0.0, 1.0),
          (-0.7, 0.7),
        ]) {
          e.sparks.spawn(
            x: sx + vx * 0.6,
            y: sy + vy * 0.6,
            vx: vx * 0.05,
            vy: vy * 0.05,
            life: 3,
            size: 0.08,
            aspect: 5,
            alignToVelocity: true,
            color: const ColorRamp.fade([3, 3, 3, 1]),
          );
          e.debris.spawn(
            x: sx + vx * 1.1,
            y: sy + vy * 1.1,
            vx: vx * 0.05,
            vy: vy * 0.05,
            life: 3,
            size: 0.2,
            aspect: 1.7,
            alignToVelocity: true,
            color: const ColorRamp.fade([3, 1, 1, 1]),
          );
        }
      case 'coin':
        final w = c.world;
        for (int i = 0; i < 3; i++) {
          w.addGameObject(Coin(w), -60.0 + i * 60, w.ship.y - 170);
        }
      case 'pickup':
        final w = c.world;
        for (int i = 0; i < 4; i++) {
          w.addGameObject(
            PowerUp(w, PowerUpType.values[i]),
            -105.0 + i * 70,
            w.ship.y - 140,
          );
        }
      case 'crystal':
        final w = c.world;
        w.addGameObject(AsteroidPowerUp(w), 60, w.ship.y - 150);
      case 'kill':
        c.world.killShip();
      case 'powerup':
        final n = int.tryParse(params['n'] ?? '1') ?? 1;
        for (int i = 0; i < n; i++) {
          c.world.playerState.activatePowerUp(
            PowerUpTypeByName.byName(params['type'] ?? 'shield'),
          );
        }
      case 'skip':
        // Advance the simulation quickly (seconds).
        final secs = double.tryParse(params['s'] ?? '1') ?? 1;
        for (int i = 0; i < secs * 60; i++) {
          c.world.step();
          c.world.events.clear();
        }
    }
    return developer.ServiceExtensionResponse.result(
      jsonEncode({
        'phase': c.phase.name,
        'score': c.world.playerState.score,
        'coins': c.world.playerState.coins,
        'scroll': c.world.scroll,
        'objects': c.world.children.length,
        'gameHeight': c.gameHeight,
        'stateCoins': c.state.coins,
        'time': c.time,
        'fps': c.fps,
        'tickMs': c.tickMs,
        'quality': c.renderer.effects.quality,
        'renderScale': c.renderer.scene.renderScale,
        'ready': Scene.isReadyToRender,
        'eye': c.renderer.camera.eye.toString(),
        'target': c.renderer.camera.target.toString(),
        'fov': c.renderer.camera.lens.fovRadiansY,
        'shiftY': c.renderer.camera.lens.shiftY,
        'sceneRoots': c.renderer.scene.root.children.length,
      }),
    );
  });
}
