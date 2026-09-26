// The original 2D Space Blast scene (SpriteWidget), drawn from the shared
// GameWorld: no game logic runs here. Every frame the node tree is synced to
// the simulation, and simulation events trigger the original explosions,
// flashes and HUD effects.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:spritewidget/spritewidget.dart';

import '../game/game_controller.dart';
import '../game/sim/events.dart';
import '../game/sim/game_objects.dart';
import '../game/sim/joystick.dart' as sim show Joystick;
import '../game/sim/motions.dart' show splinePoint;
import '../game/sim/player_state.dart' show CoinFlight;
import '../game/sim/world.dart';
import 'classic_parts.dart';

class ClassicGameNode extends NodeWithSize {
  ClassicGameNode(this.controller, this.assets)
    : world = controller.world,
      super(const Size(320.0, 320.0)) {
    final images = assets.images;
    _background = RepeatedImage(images['assets/classic/starfield.png']!);
    addChild(_background);

    _starField = StarField(assets.sprites, 200);
    addChild(_starField);

    _nebula = RepeatedImage(
      images['assets/classic/nebula.png']!,
      ui.BlendMode.plus,
    );
    addChild(_nebula);

    _gameScreen = Node();
    addChild(_gameScreen);

    _level = Node()..position = const Offset(160.0, 0.0);
    _gameScreen.addChild(_level);

    _hud = _ClassicHud(assets)..position = const Offset(0.0, 20.0);
    addChild(_hud);

    _joystick = _ClassicJoystick(world.joystick);
    _gameScreen.addChild(_joystick);

    controller.eventListeners.add(_onEvent);
    controller.frame.addListener(_sync);
    _lastScroll = world.scroll;
    _sync();
  }

  final GameController controller;
  final ClassicAssets assets;
  final GameWorld world;

  late RepeatedImage _background;
  late StarField _starField;
  late RepeatedImage _nebula;
  late Node _gameScreen;
  late Node _level;
  late _ClassicHud _hud;
  late _ClassicJoystick _joystick;

  final Map<GameObject, _Mirror> _mirrors = {};
  final List<GameEvent> _pending = [];
  double _lastScroll = 0.0;
  double _gameHeight = 480.0;

  void dispose() {
    controller.eventListeners.remove(_onEvent);
    controller.frame.removeListener(_sync);
  }

  void _onEvent(GameEvent event) => _pending.add(event);

  @override
  void spriteBoxPerformedLayout() {
    _gameHeight = spriteBox!.visibleArea!.height;
    _gameScreen.position = Offset(0.0, _gameHeight);
  }

  /// Runs right after the controller advanced the simulation.
  void _sync() {
    if (!identical(controller.world, world)) return;
    final a = controller.alpha;

    // Scrolling, with the original parallax factors.
    final scroll = world.prevScroll + (world.scroll - world.prevScroll) * a;
    final delta = scroll - _lastScroll;
    _lastScroll = scroll;
    _background.move(delta * 0.1);
    _nebula.move(delta);
    _starField.move(0.0, delta);
    _level.position = Offset(160.0, scroll);

    // Game objects.
    for (final obj in world.children) {
      final mirror = _mirrors.putIfAbsent(obj, () {
        final m = _Mirror.create(obj, assets, _level);
        _level.addChild(m.node);
        return m;
      });
      mirror.sync(a, world);
    }
    _mirrors.removeWhere((obj, mirror) {
      if (obj.attached) return false;
      mirror.remove();
      return true;
    });

    // Events.
    for (final event in _pending) {
      switch (event) {
        case ExplosionEvent e:
          final explosion = e.kind == ExplosionKind.big
              ? (ExplosionBig(assets.sprites)..scale = e.scale)
              : ExplosionMini(assets.sprites);
          explosion.position = Offset(e.x, e.y);
          _level.addChild(explosion);
        case FlashEvent _:
          addChild(Flash(Size(320.0, _gameHeight), 1.0));
        default:
          break;
      }
    }
    _pending.clear();

    final ps = world.playerState;
    if (ps.score != _hud.score) _hud.setScore(ps.score);
    if (ps.coins != _hud.coins) _hud.setCoins(ps.coins);
    _hud.syncCoinFlights(world, a);
    _joystick.sync(controller.time);
  }
}

/// A sim object's sprite(s) in the original style.
class _Mirror {
  _Mirror(this.object, this.node, this.assets);

  final GameObject object;
  final Node node;
  final ClassicAssets assets;

  Sprite? sprite;
  Sprite? shield;
  PowerBar? bar;
  int _lastDamageStep = -1;

  static _Mirror create(GameObject obj, ClassicAssets assets, Node level) {
    final sheet = assets.sprites;
    final node = Node();
    final m = _Mirror(obj, node, assets);
    Sprite add(String name, double scale) {
      final s = Sprite(texture: sheet[name]!)..scale = scale;
      node.addChild(s);
      return s;
    }

    void spin(Sprite s, double seconds, [double direction = 1]) {
      s.motions.run(
        MotionRepeatForever(
          motion: MotionTween<double>(
            setter: (a) => s.rotation = a,
            start: 0.0,
            end: 360.0 * direction,
            duration: seconds,
          ),
        ),
      );
    }

    void fadeIn(Sprite s) {
      s.motions.run(
        MotionTween<double>(
          setter: (a) => s.opacity = a,
          start: 0.0,
          end: 1.0,
          duration: 0.6,
        ),
      );
    }

    switch (obj) {
      case Ship _:
        m.sprite = add('ship.png', 0.3)..rotation = -90.0;
        m.shield = add('shield.png', 0.35)..blendMode = ui.BlendMode.plus;
        spin(m.shield!, 1.0);
      case Laser laser:
        addLaserSprites(node, laser.level, laser.direction, sheet);
      case LevelLabel label:
        node.addChild(
          Label(
            'LEVEL ${label.level}',
            textAlign: TextAlign.center,
            textStyle: const TextStyle(
              fontFamily: 'Orbitron',
              letterSpacing: 10.0,
              color: Color(0xffffffff),
              fontSize: 24.0,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      case AsteroidPowerUp crystal:
        add('powerup.png', 0.3);
        add('powerup_${crystal.powerUpType.index}.png', 0.3);
        m.sprite = add('crystal_${crystal.variant}.png', 0.3);
      case AsteroidBig a:
        m.sprite = add('asteroid_big_${a.variant}.png', 0.3);
        spin(m.sprite!, a.spinPeriod, a.spinDirection);
      case AsteroidSmall a:
        m.sprite = add('asteroid_small_${a.variant}.png', 0.3);
        spin(m.sprite!, a.spinPeriod, a.spinDirection);
      case EnemyScout e:
        m.sprite = add('enemy_scout_${e.variant}.png', 0.32);
      case EnemyDestroyer e:
        m.sprite = add('enemy_destroyer_${e.variant}.png', 0.32);
      case EnemyBoss e:
        m.sprite = add('enemy_boss_${e.variant}.png', 0.32);
        m.bar = PowerBar(const Size(60.0, 10.0))
          ..pivot = const Offset(0.5, 0.5);
        level.addChild(m.bar!);
      case EnemyLaser l:
        m.sprite = add('explosion_particle.png', 0.5)
          ..rotation = l.direction + 90
          ..colorOverlay = const Color(0xffffe38e);
      case Coin _:
        m.sprite = add('coin.png', 0.7);
        spin(m.sprite!, 1.0);
        fadeIn(m.sprite!);
      case PowerUp p:
        m.sprite = add('powerup.png', 0.3);
        spin(m.sprite!, 1.0);
        fadeIn(m.sprite!);
        add('powerup_${p.type.index}.png', 0.3);
      default:
        break;
    }
    if (obj is Collectable) node.zPosition = 20.0;
    return m;
  }

  void sync(double a, GameWorld world) {
    final o = object;
    node.position = Offset(
      o.prevX + (o.x - o.prevX) * a,
      o.prevY + (o.y - o.prevY) * a,
    );

    switch (o) {
      case Ship ship:
        node.visible = ship.visible;
        final ps = world.playerState;
        // The original blinks the shield every frame while it runs out.
        shield!.visible =
            ps.shieldActive &&
            (!ps.shieldDeactivating || world.stepCount.isEven);
      case Laser laser:
        node.rotation = laser.rotation;
      case EnemyScout _:
      case EnemyDestroyer _:
        node.rotation = _lerpAngle(o.prevRotation, o.rotation, a);
        sprite!.colorOverlay = colorForDamage(o.damage, o.maxDamage);
      case EnemyBoss boss:
        node.rotation = _lerpAngle(o.prevRotation, o.rotation, a);
        if (boss.lastDamageStep != _lastDamageStep) {
          _lastDamageStep = boss.lastDamageStep;
          final s = sprite!;
          s.motions.stopAll();
          s.motions.run(
            MotionTween<Color>(
              setter: (c) => s.colorOverlay = c,
              start: const Color.fromARGB(180, 255, 3, 86),
              end: const Color(0x00000000),
              duration: 0.3,
            ),
          );
        }
        bar!
          ..position = Offset(
            boss.prevBarX + (boss.barX - boss.prevBarX) * a,
            boss.prevBarY + (boss.barY - boss.prevBarY) * a,
          )
          ..power = boss.power;
      case AsteroidPowerUp _:
        sprite!.colorOverlay = colorForDamage(
          o.damage,
          o.maxDamage,
          const Color.fromARGB(255, 200, 200, 255),
        );
      case Asteroid _:
        sprite!.colorOverlay = colorForDamage(o.damage, o.maxDamage);
      default:
        break;
    }
  }

  void remove() {
    node.removeFromParent();
    bar?.removeFromParent();
  }

  static double _lerpAngle(double from, double to, double t) {
    double d = to - from;
    while (d > 180) {
      d -= 360;
    }
    while (d < -180) {
      d += 360;
    }
    return from + d * t;
  }
}

/// The original score and coin boards with sprite digits.
class _ClassicHud extends Node {
  _ClassicHud(this.assets) {
    final ui = assets.ui;
    _scoreBoard = Sprite(texture: ui['scoreboard.png']!)
      ..pivot = const Offset(1.0, 0.0)
      ..scale = 0.35
      ..position = const Offset(240.0, 10.0);
    addChild(_scoreBoard);
    _score = _ScoreDisplay(ui)..position = const Offset(349.0, 49.0);
    _scoreBoard.addChild(_score);

    _coinBoard = Sprite(texture: ui['coinboard.png']!)
      ..pivot = const Offset(1.0, 0.0)
      ..scale = 0.35
      ..position = const Offset(105.0, 10.0);
    addChild(_coinBoard);
    _coins = _ScoreDisplay(ui)..position = const Offset(252.0, 49.0);
    _coinBoard.addChild(_coins);
  }

  final ClassicAssets assets;
  late Sprite _scoreBoard;
  late _ScoreDisplay _score;
  late Sprite _coinBoard;
  late _ScoreDisplay _coins;
  final Map<CoinFlight, Sprite> _flights = {};

  int score = 0;
  int coins = 0;

  void setScore(int score) {
    this.score = score;
    _score.score = score;
    _flash(_scoreBoard);
  }

  void setCoins(int coins) {
    this.coins = coins;
    _coins.score = coins;
    _flash(_coinBoard);
  }

  void _flash(Sprite sprite) {
    sprite.motions.stopAll();
    sprite.motions.run(
      MotionTween<Color>(
        setter: (a) => sprite.colorOverlay = a,
        start: const Color(0x66ccfff0),
        end: const Color(0x00ccfff0),
        duration: 0.3,
      ),
    );
  }

  /// Coins flying to the coin board, along the original spline.
  void syncCoinFlights(GameWorld world, double a) {
    final active = world.playerState.coinFlights.toSet();
    _flights.removeWhere((flight, sprite) {
      if (active.contains(flight)) return false;
      sprite.removeFromParent();
      return true;
    });
    for (final flight in active) {
      final sprite = _flights.putIfAbsent(flight, () {
        final s = Sprite(texture: assets.sprites['coin.png']!);
        addChild(s);
        return s;
      });
      final elapsed =
          (math.max(0, flight.steps - 1) + a) / GameWorld.stepsPerSecond;
      final t = (elapsed / CoinFlight.duration).clamp(0.0, 1.0);
      // In this node's space (it sits 20 units down); the original flew to
      // (30, 30) here, with the middle point pushed 50 units right.
      final start = flight.path.first - const Offset(0.0, 20.0);
      const end = Offset(30.0, 30.0);
      final middle = Offset(
        (start.dx + end.dx) / 2.0 + 50.0,
        (start.dy + end.dy) / 2.0,
      );
      sprite
        ..position = splinePoint([start, middle, end], 0.25, t)
        ..rotation = t * 360.0
        ..scale = 0.7 + 0.5 * t;
    }
  }
}

class _ScoreDisplay extends Node {
  _ScoreDisplay(this._sheetUI);

  final SpriteSheet _sheetUI;
  int _score = 0;
  bool _dirty = true;

  set score(int score) {
    _score = score;
    _dirty = true;
  }

  @override
  void update(double dt) {
    if (!_dirty) return;
    removeAllChildren();
    final scoreStr = _score.toString();
    double xPos = -37.0;
    for (int i = scoreStr.length - 1; i >= 0; i--) {
      final numSprite = Sprite(
        texture: _sheetUI['number_${scoreStr.substring(i, i + 1)}.png']!,
      )..position = Offset(xPos, 0.0);
      addChild(numSprite);
      xPos -= 37.0;
    }
    _dirty = false;
  }
}

/// The original VirtualJoystick's look, driven by the shared joystick.
class _ClassicJoystick extends NodeWithSize {
  _ClassicJoystick(this.joystick) : super(const Size(160.0, 160.0)) {
    position = const Offset(160.0, -20.0);
    pivot = const Offset(0.5, 1.0);
  }

  final sim.Joystick joystick;
  final Offset _center = const Offset(80.0, 80.0);
  Offset _handle = Offset.zero;
  Offset _velocity = Offset.zero;
  double _lastTime = 0;

  final Paint _paintHandle = Paint()..color = const Color(0xffffffff);
  final Paint _paintControl = Paint()
    ..color = const Color(0xffffffff)
    ..strokeWidth = 1.0
    ..style = PaintingStyle.stroke;

  void sync(double time) {
    final dt = (time - _lastTime).clamp(0.0, 0.05);
    _lastTime = time;
    final target = joystick.handleTarget;
    if (joystick.isDown) {
      _handle = target;
      _velocity = Offset.zero;
    } else {
      // The original springs back with an elasticOut tween.
      final force = (target - _handle) * 260.0 - _velocity * 9.0;
      _velocity += force * dt;
      _handle += _velocity * dt;
    }
  }

  @override
  void paint(Canvas canvas) {
    applyTransformForPivot(canvas);
    canvas.drawCircle(_center + _handle, 25.0, _paintHandle);
    canvas.drawCircle(_center, 40.0, _paintControl);
  }
}
