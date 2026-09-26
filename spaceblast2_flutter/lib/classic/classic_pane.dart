// The original game's screens (menu and game) for the split-screen demo,
// wired to the shared GameController.
import 'package:flutter/material.dart';
import 'package:spritewidget/spritewidget.dart';

import '../game/game_controller.dart';
import '../game/sim/persistent_state.dart';
import '../game/sim/power_up_type.dart';
import 'classic_game_node.dart';
import 'classic_parts.dart';

const Color _darkTextColor = Color(0xff3c3f4a);

/// Shows the original menu, or the original game drawn from the shared
/// simulation while a run is on.
class ClassicPane extends StatelessWidget {
  const ClassicPane({
    super.key,
    required this.controller,
    required this.assets,
  });

  final GameController controller;
  final ClassicAssets assets;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final inGame =
            controller.phase == GamePhase.launching ||
            controller.phase == GamePhase.playing;
        if (!inGame) {
          return _ClassicMenu(controller: controller, assets: assets);
        }
        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) {
            controller.userGesture();
            controller.world.joystick.pointerDown(
              e.pointer,
              _toGame(context, e.localPosition),
              controller.gameHeight,
            );
          },
          onPointerMove: (e) => controller.world.joystick.pointerMove(
            e.pointer,
            _toGame(context, e.localPosition),
          ),
          onPointerUp: (e) => controller.world.joystick.pointerUp(e.pointer),
          onPointerCancel: (e) =>
              controller.world.joystick.pointerUp(e.pointer),
          child: _ClassicGame(
            // A new run is a new world, and a new node tree.
            key: ObjectKey(controller.world),
            controller: controller,
            assets: assets,
          ),
        );
      },
    );
  }

  static Offset _toGame(BuildContext context, Offset local) {
    final width = context.size?.width ?? 320.0;
    return local * (320.0 / width);
  }
}

class _ClassicGame extends StatefulWidget {
  const _ClassicGame({
    super.key,
    required this.controller,
    required this.assets,
  });

  final GameController controller;
  final ClassicAssets assets;

  @override
  State<_ClassicGame> createState() => _ClassicGameState();
}

class _ClassicGameState extends State<_ClassicGame> {
  late final ClassicGameNode _node = ClassicGameNode(
    widget.controller,
    widget.assets,
  );

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SpriteWidget(
      _node,
      transformMode: SpriteBoxTransformMode.fixedWidth,
    );
  }
}

/// The original MainScene: scores, upgrades, starting level and Play.
class _ClassicMenu extends StatefulWidget {
  const _ClassicMenu({required this.controller, required this.assets});

  final GameController controller;
  final ClassicAssets assets;

  @override
  State<_ClassicMenu> createState() => _ClassicMenuState();
}

class _ClassicMenuState extends State<_ClassicMenu> {
  late final _MainSceneBackgroundNode _background = _MainSceneBackgroundNode(
    widget.assets,
  );

  GameController get controller => widget.controller;
  ClassicAssets get assets => widget.assets;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // The original CoordinateSystem: 320 units wide, height to fit.
        final height = constraints.maxHeight * 320.0 / constraints.maxWidth;
        return Listener(
          onPointerDown: (_) => controller.userGesture(),
          child: FittedBox(
            fit: BoxFit.fitWidth,
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: 320.0,
              height: height,
              child: DefaultTextStyle(
                style: const TextStyle(
                  fontFamily: 'Orbitron',
                  fontSize: 20.0,
                  color: Color(0xffffffff),
                ),
                child: ListenableBuilder(
                  listenable: controller.state,
                  builder: (context, _) => Stack(
                    children: [
                      Positioned.fill(
                        child: SpriteWidget(
                          _background,
                          transformMode: SpriteBoxTransformMode.fixedWidth,
                        ),
                      ),
                      Column(
                        children: [
                          SizedBox(
                            width: 320.0,
                            height: 98.0,
                            child: _TopBar(controller.state, assets),
                          ),
                          Expanded(child: _CenterArea(controller, assets)),
                          SizedBox(
                            width: 320.0,
                            height: 93.0,
                            child: _BottomBar(controller, assets),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar(this.gameState, this.assets);

  final PersistentGameState gameState;
  final ClassicAssets assets;

  @override
  Widget build(BuildContext context) {
    const scoreLabelStyle = TextStyle(
      fontFamily: 'Orbitron',
      fontSize: 20.0,
      fontWeight: FontWeight.w500,
      color: _darkTextColor,
    );
    return Stack(
      children: [
        const Positioned(
          left: 18.0,
          top: 13.0,
          child: Text('Last Score', style: scoreLabelStyle),
        ),
        const Positioned(
          left: 18.0,
          top: 39.0,
          child: Text('Weekly Best', style: scoreLabelStyle),
        ),
        Positioned(
          right: 18.0,
          top: 13.0,
          child: Text('${gameState.lastScore}', style: scoreLabelStyle),
        ),
        Positioned(
          right: 18.0,
          top: 39.0,
          child: Text('${gameState.weeklyBestScore}', style: scoreLabelStyle),
        ),
        Positioned(
          left: 18.0,
          top: 80.0,
          child: TextureImage(
            texture: assets.ui['icn_crystal.png']!,
            width: 12.0,
            height: 18.0,
          ),
        ),
        Positioned(
          left: 36.0,
          top: 82.5,
          child: Text(
            '${gameState.coins}',
            style: const TextStyle(
              fontSize: 16.0,
              fontWeight: FontWeight.w500,
              color: _darkTextColor,
            ),
          ),
        ),
      ],
    );
  }
}

class _CenterArea extends StatelessWidget {
  const _CenterArea(this.controller, this.assets);

  final GameController controller;
  final ClassicAssets assets;

  PersistentGameState get gameState => controller.state;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text('Upgrade Laser'),
        _buildLaserUpgradeButton(),
        const Text('Upgrade Power-Ups'),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildPowerUpButton(PowerUpType.shield),
            _buildPowerUpButton(PowerUpType.sideLaser),
            _buildPowerUpButton(PowerUpType.speedBoost),
            _buildPowerUpButton(PowerUpType.speedLaser),
          ],
        ),
      ],
    );
  }

  Widget _buildPowerUpButton(PowerUpType type) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        children: [
          TextureButton(
            texture: assets.ui['btn_powerup_${type.index}.png']!,
            width: 57.0,
            height: 57.0,
            label: '${gameState.powerUpUpgradePrice(type)}',
            labelOffset: const Offset(3.0, 20.5),
            textStyle: const TextStyle(
              fontFamily: 'Orbitron',
              fontSize: 11.0,
              color: _darkTextColor,
            ),
            onPressed: () => controller.upgradePowerUp(type),
          ),
          Padding(
            padding: const EdgeInsets.all(5.0),
            child: Text(
              'Lvl ${gameState.powerupLevel(type) + 1}',
              style: const TextStyle(fontSize: 12.0),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLaserUpgradeButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0.0, 8.0, 0.0, 18.0),
      child: Stack(
        children: [
          TextureButton(
            texture: assets.ui['btn_laser_upgrade.png']!,
            width: 137.0,
            height: 63.0,
            label: '${gameState.laserUpgradePrice()}',
            labelOffset: const Offset(2.0, 20.0),
            textStyle: const TextStyle(
              fontFamily: 'Orbitron',
              fontSize: 12.0,
              color: _darkTextColor,
            ),
            onPressed: controller.upgradeLaser,
          ),
          Positioned(
            left: 19.5,
            top: 14.0,
            child: _LaserDisplay(gameState.laserLevel, assets),
          ),
          Positioned(
            right: 19.5,
            top: 14.0,
            child: _LaserDisplay(gameState.laserLevel + 1, assets),
          ),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar(this.controller, this.assets);

  final GameController controller;
  final ClassicAssets assets;

  @override
  Widget build(BuildContext context) {
    final ui = assets.ui;
    final level = controller.state.currentStartingLevel;
    return Stack(
      children: [
        Positioned(
          left: 18.0,
          top: 14.0,
          child: TextureImage(
            texture: ui['level_display.png']!,
            width: 62.0,
            height: 62.0,
          ),
        ),
        Positioned(
          left: 18.0,
          top: 14.0,
          child: TextureImage(
            texture: ui['level_display_${level + 1}.png']!,
            width: 62.0,
            height: 62.0,
          ),
        ),
        Positioned(
          left: 85.0,
          top: 14.0,
          child: TextureButton(
            texture: ui['btn_level_up.png']!,
            width: 30.0,
            height: 30.0,
            onPressed: controller.startLevelUp,
          ),
        ),
        Positioned(
          left: 85.0,
          top: 46.0,
          child: TextureButton(
            texture: ui['btn_level_down.png']!,
            width: 30.0,
            height: 30.0,
            onPressed: controller.startLevelDown,
          ),
        ),
        Positioned(
          left: 120.0,
          top: 14.0,
          child: TextureButton(
            onPressed: controller.play,
            texture: ui['btn_play.png']!,
            label: 'PLAY',
            textStyle: const TextStyle(
              fontFamily: 'Orbitron',
              fontSize: 28.0,
              letterSpacing: 3.0,
              color: Color(0xffffffff),
            ),
            width: 181.0,
            height: 62.0,
          ),
        ),
      ],
    );
  }
}

class _MainSceneBackgroundNode extends NodeWithSize {
  _MainSceneBackgroundNode(ClassicAssets assets)
    : super(const Size(320.0, 320.0)) {
    final images = assets.images;
    _background = RepeatedImage(images['assets/classic/starfield.png']!);
    addChild(_background);

    addChild(StarField(assets.sprites, 200, true));

    _nebula = RepeatedImage(
      images['assets/classic/nebula.png']!,
      BlendMode.plus,
    );
    addChild(_nebula);

    _bgTop = Sprite.fromImage(images['assets/classic/ui_bg_top.png']!)
      ..pivot = Offset.zero
      ..size = const Size(320.0, 108.0);
    addChild(_bgTop);

    _bgBottom = Sprite.fromImage(images['assets/classic/ui_bg_bottom.png']!)
      ..pivot = const Offset(0.0, 1.0)
      ..size = const Size(320.0, 97.0);
    addChild(_bgBottom);
  }

  late RepeatedImage _background;
  late RepeatedImage _nebula;
  late Sprite _bgTop;
  late Sprite _bgBottom;

  @override
  void paint(Canvas canvas) {
    canvas.drawRect(
      const Rect.fromLTWH(0.0, 0.0, 320.0, 320.0),
      Paint()..color = const Color(0xff000000),
    );
    super.paint(canvas);
  }

  @override
  void spriteBoxPerformedLayout() {
    _bgBottom.position = Offset(0.0, spriteBox!.visibleArea!.size.height);
  }

  @override
  void update(double dt) {
    _background.move(10.0 * dt);
    _nebula.move(100.0 * dt);
  }
}

class _LaserDisplay extends StatelessWidget {
  const _LaserDisplay(this.level, this.assets);

  final int level;
  final ClassicAssets assets;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        width: 26.0,
        height: 26.0,
        child: SpriteWidget(_LaserDisplayNode(level, assets.sprites)),
      ),
    );
  }
}

class _LaserDisplayNode extends NodeWithSize {
  _LaserDisplayNode(int level, SpriteSheet sheet)
    : super(const Size(16.0, 16.0)) {
    final placementNode = Node()
      ..position = const Offset(8.0, 8.0)
      ..scale = 0.7;
    addChild(placementNode);
    addLaserSprites(placementNode, level, 0.0, sheet);
  }
}
