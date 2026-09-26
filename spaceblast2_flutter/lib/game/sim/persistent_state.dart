import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'power_up_type.dart';

/// Upgrades, coins and scores that survive between sessions. Stored with the
/// same key and JSON layout as the original game.
class PersistentGameState extends ChangeNotifier {
  static const _prefsKey = 'game_prefs';

  /// Demo unlocks (0-based, shown as +1): level 5 can be started, and is
  /// selected on launch, the laser is at least level 8 and there are at
  /// least [demoCoins] coins.
  static const demoStartingLevel = 4;
  static const demoLaserLevel = 7;
  static const demoCoins = 1337;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_prefsKey);
      if (json != null) {
        final Map data = const JsonDecoder().convert(json);
        coins = data['coins'];
        _powerupLevels = (data['powerUpLevels'] as List).cast<int>();
        _currentStartingLevel = data['currentStartingLevel'];
        maxStartingLevel = data['maxStartingLevel'];
        laserLevel = data['laserLevel'];
        _lastScore = data['lastScore'];
        weeklyBestScore = data['bestScore'];
      }
    } catch (e) {
      debugPrint('Failed to load game state: $e');
    }
    if (maxStartingLevel < demoStartingLevel) {
      maxStartingLevel = demoStartingLevel;
    }
    _currentStartingLevel = demoStartingLevel;
    if (laserLevel < demoLaserLevel) laserLevel = demoLaserLevel;
    if (coins < demoCoins) coins = demoCoins;
  }

  Future<void> store() async {
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = {
        'coins': coins,
        'powerUpLevels': _powerupLevels,
        'currentStartingLevel': _currentStartingLevel,
        'maxStartingLevel': maxStartingLevel,
        'laserLevel': laserLevel,
        'lastScore': _lastScore,
        'bestScore': weeklyBestScore,
      };
      await prefs.setString(_prefsKey, const JsonEncoder().convert(data));
    } catch (e) {
      debugPrint('Failed to store game state: $e');
    }
  }

  int coins = 0;

  List<int> _powerupLevels = <int>[0, 0, 0, 0];

  int powerupLevel(PowerUpType type) => _powerupLevels[type.index];

  int maxPowerUpLevel = 8;

  int _currentStartingLevel = 0;

  int get currentStartingLevel => _currentStartingLevel;

  set currentStartingLevel(int currentStartingLevel) {
    if (currentStartingLevel >= 0 && currentStartingLevel <= maxStartingLevel) {
      _currentStartingLevel = currentStartingLevel;
      notifyListeners();
    }
  }

  int maxStartingLevel = 0;

  int laserLevel = 0;

  int maxLaserLevel = 11;

  int _lastScore = 0;

  int get lastScore => _lastScore;

  set lastScore(int lastScore) {
    _lastScore = lastScore;
    if (lastScore > weeklyBestScore) weeklyBestScore = lastScore;
  }

  int weeklyBestScore = 0;

  int powerUpUpgradePrice(PowerUpType type) {
    final level = powerupLevel(type) + 1;
    return level * 50 + 50;
  }

  bool isPowerUpMaxed(PowerUpType type) =>
      _powerupLevels[type.index] >= maxPowerUpLevel;

  int powerUpFrames(PowerUpType type) {
    final level = powerupLevel(type);
    if (type == PowerUpType.speedBoost) {
      return 150 + 25 * level;
    } else {
      return 300 + 50 * level;
    }
  }

  bool upgradePowerUp(PowerUpType type) {
    final price = powerUpUpgradePrice(type);
    if (coins >= price && _powerupLevels[type.index] < maxPowerUpLevel) {
      coins -= price;
      _powerupLevels[type.index] += 1;
      store();
      return true;
    } else {
      return false;
    }
  }

  int laserUpgradePrice() => laserLevel * 100 + 200;

  bool get isLaserMaxed => laserLevel >= maxLaserLevel;

  bool upgradeLaser() {
    if (coins >= laserUpgradePrice() && laserLevel < maxLaserLevel) {
      coins -= laserUpgradePrice();
      laserLevel++;
      store();
      return true;
    } else {
      return false;
    }
  }

  void reachedLevel(int level) {
    if (level > maxStartingLevel && level < 9) {
      maxStartingLevel = level;
      _currentStartingLevel = level;
    }
    store();
  }
}
