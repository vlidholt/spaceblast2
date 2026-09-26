import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game_controller.dart';
import '../sim/joystick.dart';
import '../sim/power_up_type.dart';
import 'power_up_badge.dart';
import 'theme.dart';

/// In-game heads-up display: crystals (coins) on the left, score on the
/// right, active power-up timers underneath.
class Hud extends StatelessWidget {
  const Hud({super.key, required this.controller, required this.images});

  final GameController controller;
  final UiImages images;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: GameUnits(
        builder: (context, gameHeight) => AnimatedBuilder(
          animation: controller.frame,
          builder: (context, _) {
            final c = controller;
            final show = switch (c.phase) {
              GamePhase.launching => (c.phaseTime / 1.2 - 0.3).clamp(0.0, 1.0),
              GamePhase.playing => 1.0,
              GamePhase.returning => (1 - c.phaseTime / 0.5).clamp(0.0, 1.0),
              _ => 0.0,
            };
            if (show <= 0 || c.debugHideUi) return const SizedBox.shrink();
            final slide = (1 - show) * -30;
            return Opacity(
              opacity: show,
              child: Transform.translate(
                offset: Offset(0, slide),
                child: Stack(
                  children: [
                    Positioned(
                      left: 10,
                      top: 10,
                      child: _CoinCounter(controller: c, images: images),
                    ),
                    Positioned(
                      right: 12,
                      top: 10,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _PowerUpTimers(controller: c, images: images),
                          const SizedBox(width: 10),
                          _ScoreCounter(controller: c),
                        ],
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      top: Joystick.center(gameHeight).dy - 82,
                      child: _ControlsHint(controller: c),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Holds a HUD value at the shared bar height (no box around it).
class _Pill extends StatelessWidget {
  const _Pill({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(height: 30, child: child);
  }
}

class _CoinCounter extends StatelessWidget {
  const _CoinCounter({required this.controller, required this.images});

  final GameController controller;
  final UiImages images;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final pulse = math.max(0.0, 1.0 - (c.time - c.coinTime) / 0.3);
    return Transform.scale(
      scale: 1.0 + pulse * 0.08,
      alignment: Alignment.centerLeft,
      child: _Pill(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CrystalIcon(size: 15),
            const SizedBox(width: 6),
            Text(
              '${c.coins.value}',
              style: SbText.value(
                size: 13,
                color: Color.lerp(SbColors.text, SbColors.crystal, pulse)!,
                glow: 6,
                glowColor: SbColors.crystal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScoreCounter extends StatelessWidget {
  const _ScoreCounter({required this.controller});

  final GameController controller;

  static TextStyle _style(Color color) => SbText.value(
    size: 14,
    color: color,
    glow: 8,
    glowColor: SbColors.cyan,
  );

  /// Orbitron has no fixed-width digits, so the score gets a box as wide as
  /// its widest possible value; otherwise everything next to it would shift
  /// whenever the score changes.
  static double _boxWidth(int digits) {
    final painter = TextPainter(
      text: TextSpan(text: '8' * digits, style: _style(SbColors.text)),
      textDirection: TextDirection.ltr,
    )..layout();
    return painter.width.ceilToDouble();
  }

  static final Map<int, double> _widths = {};

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final pulse = math.max(0.0, 1.0 - (c.time - c.scoreTime) / 0.3);
    final text = '${c.score.value}'.padLeft(6, '0');
    final width = _widths.putIfAbsent(
      text.length,
      () => _boxWidth(text.length),
    );
    return Transform.scale(
      scale: 1.0 + pulse * 0.06,
      alignment: Alignment.centerRight,
      child: _Pill(
        child: SizedBox(
          width: width,
          child: Align(
            alignment: Alignment.centerRight,
            child: Text(
              text,
              style: _style(Color.lerp(SbColors.text, SbColors.cyan, pulse)!),
            ),
          ),
        ),
      ),
    );
  }
}

class _PowerUpTimers extends StatefulWidget {
  const _PowerUpTimers({required this.controller, required this.images});

  final GameController controller;
  final UiImages images;

  @override
  State<_PowerUpTimers> createState() => _PowerUpTimersState();
}

/// Animates badges in (pop with a small overshoot) and out (fade and
/// shrink), and animates each slot's width so the others slide into place.
class _PowerUpTimersState extends State<_PowerUpTimers> {
  static const double _slotWidth = 33.0;
  static const double _inSeconds = 0.35;
  static const double _outSeconds = 0.3;

  final Map<PowerUpType, double> _presence = {};
  final Map<PowerUpType, double> _lastFraction = {};
  double? _lastTime;

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final ps = c.playerState;
    final state = c.state;
    final dt = _lastTime == null ? 0.0 : (c.time - _lastTime!).clamp(0.0, 0.1);
    _lastTime = c.time;

    // Each badge keeps a fixed-size slot. Slots are laid out from the right
    // (next to the score) with eased widths, so when a badge comes or goes
    // the ones further left slide smoothly, while the badge itself scales
    // around its own center.
    final entries = <({PowerUpType type, double p, bool active, int left})>[];
    for (final type in PowerUpType.values) {
      final left = c.phase == GamePhase.playing ? ps.framesLeft(type) : 0;
      final active = left > 0;
      var p = _presence[type] ?? 0.0;
      p = active
          ? math.min(1.0, p + dt / _inSeconds)
          : math.max(0.0, p - dt / _outSeconds);
      _presence[type] = p;
      if (p <= 0) {
        _lastFraction.remove(type);
        continue;
      }
      if (active) {
        final total = type == PowerUpType.shield
            ? math.max(
                state.powerUpFrames(PowerUpType.shield),
                state.powerUpFrames(PowerUpType.speedBoost) + 60,
              )
            : state.powerUpFrames(type);
        _lastFraction[type] = (left / total).clamp(0.0, 1.0);
      }
      entries.add((type: type, p: p, active: active, left: left));
    }

    final children = <Widget>[];
    double right = 0;
    for (final e in entries.reversed) {
      final scale = e.active
          ? Curves.easeOutBack.transform(e.p)
          : 0.55 + 0.45 * Curves.easeOut.transform(e.p);
      final blinking =
          e.active && e.left < 60 && (c.world.stepCount ~/ 6).isOdd;
      children.add(
        Positioned(
          right: right,
          top: 0,
          width: _slotWidth,
          height: 30,
          child: Opacity(
            opacity: Curves.easeOut.transform(e.p),
            child: Transform.scale(
              scale: scale,
              child: Center(
                child: PowerUpBadge(
                  type: e.type,
                  fraction: _lastFraction[e.type] ?? 0.0,
                  dim: blinking,
                  icon: widget.images.powerUps[e.type.index],
                ),
              ),
            ),
          ),
        ),
      );
      right += _slotWidth * Curves.easeInOutCubic.transform(e.p);
    }
    return SizedBox(
      width: right,
      height: 30,
      child: Stack(clipBehavior: Clip.none, children: children),
    );
  }
}

/// A short reminder of the controls at the start of a run.
class _ControlsHint extends StatelessWidget {
  const _ControlsHint({required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final t = c.phase == GamePhase.playing
        ? c.phaseTime + GameController.launchDuration
        : c.phase == GamePhase.launching
        ? c.phaseTime
        : 99.0;
    final fadeIn = ((t - 1.0) / 0.5).clamp(0.0, 1.0);
    final fadeOut = (1.0 - (t - 5.5) / 0.8).clamp(0.0, 1.0);
    final opacity = fadeIn * fadeOut;
    if (opacity <= 0) return const SizedBox.shrink();
    return Opacity(
      opacity: opacity,
      child: Column(
        children: [
          Text(
            'DRAG TO FLY  ·  HOLD TO FIRE',
            textAlign: TextAlign.center,
            style: SbText.label(size: 7, color: SbColors.cyan),
          ),
        ],
      ),
    );
  }
}
