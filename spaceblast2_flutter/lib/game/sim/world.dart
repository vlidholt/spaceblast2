import 'dart:ui';

import 'events.dart';
import 'game_math.dart';
import 'game_objects.dart';
import 'joystick.dart';
import 'persistent_state.dart';
import 'player_state.dart';

const double chunkSpacing = 640.0;
const int chunksPerLevel = 9;
const int _maxLevel = 9;

/// The gameplay simulation: a step-for-step port of the original GameDemoNode
/// and GameObjectFactory, advanced at a fixed 60 steps per second.
///
/// The world keeps the original's coordinate system. The level is 320 units
/// wide with x = 0 in the middle, y grows downward, and [scroll] is how far
/// the level has moved down. [gameHeight] is the visible height in the same
/// units (it depends on the screen's aspect ratio).
class GameWorld {
  GameWorld(this.gameState, {this.gameHeight = 480.0}) {
    playerState = PlayerState(this, gameState);
    ship = Ship(this);
    attach(ship);
    addObjects();
  }

  static const int stepsPerSecond = 60;
  static const double dt = 1.0 / stepsPerSecond;

  final PersistentGameState gameState;
  final Joystick joystick = Joystick();
  late final PlayerState playerState;
  late final Ship ship;

  double gameHeight;

  /// Level offset; objects at y = -scroll sit at the bottom of the screen.
  double scroll = 0.0;
  double prevScroll = 0.0;

  int stepCount = 0;
  double get time => stepCount * dt;

  int _chunk = 0;
  int topLevelReached = 0;

  int _framesToFire = 0;
  static const int _framesBetweenShots = 20;

  bool gameOver = false;
  int _gameOverSteps = -1;
  bool _gameOverReported = false;

  final List<GameEvent> events = [];

  // Level children, kept sorted by (zPosition, addedOrder) like SpriteWidget.
  final List<GameObject> _children = [];
  bool _needsSort = false;
  int _lastAddedOrder = 0;

  List<GameObject> get children {
    if (_needsSort) {
      _children.sort((a, b) {
        if (a.zPosition == b.zPosition) return a.addedOrder - b.addedOrder;
        return a.zPosition > b.zPosition ? 1 : -1;
      });
      _needsSort = false;
    }
    return _children;
  }

  void emit(GameEvent event) => events.add(event);

  Offset levelToScreen(double x, double y) =>
      Offset(160.0 + x, gameHeight + scroll + y);

  void attach(GameObject obj) {
    obj.attached = true;
    obj.addedOrder = ++_lastAddedOrder;
    obj.spawnStep = stepCount;
    _children.add(obj);
    _needsSort = true;
  }

  void removeObject(GameObject obj) {
    if (!obj.attached) return;
    obj.attached = false;
    _children.remove(obj);
  }

  void addGameObject(GameObject obj, double x, double y) {
    obj.x = x;
    obj.y = y;
    obj.setupActions();
    obj.savePrevious();
    attach(obj);
  }

  /// Advances the game by one fixed step, in the same phase order as
  /// SpriteBox: constraint pre-update, motions, node updates (root first, then
  /// the HUD, then level children back to front) and finally constraints.
  void step() {
    stepCount++;
    prevScroll = scroll;
    for (final obj in children) {
      obj.savePrevious();
    }

    // Constraints (pre-update)
    for (final obj in children) {
      obj.constraintPreUpdate();
    }

    // Motions
    for (final obj in List<GameObject>.of(children)) {
      if (obj.attached) obj.motion?.step(dt);
    }
    playerState.stepCoinFlights();

    // Updates
    _update();
    playerState.update();
    final snapshot = List<GameObject>.of(children);
    for (int i = snapshot.length - 1; i >= 0; i--) {
      if (snapshot[i].attached) snapshot[i].update();
    }

    // Constraints
    for (final obj in children) {
      obj.constrain();
    }

    if (_gameOverSteps >= 0) {
      _gameOverSteps--;
      if (_gameOverSteps < 0 && !_gameOverReported) {
        _gameOverReported = true;
        emit(
          GameOverEvent(playerState.score, playerState.coins, topLevelReached),
        );
      }
    }
  }

  void _update() {
    // Scroll the level
    scroll += playerState.scrollSpeed;

    // Add objects
    addObjects();

    // Move the ship
    if (!gameOver) {
      ship.applyThrust(joystick.value, scroll);
    }

    // Add shots
    if (_framesToFire == 0 && joystick.isDown && !gameOver) {
      fire();
      _framesToFire = playerState.speedLaserActive
          ? _framesBetweenShots ~/ 2
          : _framesBetweenShots;
    }
    if (_framesToFire > 0) _framesToFire--;

    // Move game objects
    for (final obj in children) {
      obj.move();
    }

    // Remove offscreen game objects
    final list = children;
    for (int i = list.length - 1; i >= 0; i--) {
      if (i < list.length) list[i].removeIfOffscreen(scroll);
    }

    if (gameOver) return;

    // Check for collisions between lasers and objects that can take damage.
    // Like the original, a laser keeps checking the remaining targets after
    // it hits one, and objects destroyed earlier in the step can still be hit.
    final lasers = <Laser>[
      for (final obj in children)
        if (obj is Laser) obj,
    ];
    final damageables = <GameObject>[
      for (final obj in children)
        if (obj.canBeDamaged) obj,
    ];

    for (final laser in lasers) {
      for (final damageable in damageables) {
        if (laser.collidingWith(damageable)) {
          damageable.addDamage(laser.impact);
          laser.destroy();
        }
      }
    }

    // Check for collisions between the ship and objects that can damage it.
    final nodes = List<GameObject>.of(children);
    for (final node in nodes) {
      if (node.canDamageShip) {
        if (node.collidingWith(ship)) {
          if (playerState.shieldActive) {
            // Hit, but saved by the shield!
            if (node is! EnemyBoss) node.destroy();
          } else {
            // The ship was hit :(
            killShip();
          }
        }
      } else if (node.canBeCollected) {
        if (node.collidingWith(ship)) {
          node.collect();
        }
      }
    }
  }

  void addObjects() {
    while (scroll + chunkSpacing >= _chunk * chunkSpacing) {
      addLevelChunk(_chunk, -_chunk * chunkSpacing - chunkSpacing);
      _chunk += 1;
    }
  }

  void addLevelChunk(int chunk, double yPos) {
    final level = chunk ~/ chunksPerLevel + gameState.currentStartingLevel;
    final part = chunk % chunksPerLevel;

    if (part == 0) {
      final lbl = LevelLabel(this, level + 1);
      lbl.x = 0.0;
      lbl.y = yPos + chunkSpacing / 2.0 - 150.0;
      lbl.savePrevious();
      topLevelReached = level;
      attach(lbl);
    } else if (part == 1) {
      addAsteroids(level, yPos);
    } else if (part == 2) {
      addEnemyScoutSwarm(level, yPos);
    } else if (part == 3) {
      addAsteroids(level, yPos);
    } else if (part == 4) {
      addEnemyDestroyerSwarm(level, yPos);
    } else if (part == 5) {
      addAsteroids(level, yPos);
    } else if (part == 6) {
      addEnemyScoutSwarm(level, yPos);
    } else if (part == 7) {
      addAsteroids(level, yPos);
    } else if (part == 8) {
      addBossFight(level, yPos);
    }
  }

  void fire() {
    final laserLevel = playerState.laserLevel;

    void shoot(double dx, double r) {
      final shot = Laser(this, laserLevel, r);
      shot.x = ship.x + dx;
      shot.y = ship.y - 10.0;
      shot.savePrevious();
      attach(shot);
    }

    shoot(17.0, -90.0);
    shoot(-17.0, -90.0);

    if (playerState.sideLaserActive) {
      shoot(17.0, -45.0);
      shoot(-17.0, -135.0);
    }
  }

  void killShip() {
    if (gameOver) return;

    ship.visible = false;
    emit(const SoundEvent('explosion_player'));
    emit(
      ExplosionEvent(
        ExplosionKind.big,
        ship.x,
        ship.y,
        1.5,
        source: ObjectKind.ship,
        variant: 0,
      ),
    );
    emit(ShipDestroyedEvent(ship.x, ship.y));
    emit(const FlashEvent());

    gameOver = true;

    // Report the score back in 2 seconds.
    _gameOverSteps = 2 * stepsPerSecond;
  }

  // --- GameObjectFactory ---------------------------------------------------

  void addAsteroids(int level, double yPos) {
    final numAsteroids = 10 + level * 4;
    final distribution = (level * 0.2).clamp(0.0, 0.8);

    for (int i = 0; i < numAsteroids; i++) {
      GameObject obj;
      if (i == 0) {
        obj = AsteroidPowerUp(this);
      } else if (randomDouble() < distribution) {
        obj = AsteroidBig(this);
      } else {
        obj = AsteroidSmall(this);
      }

      addGameObject(
        obj,
        randomSignedDouble() * 160.0,
        yPos + chunkSpacing * randomDouble(),
      );
    }
  }

  static List<int> _swarmTypes(int swarmLevel) => switch (swarmLevel) {
    0 => [0, 0, 0],
    1 => [0, 1, 0],
    2 => [1, 0, 1],
    3 => [1, 1, 1],
    4 => [0, 1, 2],
    5 => [1, 2, 1],
    6 => [2, 1, 2],
    7 => [2, 1, 2],
    _ => [2, 2, 2],
  };

  void addEnemyScoutSwarm(int level, double yPos) {
    final numEnemies = (3 + level * 3).clamp(0, 12);
    final types = _swarmTypes(level % _maxLevel);

    for (int i = 0; i < numEnemies; i++) {
      final type = types[i % 3];
      final spacing = (chunkSpacing / (numEnemies + 1.0)) < 80.0
          ? 80.0
          : chunkSpacing / (numEnemies + 1.0);
      final y =
          yPos +
          chunkSpacing / 2.0 -
          (numEnemies - 1) * spacing / 2.0 +
          i * spacing;
      addGameObject(EnemyScout(this, type), 0.0, y);
    }
  }

  void addEnemyDestroyerSwarm(int level, double yPos) {
    final numEnemies = (2 + level).clamp(2, 10);
    final types = _swarmTypes(level % _maxLevel);

    for (int i = 0; i < numEnemies; i++) {
      final type = types[i % 3];
      addGameObject(
        EnemyDestroyer(this, type),
        randomSignedDouble() * 120.0,
        yPos + chunkSpacing * randomDouble(),
      );
    }
  }

  void addBossFight(int level, double yPos) {
    // Add boss
    final boss = EnemyBoss(this, level);
    addGameObject(boss, 0.0, yPos + chunkSpacing / 2.0);

    playerState.boss = boss;

    // Same as the original's `(level - 1 ~/ 3).clamp(0, 2)`.
    final destroyerLevel = (level - 1 ~/ 3).clamp(0, 2);

    // Add boss's helpers
    if (level >= 1) {
      addGameObject(
        EnemyDestroyer(this, destroyerLevel),
        -80.0,
        yPos + chunkSpacing / 2.0 + 70.0,
      );
      addGameObject(
        EnemyDestroyer(this, destroyerLevel),
        80.0,
        yPos + chunkSpacing / 2.0 + 70.0,
      );

      if (level >= 2) {
        addGameObject(
          EnemyDestroyer(this, destroyerLevel),
          -80.0,
          yPos + chunkSpacing / 2.0 - 70.0,
        );
        addGameObject(
          EnemyDestroyer(this, destroyerLevel),
          80.0,
          yPos + chunkSpacing / 2.0 - 70.0,
        );
      }
    }
  }
}
