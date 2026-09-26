import 'dart:math' as math;
import 'dart:ui';

import 'events.dart';
import 'game_math.dart';
import 'game_objects.dart';
import 'motions.dart';
import 'persistent_state.dart';
import 'power_up_type.dart';
import 'world.dart';

/// A collected coin flying to the HUD counter. The counter only goes up when
/// it arrives, like in the original.
class CoinFlight {
  CoinFlight(this.path);

  /// Start, middle and end point in screen game units (320 wide).
  final List<Offset> path;

  int steps = 0;

  /// Seconds into the 0.5s flight, following MotionInterval's first-tick rule.
  double get elapsed => math.max(0, steps - 1) / GameWorld.stepsPerSecond;

  double get t => (elapsed / CoinFlight.duration).clamp(0.0, 1.0);

  static const double duration = 0.5;

  Offset positionAt(double t) => splinePoint(path, 0.25, t);
}

/// Score, coins, power-up timers and scroll speed for the current run.
class PlayerState {
  PlayerState(this._world, this._gameState) {
    laserLevel = _gameState.laserLevel;
  }

  final GameWorld _world;
  final PersistentGameState _gameState;

  /// Where coins fly to, in screen game units. Set by the HUD layout.
  static Offset coinTarget = const Offset(30.0, 50.0);

  int laserLevel = 0;

  static const double normalScrollSpeed = 2.0;

  double scrollSpeed = normalScrollSpeed;
  double _scrollSpeedTarget = normalScrollSpeed;

  EnemyBoss? boss;

  int _score = 0;
  int get score => _score;
  set score(int score) {
    _score = score;
    _world.emit(ScoreChangedEvent(score));
  }

  int _coins = 0;
  int get coins => _coins;

  final List<CoinFlight> coinFlights = [];

  void addCoin(Coin c) {
    // Animate the coin from where it was picked up to the top of the screen.
    final startPos = _world.levelToScreen(c.x, c.y);
    final finalPos = coinTarget;
    final middlePos = Offset(
      (startPos.dx + finalPos.dx) / 2.0 + 50.0,
      (startPos.dy + finalPos.dy) / 2.0,
    );
    coinFlights.add(CoinFlight([startPos, middlePos, finalPos]));
  }

  /// Advances the coin flights (they are motions in the original, so they run
  /// in the motion phase of the step).
  void stepCoinFlights() {
    for (int i = coinFlights.length - 1; i >= 0; i--) {
      final flight = coinFlights[i];
      flight.steps++;
      if (flight.elapsed >= CoinFlight.duration - 1e-9) {
        coinFlights.removeAt(i);
        _coins += 1;
        _world.emit(CoinCountChangedEvent(_coins));
      }
    }
  }

  void activatePowerUp(PowerUpType type) {
    if (type == PowerUpType.shield) {
      _shieldFrames += _gameState.powerUpFrames(type);
    } else if (type == PowerUpType.sideLaser) {
      _sideLaserFrames += _gameState.powerUpFrames(type);
    } else if (type == PowerUpType.speedLaser) {
      _speedLaserFrames += _gameState.powerUpFrames(type);
    } else if (type == PowerUpType.speedBoost) {
      _speedBoostFrames += _gameState.powerUpFrames(type);
      _shieldFrames += _gameState.powerUpFrames(type) + 60;
    }
  }

  int _shieldFrames = 0;
  bool get shieldActive => _shieldFrames > 0 || _speedBoostFrames > 0;
  bool get shieldDeactivating =>
      math.max(_shieldFrames, _speedBoostFrames) > 0 &&
      math.max(_shieldFrames, _speedBoostFrames) < 60;

  int _sideLaserFrames = 0;
  bool get sideLaserActive => _sideLaserFrames > 0;

  int _speedLaserFrames = 0;
  bool get speedLaserActive => _speedLaserFrames > 0;

  int _speedBoostFrames = 0;
  bool get speedBoostActive => _speedBoostFrames > 0;

  /// Remaining frames per power-up, for the HUD.
  int framesLeft(PowerUpType type) => switch (type) {
    PowerUpType.shield => math.max(_shieldFrames, _speedBoostFrames),
    PowerUpType.speedLaser => _speedLaserFrames,
    PowerUpType.sideLaser => _sideLaserFrames,
    PowerUpType.speedBoost => _speedBoostFrames,
  };

  void update() {
    if (_shieldFrames > 0) _shieldFrames--;
    if (_sideLaserFrames > 0) _sideLaserFrames--;
    if (_speedLaserFrames > 0) _speedLaserFrames--;
    if (_speedBoostFrames > 0) _speedBoostFrames--;

    // Update speed
    final boss = this.boss;
    if (boss != null) {
      final bossScreenY = _world.levelToScreen(boss.x, boss.y).dy;
      if (bossScreenY > (_world.gameHeight - 400.0)) {
        _scrollSpeedTarget = 0.0;
      } else {
        _scrollSpeedTarget = normalScrollSpeed;
      }
    } else {
      if (speedBoostActive) {
        _scrollSpeedTarget = normalScrollSpeed * 6.0;
      } else {
        _scrollSpeedTarget = normalScrollSpeed;
      }
    }

    scrollSpeed = GameMath.filter(scrollSpeed, _scrollSpeedTarget, 0.1);
  }
}
