import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Colors and text styles shared by the menu and the HUD.
abstract final class SbColors {
  static const background = Color(0xFF05030F);
  static const panel = Color(0xFF140E34);
  static const panelEdge = Color(0x55A99BFF);
  static const cyan = Color(0xFF7DF1FF);
  static const cyanDeep = Color(0xFF2AB8F0);
  static const violet = Color(0xFFB77BFF);
  static const magenta = Color(0xFFFF4FA3);
  static const crystal = Color(0xFF6BFFB5);
  static const text = Color(0xFFEAE6FF);
  static const muted = Color(0xFF9D96CF);
  static const danger = Color(0xFFFF3D6E);
  static const gold = Color(0xFFFFD36B);
}

abstract final class SbText {
  static const family = 'Orbitron';

  /// Orbitron's line box (ascent 0.75em, descent 0.25em) puts its capitals
  /// (0.72em tall) 0.11em above the box center. Shift caps-only text down by
  /// this much times the font size to center it optically.
  static const double capsCenterOffset = 0.11;

  static TextStyle label({double size = 9, Color color = SbColors.muted}) =>
      TextStyle(
        fontFamily: family,
        fontSize: size,
        fontWeight: FontWeight.w500,
        letterSpacing: size * 0.22,
        color: color,
      );

  static TextStyle value({
    double size = 14,
    Color color = SbColors.text,
    FontWeight weight = FontWeight.w700,
    double glow = 0.0,
    Color? glowColor,
  }) => TextStyle(
    fontFamily: family,
    fontSize: size,
    fontWeight: weight,
    letterSpacing: size * 0.06,
    color: color,
    fontFeatures: const [ui.FontFeature.tabularFigures()],
    shadows: glow > 0
        ? [
            Shadow(
              color: (glowColor ?? color).withValues(alpha: 0.8),
              blurRadius: glow,
            ),
          ]
        : null,
  );
}

/// Decoded sprites the UI paints directly.
class UiImages {
  UiImages._(this.laser, this.coin, this.powerUps, this.glow);

  final ui.Image laser;
  final ui.Image coin;
  final List<ui.Image> powerUps;
  final ui.Image glow;

  static Future<UiImages> load() async {
    Future<ui.Image> img(String path) async {
      final data = await rootBundle.load(path);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      return (await codec.getNextFrame()).image;
    }

    final results = await Future.wait([
      img('assets/sprites/explosion_particle.png'),
      img('assets/sprites/coin.png'),
      for (int i = 0; i < 4; i++) img('assets/sprites/powerup_$i.png'),
      img('assets/sprites/star_0.png'),
    ]);
    return UiImages._(
      results[0],
      results[1],
      results.sublist(2, 6),
      results[6],
    );
  }
}

/// Lays out [builder]'s content in game units (320 wide, [gameHeight] tall)
/// and scales it to fill the available width.
class GameUnits extends StatelessWidget {
  const GameUnits({super.key, required this.builder});

  final Widget Function(BuildContext context, double gameHeight) builder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = constraints.maxWidth / 320.0;
        final height = constraints.maxHeight / scale;
        return ClipRect(
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: 320,
            maxWidth: 320,
            minHeight: height,
            maxHeight: height,
            child: Transform.scale(
              scale: scale,
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 320,
                height: height,
                child: builder(context, height),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The crystal currency icon: a faceted green gem matching the 3D pickups.
class CrystalIcon extends StatelessWidget {
  const CrystalIcon({super.key, this.size = 14});

  /// Height in logical pixels (the width is about half of it).
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size * 0.62,
      height: size,
      child: CustomPaint(painter: _CrystalPainter()),
    );
  }
}

class _CrystalPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) => paintCrystalGem(canvas, size);

  @override
  bool shouldRepaint(_CrystalPainter oldDelegate) => false;
}

/// Paints the crystal gem into a box of [size] at the canvas origin.
void paintCrystalGem(Canvas canvas, Size size, {double glow = 1.0}) {
  final w = size.width, h = size.height;
  final top = Offset(w / 2, 0);
  final bottom = Offset(w / 2, h);
  final ul = Offset(0, h * 0.28);
  final ur = Offset(w, h * 0.28);
  final ll = Offset(0, h * 0.72);
  final lr = Offset(w, h * 0.72);
  final outline = Path()
    ..moveTo(top.dx, top.dy)
    ..lineTo(ur.dx, ur.dy)
    ..lineTo(lr.dx, lr.dy)
    ..lineTo(bottom.dx, bottom.dy)
    ..lineTo(ll.dx, ll.dy)
    ..lineTo(ul.dx, ul.dy)
    ..close();
  if (glow > 0) {
    canvas.drawPath(
      outline,
      Paint()
        ..color = Color.fromRGBO(107, 255, 181, 0.53 * glow)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, h * 0.18),
    );
  }
  canvas.drawPath(
    outline,
    Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero,
        Offset(w, h),
        const [Color(0xFFD9FFF0), Color(0xFF4FF0A8), Color(0xFF0E8A63)],
        const [0.0, 0.45, 1.0],
      ),
  );
  // Facets: a lit left half and a shaded right half.
  final mid = Offset(w / 2, h * 0.5);
  canvas.drawPath(
    Path()
      ..moveTo(top.dx, top.dy)
      ..lineTo(ur.dx, ur.dy)
      ..lineTo(lr.dx, lr.dy)
      ..lineTo(bottom.dx, bottom.dy)
      ..lineTo(mid.dx, mid.dy)
      ..close(),
    Paint()..color = const Color(0x33003A28),
  );
  final facet = Paint()
    ..color = const Color(0x99FFFFFF)
    ..strokeWidth = h * 0.04
    ..style = PaintingStyle.stroke;
  canvas.drawLine(top, mid, facet);
  canvas.drawLine(mid, bottom, facet..color = const Color(0x44FFFFFF));
  canvas.drawLine(ul, mid, facet..color = const Color(0x55FFFFFF));
  canvas.drawLine(mid, ur, facet);
}
