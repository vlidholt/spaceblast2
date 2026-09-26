import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spaceblast2_flutter/game/sim/events.dart';
import 'package:spaceblast2_flutter/game/sim/game_objects.dart';
import 'package:spaceblast2_flutter/game/sim/persistent_state.dart';
import 'package:spaceblast2_flutter/game/sim/power_up_type.dart';
import 'package:spaceblast2_flutter/game/sim/world.dart';

GameWorld _world({int startLevel = 0}) {
  final state = PersistentGameState()
    ..maxStartingLevel = 9
    ..currentStartingLevel = startLevel;
  return GameWorld(state, gameHeight: 480);
}

/// Removes everything but the ship so a test can set up its own scene.
void _clear(GameWorld w) {
  for (final o in List.of(w.children)) {
    if (o is! Ship) w.removeObject(o);
  }
}

/// Lets the ship finish flying in from below the screen.
void _settle(GameWorld w) {
  for (int i = 0; i < 60; i++) {
    w.step();
  }
  _clear(w);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the first chunks hold the level label and the first asteroid field', () {
    final w = _world();
    final labels = w.children.whereType<LevelLabel>().toList();
    expect(labels, hasLength(1));
    expect(labels.single.level, 1);
    // Level 0 asteroid fields have 10 asteroids, the first one with a crystal.
    expect(w.children.whereType<Asteroid>(), hasLength(10));
    expect(w.children.whereType<AsteroidPowerUp>(), hasLength(1));
  });

  test('holding fire shoots two lasers every 20 steps, 10 with rapid fire', () {
    final w = _world();
    _settle(w);
    final seen = <int>{};
    int lasers() {
      for (final l in w.children.whereType<Laser>()) {
        seen.add(l.id);
      }
      return seen.length;
    }

    w.joystick.isDown = true;
    w.step();
    expect(lasers(), 2);
    for (int i = 0; i < 19; i++) {
      w.step();
    }
    expect(lasers(), 2);
    w.step();
    expect(lasers(), 4);

    // The pending 20 step cooldown runs out first, then shots come every 10.
    w.playerState.activatePowerUp(PowerUpType.speedLaser);
    for (int i = 0; i < 40; i++) {
      w.step();
      lasers();
    }
    expect(lasers(), 10);
  });

  test('side lasers add two diagonal shots', () {
    final w = _world();
    _clear(w);
    w.playerState.activatePowerUp(PowerUpType.sideLaser);
    w.joystick.isDown = true;
    w.step();
    final dirs = w.children.whereType<Laser>().map((l) => l.direction).toList()
      ..sort();
    expect(dirs, [-135.0, -90.0, -90.0, -45.0]);
  });

  test('ship eases toward the joystick target like the original', () {
    final w = _world();
    _clear(w);
    w.joystick.value = const Offset(1, -1);
    for (int i = 0; i < 200; i++) {
      w.step();
    }
    expect(w.ship.x, closeTo(160, 0.01));
    // The target moves with the scroll, so the filter trails it by 8 units.
    expect(w.ship.y, closeTo(-220 - 250 - w.scroll + 8, 0.5));
  });

  test('destroying a small asteroid scores 30 and drops a coin', () {
    final w = _world();
    _settle(w);
    final a = AsteroidSmall(w);
    w.addGameObject(a, 0, w.ship.y - 60);
    // Three laser hits (impact 1) destroy it.
    for (int i = 0; i < 3; i++) {
      final laser = Laser(w, 0, -90);
      laser.x = a.x;
      laser.y = a.y + 5;
      w.attach(laser);
      w.step();
    }
    expect(a.attached, isFalse);
    expect(w.playerState.score, 30);
    expect(w.children.whereType<Coin>(), hasLength(1));
  });

  test('coins count once their flight to the HUD finishes', () {
    final w = _world();
    _settle(w);
    w.step();
    final coin = Coin(w);
    w.addGameObject(coin, w.ship.x, w.ship.y);
    w.step();
    expect(coin.attached, isFalse);
    expect(w.playerState.coins, 0);
    expect(w.playerState.coinFlights, hasLength(1));
    for (int i = 0; i < 31; i++) {
      w.step();
    }
    expect(w.playerState.coins, 1);
  });

  test('the shield destroys obstacles instead of the ship', () {
    final w = _world();
    _settle(w);
    w.playerState.activatePowerUp(PowerUpType.shield);
    w.step();
    final a = AsteroidBig(w);
    w.addGameObject(a, w.ship.x, w.ship.y);
    w.step();
    expect(a.attached, isFalse);
    expect(w.gameOver, isFalse);
  });

  test('a hit without shield ends the game two seconds later', () {
    final w = _world();
    _settle(w);
    w.step();
    final a = AsteroidBig(w);
    w.addGameObject(a, w.ship.x, w.ship.y);
    w.step();
    expect(w.gameOver, isTrue);
    expect(w.ship.visible, isFalse);
    w.events.clear();
    for (int i = 0; i < 119; i++) {
      w.step();
    }
    expect(w.events.whereType<GameOverEvent>(), isEmpty);
    w.step();
    expect(w.events.whereType<GameOverEvent>(), hasLength(1));
  });

  test('scrolling stops while a boss is on screen', () {
    final w = _world();
    _settle(w);
    final boss = EnemyBoss(w, 0);
    w.addGameObject(boss, 0, -w.scroll - 300);
    w.playerState.boss = boss;
    for (int i = 0; i < 120; i++) {
      w.step();
    }
    expect(w.playerState.scrollSpeed, lessThan(0.01));
  });

  test('speed boost scrolls six times faster and adds a shield', () {
    final w = _world();
    _settle(w);
    w.playerState.activatePowerUp(PowerUpType.speedBoost);
    for (int i = 0; i < 90; i++) {
      w.step();
    }
    expect(w.playerState.scrollSpeed, closeTo(12, 0.1));
    expect(w.playerState.shieldActive, isTrue);
  });

  test('upgrade prices and power-up durations match the original', () {
    final s = PersistentGameState()..coins = 10000;
    expect(s.laserUpgradePrice(), 200);
    expect(s.upgradeLaser(), isTrue);
    expect(s.laserUpgradePrice(), 300);
    expect(s.powerUpUpgradePrice(PowerUpType.shield), 100);
    expect(s.powerUpFrames(PowerUpType.shield), 300);
    expect(s.powerUpFrames(PowerUpType.speedBoost), 150);
    s.upgradePowerUp(PowerUpType.speedBoost);
    expect(s.powerUpFrames(PowerUpType.speedBoost), 175);
  });

  test('levels progress through the original nine-chunk layout', () {
    final w = _world(startLevel: 1);
    _clear(w);
    w.playerState.activatePowerUp(PowerUpType.shield);
    final kinds = <ObjectKind>{};
    for (int i = 0; i < 60 * 45; i++) {
      w.playerState.activatePowerUp(PowerUpType.shield);
      w.step();
      for (final o in w.children) {
        kinds.add(o.kind);
      }
    }
    expect(
      kinds,
      containsAll([
        ObjectKind.enemyScout,
        ObjectKind.enemyDestroyer,
        ObjectKind.enemyBoss,
        ObjectKind.asteroidPowerUp,
      ]),
    );
    expect(w.topLevelReached, greaterThanOrEqualTo(1));
  });
}
