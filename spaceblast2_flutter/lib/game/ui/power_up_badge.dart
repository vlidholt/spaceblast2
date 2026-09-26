import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../sim/power_up_type.dart';

/// The HUD marker for an active power-up: a faceted hexagonal gem in the
/// crystals' violet-to-cyan palette with a vector icon, and the remaining
/// time drawn as a glowing edge that drains around the gem.
class PowerUpBadge extends StatelessWidget {
  const PowerUpBadge({
    super.key,
    required this.type,
    required this.fraction,
    this.size = 28,
    this.dim = false,
    this.icon,
  });

  final PowerUpType type;

  /// Remaining time, 1 (full) to 0.
  final double fraction;
  final double size;

  /// True while blinking out.
  final bool dim;

  /// The original game's icon sprite (a 256px image with the icon in the
  /// middle). When null, a vector icon is drawn instead.
  final ui.Image? icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size * 0.92,
      height: size,
      child: CustomPaint(painter: _BadgePainter(type, fraction, dim, icon)),
    );
  }
}

class _BadgePainter extends CustomPainter {
  _BadgePainter(this.type, this.fraction, this.dim, this.icon);

  final PowerUpType type;
  final double fraction;
  final bool dim;
  final ui.Image? icon;

  // Pointy-top hexagon corners, clockwise from the top.
  static List<Offset> _hex(Offset c, double rx, double ry) => [
    for (int i = 0; i < 6; i++)
      Offset(
        c.dx + rx * math.sin(i * math.pi / 3),
        c.dy - ry * math.cos(i * math.pi / 3),
      ),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final rx = size.width / 2;
    final ry = size.height / 2;
    final outer = _hex(c, rx, ry);
    final inner = _hex(c, rx * 0.72, ry * 0.72);
    final alpha = dim ? 0.45 : 1.0;

    Path poly(List<Offset> pts) => Path()..addPolygon(pts, true);

    // Soft glow behind the gem.
    canvas.drawPath(
      poly(outer),
      Paint()
        ..color = Color.fromRGBO(80, 200, 255, 0.35 * alpha)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.height * 0.22),
    );

    // Six crown facets between the outer and inner hexagon, shaded as if lit
    // from the upper left, cycling through the crystal palette.
    const facetColors = [
      Color(0xFF9FF0FF), // top-right
      Color(0xFF3FA8F0), // right
      Color(0xFF2A4FC8), // bottom-right
      Color(0xFF5A2FB8), // bottom-left
      Color(0xFF8A5BF0), // left
      Color(0xFFC9B6FF), // top-left
    ];
    for (int i = 0; i < 6; i++) {
      final j = (i + 1) % 6;
      canvas.drawPath(
        poly([outer[i], outer[j], inner[j], inner[i]]),
        Paint()..color = facetColors[i].withValues(alpha: 0.9 * alpha),
      );
    }

    // The table: a deep glassy center for the icon.
    canvas.drawPath(
      poly(inner),
      Paint()
        ..shader = ui.Gradient.radial(
          c - Offset(rx * 0.2, ry * 0.25),
          ry * 0.9,
          [
            Color.fromRGBO(40, 70, 170, alpha),
            Color.fromRGBO(12, 14, 60, alpha),
          ],
        ),
    );

    // Facet edges.
    final edge = Paint()
      ..color = Color.fromRGBO(230, 250, 255, 0.35 * alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6;
    canvas.drawPath(poly(inner), edge);
    for (int i = 0; i < 6; i++) {
      canvas.drawLine(outer[i], inner[i], edge);
    }

    // Remaining time: a bright rim running clockwise from the top.
    _drawRim(canvas, outer, 1.0, Color.fromRGBO(20, 30, 80, 0.8 * alpha), 1.6);
    _drawRim(
      canvas,
      outer,
      fraction,
      Color.fromRGBO(170, 245, 255, alpha),
      1.6,
      glow: true,
    );

    // Icon.
    final image = icon;
    if (image != null) {
      // The icon fills roughly the middle quarter of the sprite.
      final w = image.width.toDouble(), h = image.height.toDouble();
      final src = Rect.fromCenter(
        center: Offset(w / 2, h / 2),
        width: w * 0.3,
        height: h * 0.3,
      );
      final side = size.height * 0.6;
      canvas.drawImageRect(
        image,
        src,
        Rect.fromCenter(center: c, width: side, height: side),
        Paint()
          ..filterQuality = FilterQuality.medium
          ..color = Color.fromRGBO(255, 255, 255, alpha),
      );
    } else {
      canvas.save();
      canvas.translate(c.dx, c.dy);
      _drawIcon(canvas, size.height * 0.2, alpha);
      canvas.restore();
    }

    // A small glint on the top-left facet.
    canvas.drawCircle(
      Offset.lerp(outer[5], inner[5], 0.45)!,
      size.height * 0.035,
      Paint()..color = Color.fromRGBO(255, 255, 255, 0.9 * alpha),
    );
  }

  void _drawRim(
    Canvas canvas,
    List<Offset> pts,
    double fraction,
    Color color,
    double width, {
    bool glow = false,
  }) {
    if (fraction <= 0) return;
    final path = Path()..moveTo(pts[0].dx, pts[0].dy);
    final total = fraction.clamp(0.0, 1.0) * 6;
    for (int i = 0; i < 6; i++) {
      final a = pts[i];
      final b = pts[(i + 1) % 6];
      if (total >= i + 1) {
        path.lineTo(b.dx, b.dy);
      } else {
        final p = Offset.lerp(a, b, total - i)!;
        path.lineTo(p.dx, p.dy);
        break;
      }
    }
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    if (glow) {
      canvas.drawPath(
        path,
        Paint()
          ..color = color.withValues(alpha: color.a * 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = width * 3
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
      );
    }
    canvas.drawPath(path, paint);
  }

  void _drawIcon(Canvas canvas, double s, double alpha) =>
      paintPowerUpIcon(canvas, type, s, alpha: alpha);

  @override
  bool shouldRepaint(_BadgePainter oldDelegate) =>
      oldDelegate.fraction != fraction ||
      oldDelegate.type != type ||
      oldDelegate.dim != dim ||
      oldDelegate.icon != icon;
}

/// Paints the vector icon for a power-up centered on the origin; [s] is
/// about half the icon's height.
void paintPowerUpIcon(
  Canvas canvas,
  PowerUpType type,
  double s, {
  double alpha = 1.0,
}) {
  final stroke = Paint()
    ..color = Color.fromRGBO(235, 252, 255, alpha)
    ..style = PaintingStyle.stroke
    ..strokeWidth = s * 0.28
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  final fill = Paint()..color = Color.fromRGBO(235, 252, 255, alpha);
  final glow = Paint()
    ..color = Color.fromRGBO(120, 230, 255, 0.8 * alpha)
    ..style = PaintingStyle.stroke
    ..strokeWidth = s * 0.7
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..maskFilter = MaskFilter.blur(BlurStyle.normal, s * 0.35);

  Path path;
  var filled = false;
  switch (type) {
    case PowerUpType.shield:
      path = Path()
        ..moveTo(0, -s * 1.15)
        ..lineTo(s * 0.95, -s * 0.7)
        ..quadraticBezierTo(s * 0.95, s * 0.55, 0, s * 1.15)
        ..quadraticBezierTo(-s * 0.95, s * 0.55, -s * 0.95, -s * 0.7)
        ..close();
    case PowerUpType.speedLaser:
      path = Path()
        ..moveTo(s * 0.35, -s * 1.2)
        ..lineTo(-s * 0.6, s * 0.12)
        ..lineTo(-s * 0.02, s * 0.12)
        ..lineTo(-s * 0.35, s * 1.2)
        ..lineTo(s * 0.62, -s * 0.18)
        ..lineTo(s * 0.02, -s * 0.18)
        ..close();
      filled = true;
    case PowerUpType.sideLaser:
      path = Path()
        ..moveTo(0, s * 0.9)
        ..lineTo(0, -s * 1.1)
        ..moveTo(-s * 0.2, s * 0.9)
        ..lineTo(-s * 1.0, -s * 0.8)
        ..moveTo(s * 0.2, s * 0.9)
        ..lineTo(s * 1.0, -s * 0.8);
    case PowerUpType.speedBoost:
      path = Path()
        ..moveTo(-s * 0.85, -s * 0.05)
        ..lineTo(0, -s * 0.85)
        ..lineTo(s * 0.85, -s * 0.05)
        ..moveTo(-s * 0.85, s * 0.8)
        ..lineTo(0, 0)
        ..lineTo(s * 0.85, s * 0.8);
  }
  canvas.drawPath(path, glow);
  canvas.drawPath(path, filled ? fill : stroke);
}
