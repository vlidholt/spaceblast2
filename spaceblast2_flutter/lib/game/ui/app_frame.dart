import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../game_controller.dart';

/// Keeps the game in the original's mobile aspect ratio (at least 1.5:1
/// portrait). On wider screens the sides get a dark, slowly moving nebula
/// gradient whose color follows the action (calm violet, red for bosses,
/// cyan for speed boosts).
class AppFrame extends StatelessWidget {
  const AppFrame({super.key, required this.controller, required this.child});

  final GameController controller;
  final Widget child;

  static const minRatio = 1.5;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final ratio = constraints.maxHeight / constraints.maxWidth;
        if (ratio > minRatio) {
          return child;
        }
        final width = constraints.maxHeight / minRatio;
        final inset = (constraints.maxWidth - width) / 2;
        return Stack(
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _BorderPainter(controller, inset, width),
                ),
              ),
            ),
            Positioned(
              top: 0,
              bottom: 0,
              left: inset,
              width: width,
              child: ClipRect(child: child),
            ),
          ],
        );
      },
    );
  }
}

class _BorderPainter extends CustomPainter {
  _BorderPainter(this.c, this.inset, this.gameWidth) : super(repaint: c.frame);

  final GameController c;
  final double inset;
  final double gameWidth;

  static const _calm = [
    Color(0xFF2A1466),
    Color(0xFF0E1E5C),
    Color(0xFF3A1060),
  ];
  static const _boss = [
    Color(0xFF6A0C2A),
    Color(0xFF3A0620),
    Color(0xFF7A1A10),
  ];
  static const _boost = [
    Color(0xFF0B4A6A),
    Color(0xFF123C8C),
    Color(0xFF1A7A8A),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final t = c.time;
    // The blobs are larger than the side strips; keep them off neighbors.
    canvas.clipRect(Offset.zero & size);
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF05030F),
    );

    final boss = c.bossMood;
    final boost = c.boostMood * (1 - boss);
    final danger = c.dangerMood;
    Color mood(int i) {
      var col = Color.lerp(_calm[i], _boss[i], boss)!;
      col = Color.lerp(col, _boost[i], boost)!;
      return Color.lerp(col, const Color(0xFF1A0610), danger * 0.6)!;
    }

    // Soft drifting blobs on each side.
    final h = size.height;
    for (int side = 0; side < 2; side++) {
      final left = side == 0;
      final x0 = left ? 0.0 : inset + gameWidth;
      final w = inset;
      if (w <= 1) continue;
      for (int i = 0; i < 3; i++) {
        final phase = i * 2.1 + side * 1.3;
        final cx = x0 + w * (0.5 + 0.35 * math.sin(t * 0.07 + phase));
        final cy = h * (0.5 + 0.42 * math.sin(t * 0.05 + phase * 1.7));
        final r = h * (0.45 + 0.1 * math.sin(t * 0.11 + phase));
        final col = mood(i);
        canvas.drawCircle(
          Offset(cx, cy),
          r,
          Paint()
            ..shader = ui.Gradient.radial(Offset(cx, cy), r, [
              col.withValues(alpha: 0.55),
              col.withValues(alpha: 0.0),
            ]),
        );
      }
    }

    // Faint drifting specks for depth.
    final speck = Paint()..color = const Color(0x55CFC8FF);
    final rnd = math.Random(3);
    for (int i = 0; i < 70; i++) {
      final left = i.isEven;
      final bx = rnd.nextDouble();
      final by = rnd.nextDouble();
      final speed = 4 + rnd.nextDouble() * 10;
      final x = left ? bx * inset : inset + gameWidth + bx * inset;
      final y = (by * h + t * speed) % h;
      final r = 0.4 + rnd.nextDouble() * 0.9;
      canvas.drawCircle(Offset(x, y), r, speck);
    }

    // Glowing seams along the game area's edges.
    final edgeColor = Color.lerp(
      const Color(0xFF7DF1FF),
      const Color(0xFFFF3D6E),
      boss,
    )!;
    final pulse =
        0.55 +
        0.15 * math.sin(t * 1.3) +
        0.3 * boss * (0.5 + 0.5 * math.sin(t * 4));
    for (final x in [inset, inset + gameWidth]) {
      final rect = Rect.fromLTWH(x - 14, 0, 28, h);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = ui.Gradient.linear(
            rect.centerLeft,
            rect.centerRight,
            [
              edgeColor.withValues(alpha: 0.0),
              edgeColor.withValues(alpha: 0.18 * pulse),
              edgeColor.withValues(alpha: 0.0),
            ],
            const [0.0, 0.5, 1.0],
          ),
      );
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, h),
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(x, 0),
            Offset(x, h),
            [
              edgeColor.withValues(alpha: 0.0),
              edgeColor.withValues(alpha: 0.5 * pulse),
              edgeColor.withValues(alpha: 0.0),
            ],
            const [0.0, 0.5, 1.0],
          )
          ..strokeWidth = 1.0,
      );
    }

    // Vignette toward the outer edges.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.radial(
          size.center(Offset.zero),
          size.longestSide * 0.7,
          [const Color(0x00000000), const Color(0xAA000000)],
        ),
    );
  }

  @override
  bool shouldRepaint(covariant _BorderPainter oldDelegate) =>
      oldDelegate.inset != inset || oldDelegate.gameWidth != gameWidth;
}
