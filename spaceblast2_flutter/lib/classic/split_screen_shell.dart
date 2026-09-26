// Side-by-side demo: the original 2D game on the left, the new 3D game on
// the right, both drawn from the same simulation.
import 'package:flutter/material.dart';

import '../game/game_controller.dart';
import '../game/ui/game_shell.dart';
import 'classic_pane.dart';
import 'classic_parts.dart';

class SplitScreenShell extends StatefulWidget {
  const SplitScreenShell({super.key});

  @override
  State<SplitScreenShell> createState() => _SplitScreenShellState();
}

class _SplitScreenShellState extends State<SplitScreenShell> {
  final GameController _controller = GameController();
  ClassicAssets? _assets;

  @override
  void initState() {
    super.initState();
    ClassicAssets.load().then((assets) {
      if (mounted) setState(() => _assets = assets);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _classicSide()),
        Container(width: 2.0, color: const Color(0xFF000000)),
        Expanded(child: GameShell(controller: _controller)),
      ],
    );
  }

  /// The original's AppFrame: a flat backdrop with the game in the middle at
  /// the mobile aspect ratio.
  Widget _classicSide() {
    return ColoredBox(
      color: const Color(0xFF222244),
      child: LayoutBuilder(
        builder: (context, constraints) {
          var width = constraints.maxWidth;
          var height = constraints.maxHeight;
          if (height / width < 1.5) width = height / 1.5;
          return Center(
            child: SizedBox(
              width: width,
              height: height,
              child: ClipRect(
                child: ListenableBuilder(
                  listenable: _controller,
                  builder: (context, _) {
                    final assets = _assets;
                    if (assets == null ||
                        _controller.phase == GamePhase.loading) {
                      return const ColoredBox(color: Color(0xFF000000));
                    }
                    return ClassicPane(controller: _controller, assets: assets);
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
