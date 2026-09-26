import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_scene/scene.dart';

import '../game_controller.dart';
import '../render/game_renderer.dart';
import '../sim/player_state.dart';
import 'app_frame.dart';
import 'hud.dart';
import 'menu.dart';
import 'theme.dart';
import 'world_overlay.dart';

/// Hosts the game: loading screen, 3D view, overlays and input.
class GameShell extends StatefulWidget {
  const GameShell({super.key});

  @override
  State<GameShell> createState() => _GameShellState();
}

class _GameShellState extends State<GameShell> {
  final GameController _controller = GameController();
  UiImages? _images;
  Object? _error;

  @override
  void initState() {
    super.initState();
    // Coins fly to the crystal counter in the HUD.
    PlayerState.coinTarget = const Offset(27, 25);
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        UiImages.load(),
        _controller.load(),
      ]);
      if (!mounted) return;
      setState(() => _images = results[0] as UiImages);
    } catch (e, st) {
      debugPrint('Failed to load the game: $e\n$st');
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: SbColors.background,
      child: AppFrame(
        controller: _controller,
        child: LayoutBuilder(
          builder: (context, constraints) {
            _controller.gameHeight =
                constraints.maxHeight / (constraints.maxWidth / 320.0);
            final images = _images;
            return Stack(
              fit: StackFit.expand,
              children: [
                if (images != null) ...[
                  SceneView(
                    _controller.renderer.scene,
                    camera: _controller.renderer.camera,
                    pixelRatio: math.min(
                      MediaQuery.devicePixelRatioOf(context),
                      GameRenderer.maxPixelRatio,
                    ),
                    onTick: (elapsed, dt) => _controller.tick(dt),
                  ),
                  WorldOverlay(controller: _controller, images: images),
                  Hud(controller: _controller, images: images),
                  MainMenu(controller: _controller, images: images),
                ],
                _LoadingOverlay(
                  progress: _controller.loadProgress,
                  done: images != null,
                  error: _error,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LoadingOverlay extends StatelessWidget {
  const _LoadingOverlay({
    required this.progress,
    required this.done,
    required this.error,
  });

  final ValueListenable<double> progress;
  final bool done;
  final Object? error;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: done,
      child: AnimatedOpacity(
        opacity: done ? 0.0 : 1.0,
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOut,
        child: ColoredBox(
          color: SbColors.background,
          child: Center(
            child: error != null
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Could not start the game.\n$error',
                      textAlign: TextAlign.center,
                      style: SbText.label(size: 12, color: SbColors.danger),
                    ),
                  )
                : ValueListenableBuilder<double>(
                    valueListenable: progress,
                    builder: (context, value, _) => Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'SPACE BLAST',
                          style: SbText.value(
                            size: 22,
                            glow: 14,
                            glowColor: SbColors.cyan,
                          ).copyWith(letterSpacing: 6),
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          width: 160,
                          height: 3,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: value,
                              backgroundColor: const Color(0x22FFFFFF),
                              valueColor: const AlwaysStoppedAnimation(
                                SbColors.cyan,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
