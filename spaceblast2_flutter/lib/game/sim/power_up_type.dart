enum PowerUpType { shield, speedLaser, sideLaser, speedBoost }

final List<PowerUpType> _powerUpTypes = List<PowerUpType>.from(
  PowerUpType.values,
);
int _lastPowerUp = _powerUpTypes.length;

/// Deals power-ups from a shuffled bag so every type shows up once per round.
PowerUpType nextPowerUpType() {
  if (_lastPowerUp >= _powerUpTypes.length) {
    _powerUpTypes.shuffle();
    _lastPowerUp = 0;
  }

  final type = _powerUpTypes[_lastPowerUp];
  _lastPowerUp++;
  return type;
}

extension PowerUpTypeByName on PowerUpType {
  static PowerUpType byName(String name) =>
      PowerUpType.values.firstWhere((t) => t.name == name);
}
