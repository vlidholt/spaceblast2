import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../game_controller.dart';
import '../render/game_renderer.dart' show laserColors;
import '../sim/power_up_type.dart';
import 'theme.dart';

const _powerUpNames = {
  PowerUpType.shield: 'SHIELD',
  PowerUpType.speedLaser: 'RAPID',
  PowerUpType.sideLaser: 'SPREAD',
  PowerUpType.speedBoost: 'BOOST',
};

// The original listed the power-ups in this order.
const _powerUpOrder = [
  PowerUpType.shield,
  PowerUpType.sideLaser,
  PowerUpType.speedBoost,
  PowerUpType.speedLaser,
];

/// The start screen, drawn over the 3D hero shot of the ship.
class MainMenu extends StatelessWidget {
  const MainMenu({super.key, required this.controller, required this.images});

  final GameController controller;
  final UiImages images;

  @override
  Widget build(BuildContext context) {
    return GameUnits(
      builder: (context, gameHeight) {
        return AnimatedBuilder(
          animation: Listenable.merge([controller.frame, controller.state]),
          builder: (context, _) {
            final c = controller;
            double show;
            switch (c.phase) {
              case GamePhase.menu:
                show = 1.0;
              case GamePhase.launching:
                show = (1 - c.phaseTime / 0.45).clamp(0.0, 1.0);
              case GamePhase.returning:
                show =
                    ((c.phaseTime - GameController.returnDuration + 0.5) / 0.5)
                        .clamp(0.0, 1.0);
              default:
                show = 0.0;
            }
            if (show <= 0 || c.debugHideUi) return const SizedBox.shrink();
            final eased = Curves.easeOut.transform(show);
            return IgnorePointer(
              ignoring: c.phase != GamePhase.menu,
              child: Opacity(
                opacity: eased,
                child: _MenuContent(
                  controller: c,
                  images: images,
                  gameHeight: gameHeight,
                  slide: 1 - eased,
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _MenuContent extends StatelessWidget {
  const _MenuContent({
    required this.controller,
    required this.images,
    required this.gameHeight,
    required this.slide,
  });

  final GameController controller;
  final UiImages images;
  final double gameHeight;
  final double slide;

  @override
  Widget build(BuildContext context) {
    final compact = gameHeight < 540;
    return Stack(
      children: [
        // Darken the top and bottom so the panels read over the 3D scene.
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: const [
                  Color(0xCC05030F),
                  Color(0x0005030F),
                  Color(0x0005030F),
                  Color(0xE605030F),
                ],
                stops: [0.0, 0.28, compact ? 0.42 : 0.5, 1.0],
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              children: [
                SizedBox(height: compact ? 12 : 22),
                Transform.translate(
                  offset: Offset(0, -40 * slide),
                  child: const _Title(),
                ),
                SizedBox(height: compact ? 8 : 14),
                Transform.translate(
                  offset: Offset(0, -40 * slide),
                  child: _Stats(controller: controller, images: images),
                ),
                const Spacer(),
                Transform.translate(
                  offset: Offset(0, 60 * slide),
                  child: _UpgradePanel(
                    controller: controller,
                    images: images,
                    compact: compact,
                  ),
                ),
                SizedBox(height: compact ? 8 : 12),
                Transform.translate(
                  offset: Offset(0, 80 * slide),
                  child: _BottomBar(controller: controller),
                ),
                SizedBox(height: compact ? 12 : 20),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Title extends StatelessWidget {
  const _Title();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'S P A C E',
          style: SbText.label(size: 10, color: SbColors.cyan).copyWith(
            letterSpacing: 6,
            shadows: const [Shadow(color: SbColors.cyan, blurRadius: 10)],
          ),
        ),
        const SizedBox(height: 2),
        ShaderMask(
          shaderCallback: (rect) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFFFFF), Color(0xFFB9F6FF), Color(0xFF9A7BFF)],
            stops: [0.0, 0.45, 1.0],
          ).createShader(rect),
          child: Text(
            'BLAST',
            style: const TextStyle(
              fontFamily: SbText.family,
              fontSize: 44,
              height: 1.0,
              fontWeight: FontWeight.w900,
              letterSpacing: 6,
              color: Colors.white,
              shadows: [
                Shadow(color: Color(0xAA6FB8FF), blurRadius: 18),
                Shadow(color: Color(0x66B77BFF), blurRadius: 40),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Glass extends StatelessWidget {
  const _Glass({
    required this.child,
    this.padding = const EdgeInsets.all(10),
    this.radius = 14,
  });

  final Widget child;
  final EdgeInsets padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xB0201852), Color(0xB00A0724)],
            ),
            border: Border.all(color: SbColors.panelEdge, width: 1),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.controller, required this.images});

  final GameController controller;
  final UiImages images;

  @override
  Widget build(BuildContext context) {
    final s = controller.state;
    Widget stat(String label, String value, {Color color = SbColors.text}) =>
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: SbText.label(size: 7)),
              const SizedBox(height: 3),
              Text(
                value,
                style: SbText.value(size: 13, color: color, glow: 6),
              ),
            ],
          ),
        );
    return _Glass(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Row(
        children: [
          stat('LAST SCORE', '${s.lastScore}'),
          Container(width: 1, height: 26, color: SbColors.panelEdge),
          const SizedBox(width: 12),
          stat('WEEKLY BEST', '${s.weeklyBestScore}', color: SbColors.gold),
        ],
      ),
    );
  }
}

class _CrystalPrice extends StatelessWidget {
  const _CrystalPrice({
    required this.images,
    required this.price,
    required this.affordable,
    this.size = 10,
  });

  final UiImages images;
  final int? price;
  final bool affordable;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (price == null) {
      return Text(
        'MAX',
        style: SbText.value(size: size, color: SbColors.gold, glow: 6),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CrystalIcon(size: size * 1.1),
        const SizedBox(width: 3),
        Text(
          '$price',
          style: SbText.value(
            size: size,
            color: affordable ? SbColors.crystal : SbColors.muted,
            glow: affordable ? 5 : 0,
          ),
        ),
      ],
    );
  }
}

class _UpgradePanel extends StatelessWidget {
  const _UpgradePanel({
    required this.controller,
    required this.images,
    required this.compact,
  });

  final GameController controller;
  final UiImages images;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final s = controller.state;
    final laserPrice = s.isLaserMaxed ? null : s.laserUpgradePrice();
    return _Glass(
      padding: EdgeInsets.fromLTRB(9, compact ? 7 : 8, 9, compact ? 7 : 8),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                'UPGRADES',
                style: SbText.label(size: 8, color: SbColors.text),
              ),
              const Spacer(),
              _Chip(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CrystalIcon(size: 12),
                    const SizedBox(width: 5),
                    Text(
                      '${s.coins}',
                      style: SbText.value(
                        size: 11,
                        color: SbColors.crystal,
                        glow: 6,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 5 : 6),
          // Laser upgrade.
          _PressButton(
            key: const ValueKey('upgradeLaser'),
            enabled: laserPrice != null && s.coins >= laserPrice,
            onTap: controller.upgradeLaser,
            child: Container(
              height: compact ? 36 : 40,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: const Color(0x66110A30),
                border: Border.all(color: const Color(0x3394E8FF)),
              ),
              child: Row(
                children: [
                  _LaserDisplay(level: s.laserLevel, images: images),
                  if (!s.isLaserMaxed) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(
                        Icons.chevron_right_rounded,
                        size: 14,
                        color: SbColors.muted,
                      ),
                    ),
                    _LaserDisplay(level: s.laserLevel + 1, images: images),
                  ],
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('LASER', style: SbText.label(size: 7)),
                        const SizedBox(height: 3),
                        Text(
                          'LVL ${s.laserLevel + 1}',
                          style: SbText.value(size: 11),
                        ),
                      ],
                    ),
                  ),
                  _CrystalPrice(
                    images: images,
                    price: laserPrice,
                    affordable: laserPrice != null && s.coins >= laserPrice,
                    size: 11,
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: compact ? 5 : 6),
          Row(
            children: [
              for (final type in _powerUpOrder) ...[
                if (type != _powerUpOrder.first) const SizedBox(width: 6),
                Expanded(
                  child: _PowerUpTile(
                    controller: controller,
                    images: images,
                    type: type,
                    compact: compact,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: const Color(0x55053A2A),
        border: Border.all(color: const Color(0x556BFFB5)),
      ),
      child: child,
    );
  }
}

class _PowerUpTile extends StatelessWidget {
  const _PowerUpTile({
    required this.controller,
    required this.images,
    required this.type,
    required this.compact,
  });

  final GameController controller;
  final UiImages images;
  final PowerUpType type;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final s = controller.state;
    final maxed = s.isPowerUpMaxed(type);
    final price = maxed ? null : s.powerUpUpgradePrice(type);
    final level = s.powerupLevel(type);
    return _PressButton(
      key: ValueKey('upgrade_${type.name}'),
      enabled: price != null && s.coins >= price,
      onTap: () => controller.upgradePowerUp(type),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: compact ? 4 : 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: const Color(0x66110A30),
          border: Border.all(color: const Color(0x3394E8FF)),
        ),
        child: Column(
          children: [
            SizedBox(
              width: compact ? 22 : 24,
              height: compact ? 22 : 24,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          SbColors.cyanDeep.withValues(alpha: 0.35),
                          SbColors.cyanDeep.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                  ),
                  ClipRect(
                    child: Transform.scale(
                      scale: 3.6,
                      child: RawImage(
                        image: images.powerUps[type.index],
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.medium,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 2),
            Text(_powerUpNames[type]!, style: SbText.label(size: 5.5)),
            const SizedBox(height: 3),
            // Level pips.
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (int i = 0; i < s.maxPowerUpLevel; i++)
                  Container(
                    width: 4,
                    height: 4,
                    margin: const EdgeInsets.symmetric(horizontal: 0.6),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < level
                          ? SbColors.cyan
                          : const Color(0x33FFFFFF),
                      boxShadow: i < level
                          ? const [
                              BoxShadow(color: SbColors.cyan, blurRadius: 3),
                            ]
                          : null,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            _CrystalPrice(
              images: images,
              price: price,
              affordable: price != null && s.coins >= price,
              size: 8,
            ),
          ],
        ),
      ),
    );
  }
}

/// The laser pattern for a level: 1 to 3 beams in the level's color.
class _LaserDisplay extends StatelessWidget {
  const _LaserDisplay({required this.level, required this.images});

  final int level;
  final UiImages images;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 26,
      height: 26,
      child: CustomPaint(painter: _LaserPainter(level, images.laser)),
    );
  }
}

class _LaserPainter extends CustomPainter {
  _LaserPainter(this.level, this.image);

  final int level;
  final ui.Image image;

  @override
  void paint(Canvas canvas, Size size) {
    final num = level % 3 + 1;
    final c = laserColors[(level ~/ 3) % laserColors.length];
    final color = Color.fromARGB(
      255,
      (c[0] * 255).round(),
      (c[1] * 255).round(),
      (c[2] * 255).round(),
    );
    const offsets = [
      [Offset(0, 0)],
      [Offset(-3, 0), Offset(3, 0)],
      [Offset(-4, 0), Offset(4, 0), Offset(0, -2)],
    ];
    final center = size.center(Offset.zero);
    canvas.drawCircle(
      center,
      11,
      Paint()
        ..color = color.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );
    final src = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    final paint = Paint()
      ..colorFilter = ColorFilter.mode(color, BlendMode.modulate)
      ..blendMode = BlendMode.plus
      ..filterQuality = FilterQuality.medium;
    for (final o in offsets[num - 1]) {
      final p = center + o * 1.4;
      canvas.drawImageRect(
        image,
        src,
        Rect.fromCenter(center: p, width: 30, height: 30),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_LaserPainter oldDelegate) => oldDelegate.level != level;
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final s = controller.state;
    return Row(
      children: [
        _Glass(
          radius: 16,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: SizedBox(
            height: 46,
            child: Row(
              children: [
                _ArrowButton(
                  key: const ValueKey('levelDown'),
                  icon: Icons.chevron_left_rounded,
                  enabled: s.currentStartingLevel > 0,
                  onTap: controller.startLevelDown,
                ),
                SizedBox(
                  width: 50,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('LEVEL', style: SbText.label(size: 6)),
                      const SizedBox(height: 2),
                      Text(
                        '${s.currentStartingLevel + 1}',
                        style: SbText.value(
                          size: 20,
                          glow: 8,
                          glowColor: SbColors.cyan,
                        ),
                      ),
                    ],
                  ),
                ),
                _ArrowButton(
                  key: const ValueKey('levelUp'),
                  icon: Icons.chevron_right_rounded,
                  enabled: s.currentStartingLevel < s.maxStartingLevel,
                  onTap: controller.startLevelUp,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: _PlayButton(controller: controller)),
      ],
    );
  }
}

class _ArrowButton extends StatelessWidget {
  const _ArrowButton({
    super.key,
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _PressButton(
      enabled: enabled,
      dimWhenDisabled: false,
      onTap: onTap,
      child: Container(
        width: 28,
        height: 38,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: enabled ? const Color(0x3394E8FF) : const Color(0x11FFFFFF),
        ),
        child: Icon(
          icon,
          size: 20,
          color: enabled ? SbColors.cyan : const Color(0x44FFFFFF),
        ),
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final t = controller.time;
    final pulse = 0.5 + 0.5 * math.sin(t * 3.0);
    return _PressButton(
      key: const ValueKey('play'),
      onTap: () {
        controller.userGesture();
        controller.play();
      },
      child: Container(
        height: 54,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1E2C74), Color(0xFF141C52)],
          ),
          border: Border.all(
            color: SbColors.cyan.withValues(alpha: 0.55 + 0.25 * pulse),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: SbColors.cyanDeep.withValues(alpha: 0.18 + 0.2 * pulse),
              blurRadius: 14 + 8 * pulse,
            ),
          ],
        ),
        child: Stack(
          children: [
            // Moving sheen.
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: CustomPaint(painter: _SheenPainter((t * 0.35) % 1.6)),
              ),
            ),
            Center(
              // Orbitron's capitals sit high in the line box.
              child: Transform.translate(
                offset: const Offset(-0.4, 20 * SbText.capsCenterOffset),
                child: Text(
                  'PLAY',
                  textHeightBehavior: const TextHeightBehavior(
                    applyHeightToFirstAscent: false,
                    applyHeightToLastDescent: false,
                    leadingDistribution: TextLeadingDistribution.even,
                  ),
                  style: SbText.value(
                    size: 20,
                    glow: 10,
                    glowColor: SbColors.cyan,
                  ).copyWith(letterSpacing: 5, height: 1.0),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheenPainter extends CustomPainter {
  _SheenPainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final x = (t - 0.3) * size.width * 1.4;
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(x - 40, 0),
          Offset(x + 40, size.height),
          const [Color(0x00FFFFFF), Color(0x22FFFFFF), Color(0x00FFFFFF)],
          const [0.0, 0.5, 1.0],
        ),
    );
  }

  @override
  bool shouldRepaint(_SheenPainter oldDelegate) => oldDelegate.t != t;
}

/// Scales down while pressed, like a physical button. A disabled button
/// ignores taps and is dimmed.
class _PressButton extends StatefulWidget {
  const _PressButton({
    super.key,
    required this.onTap,
    required this.child,
    this.enabled = true,
    this.dimWhenDisabled = true,
  });

  final VoidCallback onTap;
  final Widget child;
  final bool enabled;
  final bool dimWhenDisabled;

  @override
  State<_PressButton> createState() => _PressButtonState();
}

class _PressButtonState extends State<_PressButton> {
  bool _down = false;

  @override
  void didUpdateWidget(_PressButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) _down = false;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return Opacity(
        opacity: widget.dimWhenDisabled ? 0.45 : 1.0,
        child: MouseRegion(
          cursor: SystemMouseCursors.forbidden,
          child: widget.child,
        ),
      );
    }
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTap: () {
          setState(() => _down = false);
          widget.onTap();
        },
        child: AnimatedScale(
          scale: _down ? 0.94 : 1.0,
          duration: const Duration(milliseconds: 90),
          child: AnimatedOpacity(
            opacity: _down ? 0.8 : 1.0,
            duration: const Duration(milliseconds: 90),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
