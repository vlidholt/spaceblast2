import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../game_controller.dart';
import '../sim/game_objects.dart';
import '../sim/joystick.dart';
import '../sim/player_state.dart';
import '../sim/world.dart';
import 'theme.dart';

/// 2D elements anchored to the playfield, painted in game units on top of the
/// 3D view: level titles, the boss health bar, coins flying to the HUD, the
/// joystick and the screen flash.
class WorldOverlay extends StatefulWidget {
  const WorldOverlay({
    super.key,
    required this.controller,
    required this.images,
  });

  final GameController controller;
  final UiImages images;

  @override
  State<WorldOverlay> createState() => _WorldOverlayState();
}

class _WorldOverlayState extends State<WorldOverlay> {
  final _handle = _Spring();

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return GameUnits(
      builder: (context, gameHeight) {
        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (e) {
            c.userGesture();
            if (c.phase == GamePhase.playing ||
                c.phase == GamePhase.launching) {
              c.world.joystick.pointerDown(
                e.pointer,
                e.localPosition,
                gameHeight,
              );
            }
          },
          onPointerMove: (e) =>
              c.world.joystick.pointerMove(e.pointer, e.localPosition),
          onPointerUp: (e) => c.world.joystick.pointerUp(e.pointer),
          onPointerCancel: (e) => c.world.joystick.pointerUp(e.pointer),
          child: CustomPaint(
            size: Size(320, gameHeight),
            painter: _OverlayPainter(c, widget.images, _handle),
          ),
        );
      },
    );
  }
}

/// The joystick handle's elastic return, like the original's elasticOut tween.
class _Spring {
  Offset pos = Offset.zero;
  Offset vel = Offset.zero;
  double lastTime = 0;

  Offset update(Offset target, double time, bool held) {
    final dt = (time - lastTime).clamp(0.0, 0.05);
    lastTime = time;
    if (held) {
      pos = target;
      vel = Offset.zero;
      return pos;
    }
    const k = 260.0;
    const damping = 9.0;
    final force = (target - pos) * k - vel * damping;
    vel += force * dt;
    pos += vel * dt;
    return pos;
  }
}

class _OverlayPainter extends CustomPainter {
  _OverlayPainter(this.c, this.images, this.handle) : super(repaint: c.frame);

  final GameController c;
  final UiImages images;
  final _Spring handle;

  static final Map<int, TextPainter> _labels = {};

  TextPainter _label(int level) => _labels.putIfAbsent(level, () {
    return TextPainter(
      text: TextSpan(
        text: 'LEVEL $level',
        style: const TextStyle(
          fontFamily: SbText.family,
          letterSpacing: 10.0,
          color: Color(0xffffffff),
          fontSize: 24.0,
          fontWeight: FontWeight.w600,
          shadows: [
            Shadow(color: Color(0xCC7DF1FF), blurRadius: 12),
            Shadow(color: Color(0x99B77BFF), blurRadius: 28),
          ],
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (c.phase == GamePhase.loading) return;
    final world = c.world;
    final a = c.alpha;
    final showWorld = c.phase != GamePhase.menu;

    if (showWorld) {
      for (final obj in world.children) {
        if (obj is LevelLabel) _paintLevelLabel(canvas, obj, a);
      }
      final boss = world.playerState.boss;
      if (boss != null && boss.attached) _paintBossBar(canvas, boss, a);
      _paintCoinFlights(canvas, world, a);
    }

    if (c.phase == GamePhase.playing ||
        c.phase == GamePhase.launching ||
        (c.phase == GamePhase.returning && c.phaseTime < 0.6)) {
      _paintJoystick(canvas, size, world);
    }

    // Screen flash (the original's 1s white fade), slightly softened.
    final flash = 1.0 - (c.time - c.flashTime) / 1.0;
    if (flash > 0) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..color = Color.fromARGB(
            (flash * flash * 235).round(),
            255,
            250,
            245,
          ),
      );
    }
  }

  void _paintLevelLabel(Canvas canvas, LevelLabel lbl, double a) {
    final x = lbl.prevX + (lbl.x - lbl.prevX) * a;
    final y = lbl.prevY + (lbl.y - lbl.prevY) * a;
    final p = c.levelToScreen(x, y);
    if (p.dy < -60 || p.dy > c.gameHeight + 60) return;
    final tp = _label(lbl.level);
    // A thin line sweeps out from behind the text.
    final lineW = 120.0;
    final linePaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(p.dx - lineW, 0),
        Offset(p.dx + lineW, 0),
        const [Color(0x007DF1FF), Color(0xAA7DF1FF), Color(0x007DF1FF)],
        const [0.0, 0.5, 1.0],
      )
      ..strokeWidth = 1.0;
    canvas.drawLine(
      Offset(p.dx - lineW, p.dy - 6),
      Offset(p.dx + lineW, p.dy - 6),
      linePaint,
    );
    canvas.drawLine(
      Offset(p.dx - lineW, p.dy + tp.height + 6),
      Offset(p.dx + lineW, p.dy + tp.height + 6),
      linePaint,
    );
    // Orbitron's capitals sit high in the line box; center them between the
    // lines.
    tp.paint(
      canvas,
      Offset(p.dx - tp.width / 2, p.dy + 24.0 * SbText.capsCenterOffset),
    );
  }

  void _paintBossBar(Canvas canvas, EnemyBoss boss, double a) {
    final x = boss.prevBarX + (boss.barX - boss.prevBarX) * a;
    final y = boss.prevBarY + (boss.barY - boss.prevBarY) * a;
    final p = c.levelToScreen(x, y);
    const w = 60.0, h = 10.0;
    final rect = Rect.fromCenter(center: p, width: w, height: h);
    final r = RRect.fromRectAndRadius(rect, const Radius.circular(2));
    canvas.drawRRect(
      r.inflate(3),
      Paint()
        ..color = const Color(0x66FF3D6E)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawRRect(r, Paint()..color = const Color(0xAA12081E));
    final fillRect = Rect.fromLTRB(
      rect.left + 2,
      rect.top + 2,
      rect.left + 2 + (w - 4) * boss.power,
      rect.bottom - 2,
    );
    canvas.drawRect(
      fillRect,
      Paint()
        ..shader = ui.Gradient.linear(
          fillRect.topLeft,
          fillRect.bottomLeft,
          const [Color(0xFFFFFFFF), Color(0xFFFF6B8F)],
        ),
    );
    canvas.drawRRect(
      r,
      Paint()
        ..color = const Color(0xFFFFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );
  }

  void _paintCoinFlights(Canvas canvas, GameWorld world, double a) {
    for (final flight in world.playerState.coinFlights) {
      final elapsed =
          (math.max(0, flight.steps - 1) + a) / GameWorld.stepsPerSecond;
      final t = (elapsed / CoinFlight.duration).clamp(0.0, 1.0);
      final pos = flight.positionAt(t);
      // Same growth and spin as the original's flying coin.
      final scale = 0.7 + 0.5 * t;
      final rot = t * math.pi * 2;
      final w = 11.0 * scale, h = 18.0 * scale;
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(rot);
      canvas.translate(-w / 2, -h / 2);
      paintCrystalGem(canvas, Size(w, h));
      canvas.restore();
    }
  }

  void _paintJoystick(Canvas canvas, Size size, GameWorld world) {
    final j = world.joystick;
    final center = Joystick.center(size.height);
    final handlePos = handle.update(
      j.handleTarget,
      c.time,
      j.isDown || j.value != Offset.zero,
    );
    final active = j.isDown || j.value != Offset.zero;
    final fade = c.phase == GamePhase.launching
        ? (c.phaseTime / GameController.launchDuration).clamp(0.0, 1.0)
        : c.phase == GamePhase.returning
        ? (1 - c.phaseTime / 0.6).clamp(0.0, 1.0)
        : 1.0;

    final ringAlpha = (active ? 0.75 : 0.4) * fade;
    // Soft base.
    canvas.drawCircle(
      center,
      44,
      Paint()
        ..shader = ui.Gradient.radial(center, 44, [
          Color.fromRGBO(20, 14, 52, 0.35 * fade),
          Color.fromRGBO(125, 241, 255, 0.10 * fade),
        ]),
    );
    canvas.drawCircle(
      center,
      40,
      Paint()
        ..color = Color.fromRGBO(125, 241, 255, ringAlpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    // Tick marks.
    final tick = Paint()
      ..color = Color.fromRGBO(125, 241, 255, ringAlpha * 0.8)
      ..strokeWidth = 1.2;
    for (int i = 0; i < 4; i++) {
      final ang = i * math.pi / 2;
      final d = Offset(math.cos(ang), math.sin(ang));
      canvas.drawLine(center + d * 44, center + d * 49, tick);
    }
    final hp = center + handlePos;
    canvas.drawCircle(
      hp,
      25,
      Paint()
        ..color = Color.fromRGBO(125, 241, 255, (active ? 0.35 : 0.15) * fade)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawCircle(
      hp,
      25,
      Paint()
        ..shader = ui.Gradient.radial(
          hp + const Offset(-6, -8),
          30,
          [
            Color.fromRGBO(255, 255, 255, (active ? 0.7 : 0.45) * fade),
            Color.fromRGBO(190, 240, 255, (active ? 0.45 : 0.25) * fade),
            Color.fromRGBO(120, 150, 230, (active ? 0.35 : 0.18) * fade),
          ],
          const [0.0, 0.5, 1.0],
        ),
    );
  }

  @override
  bool shouldRepaint(covariant _OverlayPainter oldDelegate) => true;
}
