import 'game_objects.dart';
import 'power_up_type.dart';

/// Things that happened during a simulation step that the presentation layer
/// (renderer, audio, HUD) reacts to. The simulation never depends on them.
sealed class GameEvent {
  const GameEvent();
}

class SoundEvent extends GameEvent {
  const SoundEvent(this.name);
  final String name;
}

enum ExplosionKind { big, mini }

class ExplosionEvent extends GameEvent {
  const ExplosionEvent(
    this.kind,
    this.x,
    this.y,
    this.scale, {
    required this.source,
    required this.variant,
  });

  final ExplosionKind kind;
  final double x;
  final double y;
  final double scale;
  final ObjectKind source;
  final int variant;
}

class FlashEvent extends GameEvent {
  const FlashEvent();
}

class MuzzleFlashEvent extends GameEvent {
  const MuzzleFlashEvent(this.x, this.y, this.direction, this.size);
  final double x;
  final double y;
  final double direction;
  final double size;
}

class PowerUpCollectedEvent extends GameEvent {
  const PowerUpCollectedEvent(this.type, this.x, this.y);
  final PowerUpType type;
  final double x;
  final double y;
}

class CoinCollectedEvent extends GameEvent {
  const CoinCollectedEvent(this.x, this.y);
  final double x;
  final double y;
}

class ShipDestroyedEvent extends GameEvent {
  const ShipDestroyedEvent(this.x, this.y);
  final double x;
  final double y;
}

class ScoreChangedEvent extends GameEvent {
  const ScoreChangedEvent(this.score);
  final int score;
}

class CoinCountChangedEvent extends GameEvent {
  const CoinCountChangedEvent(this.coins);
  final int coins;
}

class GameOverEvent extends GameEvent {
  const GameOverEvent(this.score, this.coins, this.levelReached);
  final int score;
  final int coins;
  final int levelReached;
}
