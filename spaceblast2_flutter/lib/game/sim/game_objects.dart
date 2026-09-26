import 'dart:math' as math;
import 'dart:ui';

import 'events.dart';
import 'game_math.dart';
import 'motions.dart';
import 'power_up_type.dart';
import 'world.dart';

enum ObjectKind {
  ship,
  laser,
  levelLabel,
  asteroidBig,
  asteroidSmall,
  asteroidPowerUp,
  enemyScout,
  enemyDestroyer,
  enemyBoss,
  enemyLaser,
  coin,
  powerUp,
}

/// Base class for everything that lives in the scrolling level. Positions are
/// in the original game's level coordinates: x in -160..160 (0 is the screen
/// center), y grows downward and the level scrolls by increasing its offset.
abstract class GameObject {
  GameObject(this.world);

  static int _nextId = 0;

  final GameWorld world;
  final int id = _nextId++;

  ObjectKind get kind;

  double x = 0.0;
  double y = 0.0;

  /// Degrees, clockwise on screen (0 points right, -90 points up).
  double rotation = 0.0;

  // State at the start of the last simulation step, used by the renderer to
  // interpolate between fixed steps.
  double prevX = 0.0;
  double prevY = 0.0;
  double prevRotation = 0.0;

  double radius = 0.0;
  double removeLimit = 1280.0;
  bool canDamageShip = true;
  bool canBeDamaged = true;
  bool canBeCollected = false;
  double maxDamage = 3.0;
  double _damage = 0.0;

  /// Sort key within the level; collectables draw (and update) after the rest.
  double zPosition = 0.0;
  int addedOrder = 0;

  /// True while the object is part of the level.
  bool attached = false;

  /// The simulation step the object was added on.
  int spawnStep = 0;

  /// The step the object last took damage, or -1.
  int lastDamageStep = -1;

  /// The flight path (enemies) or null.
  Motion? motion;

  /// Opaque slot for the renderer.
  Object? visual;

  /// Model variant (0..2) for objects with several looks.
  int variant = 0;

  double get damage => _damage;
  set damage(double d) {
    _damage = d;
    lastDamageStep = world.stepCount;
  }

  void savePrevious() {
    prevX = x;
    prevY = y;
    prevRotation = rotation;
  }

  bool collidingWith(GameObject obj) =>
      GameMath.distanceBetweenPoints(x, y, obj.x, obj.y) < radius + obj.radius;

  void move() {}

  void removeIfOffscreen(double scroll) {
    if (-y > scroll + removeLimit || -y < scroll - 50.0) {
      removeFromParent();
    }
  }

  void removeFromParent() => world.removeObject(this);

  void destroy() {
    if (attached) {
      createExplosion();

      final powerUp = createPowerUp();
      if (powerUp != null) {
        world.addGameObject(powerUp, x, y);
      }

      removeFromParent();
    }
  }

  void collect() => removeFromParent();

  void addDamage(double d) {
    if (!canBeDamaged) return;

    damage += d;
    if (damage >= maxDamage) {
      destroy();
      world.playerState.score += (maxDamage * 10).ceil();
    } else {
      world.emit(const SoundEvent('hit'));
    }
  }

  void createExplosion() {}

  GameObject? createPowerUp() => null;

  void setupActions() {}

  /// Per-step logic (the node's update() in the original).
  void update() {}

  // Constraints, run before the motions and after the updates.
  void constraintPreUpdate() {}
  void constrain() {}
}

class LevelLabel extends GameObject {
  LevelLabel(super.world, this.level) {
    canDamageShip = false;
    canBeDamaged = false;
  }

  final int level;

  @override
  ObjectKind get kind => ObjectKind.levelLabel;
}

class Ship extends GameObject {
  Ship(super.world) {
    radius = 20.0;
    canBeDamaged = false;
    canDamageShip = false;
    x = 0.0;
    y = 50.0;
    savePrevious();
  }

  bool visible = true;

  @override
  ObjectKind get kind => ObjectKind.ship;

  void applyThrust(Offset joystickValue, double scroll) {
    final targetX = joystickValue.dx * 160.0;
    final targetY = joystickValue.dy * 220.0 - 250.0 - scroll;
    const filterFactor = 0.2;
    x = GameMath.filter(x, targetX, filterFactor);
    y = GameMath.filter(y, targetY, filterFactor);
  }
}

class Laser extends GameObject {
  Laser(super.world, this.level, double r) {
    radius = 10.0;
    removeLimit = world.gameHeight + radius;
    canDamageShip = false;
    canBeDamaged = false;
    impact = 1.0 + level * 0.5;

    _dx = math.cos(radians(r)) * 8.0;
    _dy = math.sin(radians(r)) * 8.0 - world.playerState.scrollSpeed;

    rotation = r + 90.0;
    direction = r;
  }

  final int level;
  double impact = 0.0;

  /// Travel direction in degrees.
  late final double direction;
  late final double _dx;
  late final double _dy;

  @override
  ObjectKind get kind => ObjectKind.laser;

  @override
  void move() {
    x += _dx;
    y += _dy;
  }

  @override
  void createExplosion() {
    world.emit(
      ExplosionEvent(ExplosionKind.mini, x, y, 1.0, source: kind, variant: 0),
    );
  }
}

abstract class Obstacle extends GameObject {
  Obstacle(super.world);

  double explosionScale = 1.0;

  @override
  void createExplosion() {
    world.emit(SoundEvent('explosion_${randomInt(3)}'));
    world.emit(
      ExplosionEvent(
        ExplosionKind.big,
        x,
        y,
        explosionScale,
        source: kind,
        variant: variant,
      ),
    );
  }
}

abstract class Asteroid extends Obstacle {
  Asteroid(super.world);

  /// Visual spin: +1/-1 and seconds per revolution.
  double spinDirection = 1.0;
  double spinPeriod = 5.0;

  @override
  void setupActions() {
    spinDirection = randomBool() ? -1.0 : 1.0;
    spinPeriod = 5.0 + 5.0 * randomDouble();
  }

  @override
  GameObject? createPowerUp() => Coin(world);
}

class AsteroidBig extends Asteroid {
  AsteroidBig(super.world) {
    variant = randomInt(3);
    radius = 25.0;
    maxDamage = 5.0;
  }

  @override
  ObjectKind get kind => ObjectKind.asteroidBig;
}

class AsteroidSmall extends Asteroid {
  AsteroidSmall(super.world) {
    variant = randomInt(3);
    radius = 12.0;
    maxDamage = 3.0;
  }

  @override
  ObjectKind get kind => ObjectKind.asteroidSmall;
}

class AsteroidPowerUp extends AsteroidBig {
  AsteroidPowerUp(super.world) {
    powerUpType = nextPowerUpType();
    variant = randomInt(2);
  }

  late final PowerUpType powerUpType;

  @override
  ObjectKind get kind => ObjectKind.asteroidPowerUp;

  @override
  void setupActions() {}

  @override
  GameObject? createPowerUp() => PowerUp(world, powerUpType);
}

class EnemyScout extends Obstacle {
  EnemyScout(super.world, int level) {
    variant = level;
    radius = 12.0 + level * 2.0;

    if (level == 0) {
      maxDamage = 1.0;
    } else if (level == 1) {
      maxDamage = 4.0;
    } else if (level == 2) {
      maxDamage = 8.0;
    }
  }

  static const double _swirlSpacing = 80.0;

  Offset? _lastPosition;

  @override
  ObjectKind get kind => ObjectKind.enemyScout;

  void _addRandomSquare(List<Offset> offsets, double x, double y) {
    final xMove = randomBool() ? _swirlSpacing : -_swirlSpacing;
    final yMove = randomBool() ? _swirlSpacing : -_swirlSpacing;

    if (randomBool()) {
      offsets.addAll(<Offset>[
        Offset(x, y),
        Offset(xMove + x, y),
        Offset(xMove + x, yMove + y),
        Offset(x, yMove + y),
        Offset(x, y),
      ]);
    } else {
      offsets.addAll(<Offset>[
        Offset(x, y),
        Offset(x, y + yMove),
        Offset(xMove + x, yMove + y),
        Offset(xMove + x, y),
        Offset(x, y),
      ]);
    }
  }

  @override
  void setupActions() {
    final offsets = <Offset>[];
    _addRandomSquare(offsets, -_swirlSpacing, 0.0);
    _addRandomSquare(offsets, _swirlSpacing, 0.0);
    offsets.add(const Offset(-_swirlSpacing, 0.0));

    final points = [for (final o in offsets) Offset(x, y) + o];

    final spline = MotionSpline(
      (nx, ny) {
        x = nx;
        y = ny;
      },
      points,
      6.0,
    );
    spline.tension = 0.7;
    motion = MotionRepeatForever(spline);
  }

  @override
  GameObject? createPowerUp() => Coin(world);

  // ConstraintRotationToMovement(dampening: 0.5)
  @override
  void constraintPreUpdate() {
    _lastPosition = Offset(x, y);
  }

  @override
  void constrain() {
    final last = _lastPosition;
    if (last == null) return;
    if (last.dx == x && last.dy == y) return;
    final target = degrees(GameMath.atan2(y - last.dy, x - last.dx));
    rotation = dampenRotation(rotation, target, 0.5);
  }
}

/// Shared by enemies that keep turning toward the player's ship.
mixin RotatesTowardShip on GameObject {
  // ConstraintRotationToNode(targetNode: ship, dampening: 0.05)
  @override
  void constrain() {
    final ship = world.ship;
    final target = degrees(GameMath.atan2(ship.y - y, ship.x - x));
    rotation = dampenRotation(rotation, target, 0.05);
  }
}

class EnemyDestroyer extends Obstacle with RotatesTowardShip {
  EnemyDestroyer(super.world, int level) {
    variant = level;
    radius = 24.0 + level * 2;

    if (level == 0) {
      maxDamage = 4.0;
    } else if (level == 1) {
      maxDamage = 8.0;
    } else if (level == 2) {
      maxDamage = 16.0;
    }
  }

  int _countDown = randomInt(120) + 240;

  @override
  ObjectKind get kind => ObjectKind.enemyDestroyer;

  @override
  void setupActions() {
    final circle = ActionCircularMove(
      (nx, ny) {
        x = nx;
        y = ny;
      },
      Offset(x, y),
      40.0,
      360.0 * randomDouble(),
      randomBool(),
      3.0,
    );
    motion = MotionRepeatForever(circle);
  }

  @override
  GameObject? createPowerUp() => Coin(world);

  @override
  void update() {
    _countDown -= 1;
    if (_countDown <= 0) {
      world.emit(const SoundEvent('laser'));

      final laser = EnemyLaser(world, rotation, 5.0);
      laser.x = x;
      laser.y = y;
      laser.savePrevious();
      world.attach(laser);
      world.emit(MuzzleFlashEvent(x, y, rotation, 0.8));

      _countDown = 60 + randomInt(120);
    }
  }
}

class EnemyLaser extends Obstacle {
  EnemyLaser(super.world, this.direction, double speed) {
    canDamageShip = true;
    canBeDamaged = false;

    final rad = radians(direction);
    _dx = math.cos(rad) * speed;
    _dy = math.sin(rad) * speed;
  }

  /// Travel direction in degrees.
  final double direction;
  late final double _dx;
  late final double _dy;

  @override
  ObjectKind get kind => ObjectKind.enemyLaser;

  @override
  void move() {
    x += _dx;
    y += _dy;
  }
}

class EnemyBoss extends Obstacle with RotatesTowardShip {
  EnemyBoss(super.world, this.level) {
    radius = 48.0;
    variant = level % 3;
    maxDamage = 40.0 + 20.0 * level;
  }

  final int level;

  int _countDown = randomInt(120) + 240;

  /// The health bar follows the boss, 70 units above it, with some lag.
  double barX = 0.0;
  double barY = 0.0;
  double prevBarX = 0.0;
  double prevBarY = 0.0;
  double power = 1.0;

  @override
  ObjectKind get kind => ObjectKind.enemyBoss;

  @override
  void savePrevious() {
    super.savePrevious();
    prevBarX = barX;
    prevBarY = barY;
  }

  @override
  void update() {
    _countDown -= 1;
    if (_countDown <= 0) {
      world.emit(const SoundEvent('laser'));

      fire(10.0);
      fire(0.0);
      fire(-10.0);

      _countDown = 60 + randomInt(120);
    }
  }

  void fire(double r) {
    r += rotation;
    final laser = EnemyLaser(world, r, 5.0);

    final rad = radians(r);
    laser.x = x + math.cos(rad) * 30.0;
    laser.y = y + math.sin(rad) * 30.0;
    laser.savePrevious();
    world.attach(laser);
    world.emit(MuzzleFlashEvent(laser.x, laser.y, r, 1.2));
  }

  @override
  void setupActions() {
    final oscillate = ActionOscillate(
      (nx, ny) {
        x = nx;
        y = ny;
      },
      Offset(x, y),
      120.0,
      3.0,
    );
    motion = MotionRepeatForever(oscillate);
  }

  @override
  void constrain() {
    super.constrain();
    // ConstraintPositionToNode(offset: (0, -70), dampening: 0.5)
    barX = GameMath.filter(barX, x, 0.5);
    barY = GameMath.filter(barY, y - 70.0, 0.5);
  }

  @override
  void destroy() {
    world.playerState.boss = null;

    world.emit(const FlashEvent());
    super.destroy();

    // Add coins
    for (int i = 0; i < 20; i++) {
      final coin = Coin(world);
      world.addGameObject(
        coin,
        randomSignedDouble() * 160,
        y + randomSignedDouble() * 160.0,
      );
    }
  }

  @override
  void createExplosion() {
    world.emit(const SoundEvent('explosion_boss'));
    world.emit(
      ExplosionEvent(
        ExplosionKind.big,
        x,
        y,
        1.5,
        source: kind,
        variant: variant,
      ),
    );
  }

  @override
  set damage(double d) {
    super.damage = d;
    power = (1.0 - (damage / maxDamage)).clamp(0.0, 1.0);
  }
}

abstract class Collectable extends GameObject {
  Collectable(super.world) {
    canDamageShip = false;
    canBeDamaged = false;
    canBeCollected = true;
    zPosition = 20.0;
  }
}

class Coin extends Collectable {
  Coin(super.world) {
    radius = 7.5;
  }

  @override
  ObjectKind get kind => ObjectKind.coin;

  @override
  void collect() {
    world.emit(const SoundEvent('pickup_0'));
    world.emit(CoinCollectedEvent(x, y));
    world.playerState.addCoin(this);
    super.collect();
  }
}

class PowerUp extends Collectable {
  PowerUp(super.world, this.type) {
    radius = 10.0;
  }

  final PowerUpType type;

  @override
  ObjectKind get kind => ObjectKind.powerUp;

  @override
  void collect() {
    world.emit(const SoundEvent('buy_upgrade'));
    world.emit(PowerUpCollectedEvent(type, x, y));
    world.playerState.activatePowerUp(type);
    super.collect();
  }
}
