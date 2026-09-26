import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:vector_math/vector_math.dart';

import 'audio.dart';
import 'render/effects.dart';
import 'render/game_camera.dart';
import 'render/game_renderer.dart';
import 'sim/events.dart';
import 'sim/game_objects.dart';
import 'sim/persistent_state.dart';
import 'sim/player_state.dart';
import 'sim/power_up_type.dart';
import 'sim/world.dart';

enum GamePhase { loading, menu, launching, playing, returning }

double _smoothstep(double t) {
  t = t.clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

double _easeInOutCubic(double t) {
  t = t.clamp(0.0, 1.0);
  return t < 0.5 ? 4 * t * t * t : 1 - math.pow(-2 * t + 2, 3) / 2;
}

/// Runs the game: owns the simulation, renderer and audio, advances the
/// simulation at a fixed 60 steps per second and drives the camera through
/// the menu, launch, gameplay and return phases.
class GameController extends ChangeNotifier {
  GameController() {
    current = this;
  }

  /// The running controller (for development tooling).
  static GameController? current;

  final PersistentGameState state = PersistentGameState();
  final GameRenderer renderer = GameRenderer();
  final AudioManager audio = AudioManager();

  late GameWorld world;

  GamePhase _phase = GamePhase.loading;
  GamePhase get phase => _phase;

  final ValueNotifier<double> loadProgress = ValueNotifier(0.0);
  final ValueNotifier<int> score = ValueNotifier(0);
  final ValueNotifier<int> coins = ValueNotifier(0);

  /// Development switch that hides the menu and HUD.
  bool debugHideUi = false;

  /// Notifies once per rendered frame (for overlays).
  final ChangeNotifier frame = ChangeNotifier();

  /// Height of the visible playfield in game units (width is always 320).
  double gameHeight = 480.0;

  double time = 0.0;

  /// Smoothed frames per second (for diagnostics).
  double fps = 60.0;

  /// Smoothed milliseconds spent in [tick] (simulation + scene update).
  double tickMs = 0.0;
  final Stopwatch _tickWatch = Stopwatch();
  double _phaseTime = 0.0;
  double get phaseTime => _phaseTime;
  double _accumulator = 0.0;

  /// Interpolation factor for the current frame.
  double alpha = 0.0;

  double _drift = 0.0;
  double _driftSpeed = 1.1;

  /// Eased moods, 0..1, used by the background and the border.
  double bossMood = 0.0;
  double boostMood = 0.0;
  double dangerMood = 0.0;

  /// Time of the last screen flash, or -inf.
  double flashTime = -100.0;

  /// Time the last score change happened (HUD pulse).
  double scoreTime = -100.0;
  double coinTime = -100.0;

  /// Time the ship appeared in the menu (warp-in effect).
  double _shipAppearTime = 0.0;

  /// Menu → gameplay camera move length.
  static const double launchDuration = 1.8;
  static const double returnDuration = 1.6;

  Future<void> load() async {
    await state.load();
    await renderer.load(onProgress: (p) => loadProgress.value = p);
    world = GameWorld(state, gameHeight: gameHeight);
    _setPhase(GamePhase.menu);
    _shipAppearTime = time;
    loadProgress.value = 1.0;
    // Start the audio engine right away (browsers keep it suspended until
    // the first tap, which then unlocks it). Starting it only on that tap
    // is too late for mobile Safari, where it would stay silent.
    audio.playMusic('music_intro');
    unawaited(audio.start());
  }

  void _setPhase(GamePhase phase) {
    _phase = phase;
    _phaseTime = 0.0;
    notifyListeners();
  }

  // --- Input ----------------------------------------------------------------

  /// Any user gesture: the browser allows audio to start from here on.
  void userGesture() {
    if (!audio.ready) unawaited(audio.start());
  }

  // --- Menu actions -----------------------------------------------------------

  void upgradeLaser() {
    audio.playEffect(state.upgradeLaser() ? 'buy_upgrade' : 'click');
  }

  void upgradePowerUp(PowerUpType type) {
    audio.playEffect(state.upgradePowerUp(type) ? 'buy_upgrade' : 'click');
  }

  void startLevelUp() {
    state.currentStartingLevel++;
    audio.playEffect('click');
  }

  void startLevelDown() {
    state.currentStartingLevel--;
    audio.playEffect('click');
  }

  void play() {
    if (_phase != GamePhase.menu) return;
    audio.playEffect('click');
    audio.playMusic('music_game');
    // A fresh world at the ship's current position, with the chosen level.
    renderer.resetWorld();
    world = GameWorld(state, gameHeight: gameHeight);
    score.value = 0;
    coins.value = 0;
    _accumulator = 0;
    _setPhase(GamePhase.launching);
  }

  void _onGameOver(GameOverEvent e) {
    state.lastScore = e.score;
    state.coins += e.coins;
    state.reachedLevel(e.levelReached);
    audio.playMusic('music_intro');
    _setPhase(GamePhase.returning);
  }

  void _finishReturn() {
    // Continue the level origin from where the old run's camera was.
    renderer.originY = renderer.originY + world.scroll * kWorld;
    renderer.resetWorld();
    world = GameWorld(state, gameHeight: gameHeight);
    _shipAppearTime = time;
    renderer.effects.pickupBurst(0, 50, [1.0, 2.2, 4.0, 1], big: true);
    _setPhase(GamePhase.menu);
  }

  // --- Frame ------------------------------------------------------------------

  void tick(double dt) {
    if (_phase == GamePhase.loading || !renderer.ready) return;
    if (dt > 0) fps += (1 / dt - fps) * 0.05;
    _tickWatch
      ..reset()
      ..start();
    dt = dt.clamp(0.0, 0.1);
    time += dt;
    _phaseTime += dt;
    world.gameHeight = gameHeight;

    switch (_phase) {
      case GamePhase.menu:
        _driftSpeed += (1.1 - _driftSpeed) * (1 - math.exp(-dt * 2));
        _drift += _driftSpeed * dt;
        alpha = 0;
      case GamePhase.launching:
        _driftSpeed += (0 - _driftSpeed) * (1 - math.exp(-dt * 3));
        _drift += _driftSpeed * dt;
        _stepSimulation(dt);
        if (_phaseTime >= launchDuration) _setPhase(GamePhase.playing);
      case GamePhase.playing:
        _stepSimulation(dt);
      case GamePhase.returning:
        _stepSimulation(dt);
        if (_phaseTime >= returnDuration) _finishReturn();
      case GamePhase.loading:
        break;
    }

    // Moods.
    final bossTarget =
        world.playerState.boss != null && _phase != GamePhase.menu ? 1.0 : 0.0;
    bossMood += (bossTarget - bossMood) * (1 - math.exp(-dt * 1.5));
    // Follows the actual scroll speed (already smoothed by the simulation),
    // so it drops when a boss stops the level even while boost is active.
    final speed = world.prevScroll == world.scroll && _phase == GamePhase.menu
        ? PlayerState.normalScrollSpeed
        : world.playerState.scrollSpeed;
    boostMood =
        ((speed - PlayerState.normalScrollSpeed) /
                (PlayerState.normalScrollSpeed * 5))
            .clamp(0.0, 1.0);
    final dangerTarget = world.gameOver ? 1.0 : 0.0;
    dangerMood += (dangerTarget - dangerMood) * (1 - math.exp(-dt * 2));

    // Boss fights get their own music.
    if (_phase == GamePhase.playing) {
      final bossAlive = world.playerState.boss != null && !world.gameOver;
      audio.playMusic(bossAlive ? 'music_boss' : 'music_game');
    }

    _adaptQuality(dt);
    _render(dt);
    frame.notifyListeners();
    tickMs += (_tickWatch.elapsedMicroseconds / 1000 - tickMs) * 0.05;
  }

  void _stepSimulation(double dt) {
    _accumulator += dt;
    int steps = 0;
    while (_accumulator >= GameWorld.dt && steps < 8) {
      world.step();
      _accumulator -= GameWorld.dt;
      steps++;
      _processEvents();
    }
    if (steps == 8) _accumulator = 0;
    alpha = (_accumulator / GameWorld.dt).clamp(0.0, 1.0);
  }

  /// Extra consumers of simulation events (the split-screen classic view).
  final List<void Function(GameEvent event)> eventListeners = [];

  void _processEvents() {
    final events = List<GameEvent>.of(world.events);
    world.events.clear();
    for (final e in events) {
      for (final listener in eventListeners) {
        listener(e);
      }
      switch (e) {
        case SoundEvent s:
          audio.playEffect(s.name);
        case FlashEvent _:
          flashTime = time;
        case ScoreChangedEvent s:
          score.value = s.score;
          scoreTime = time;
        case CoinCountChangedEvent c:
          coins.value = c.coins;
          coinTime = time;
        case CoinCollectedEvent c:
          renderer.coinCollected(c.x, c.y);
        case GameOverEvent g:
          _onGameOver(g);
        default:
          renderer.handleEvent(e, world);
      }
    }
  }

  /// Keeps heavy scenes smooth on slower devices: when the frame rate drops
  /// below ~50 FPS, effect density and then render resolution go down; they
  /// recover slowly once frames are fast again.
  void _adaptQuality(double dt) {
    if (_phaseTime < 1.0) return;
    _scaleCooldown = math.max(0.0, _scaleCooldown - dt);
    final effects = renderer.effects;
    final scene = renderer.scene;
    if (fps < 50) {
      effects.quality = math.max(0.4, effects.quality - dt * 0.6);
      // Resolution changes reallocate render targets, so step it rarely.
      if (effects.quality < 0.7 &&
          _scaleCooldown == 0 &&
          scene.renderScale > 0.65) {
        scene.renderScale = math.max(0.65, scene.renderScale - 0.1);
        _scaleCooldown = 2.0;
      }
    } else if (fps > 57) {
      if (scene.renderScale < 1.0) {
        if (_scaleCooldown == 0) {
          scene.renderScale = math.min(1.0, scene.renderScale + 0.1);
          _scaleCooldown = 6.0;
        }
      } else {
        effects.quality = math.min(1.0, effects.quality + dt * 0.1);
      }
    }
  }

  double _scaleCooldown = 0.0;

  double get _scrollInterpolated =>
      world.prevScroll + (world.scroll - world.prevScroll) * alpha;

  /// Interpolated ship position in world units.
  Vector3 _shipWorld() {
    final s = world.ship;
    final x = s.prevX + (s.x - s.prevX) * alpha;
    final y = s.prevY + (s.y - s.prevY) * alpha;
    return Vector3(x * kWorld, -y * kWorld + renderer.originY, 0);
  }

  CameraShot gameplayShot(double scrollPx) {
    const d = GameRenderer.cameraDistance;
    const off = GameRenderer.cameraOffset;
    final halfH = gameHeight * kWorld / 2;
    final yc = renderer.originY + (scrollPx + gameHeight / 2) * kWorld;
    final eye = Vector3(0, yc - off, -d);
    return CameraShot(
      eye: eye,
      target: eye + Vector3(0, 0, 1),
      up: Vector3(0, 1, 0),
      fovY: 2 * math.atan(halfH / d),
      shiftY: -off / halfH,
    );
  }

  /// The cinematic chase shot behind the ship used by the menu.
  CameraShot heroShot(Vector3 ship) {
    final t = time;
    final swing = math.sin(t * 0.21) * 0.6;
    final lift = 2.7 + math.sin(t * 0.13) * 0.15;
    final eye =
        ship +
        Vector3(math.sin(swing) * 1.9, -math.cos(swing) * 1.9 - 0.1, -lift);
    // Aim behind the ship so it sits in the upper middle of the frame,
    // between the title and the upgrade panel.
    final target = ship + Vector3(math.sin(swing) * 0.35, -0.05, 0.6);
    return CameraShot(
      eye: eye,
      target: target,
      up: Vector3(0, 0.7, -1).normalized(),
      fovY: 46 * math.pi / 180,
    );
  }

  /// Where the ship will be when the next run starts (for the return shot).
  Vector3 _nextShipWorld() =>
      Vector3(0, renderer.originY + _scrollInterpolated * kWorld - 0.5, 0);

  CameraShot currentShot() {
    switch (_phase) {
      case GamePhase.menu:
      case GamePhase.loading:
        return heroShot(_shipWorld());
      case GamePhase.launching:
        final t = _easeInOutCubic(_phaseTime / launchDuration);
        // The chase shot keeps following the ship as it rises.
        final from = heroShot(_shipWorld());
        return CameraShot.lerp(from, gameplayShot(_scrollInterpolated), t);
      case GamePhase.playing:
        return gameplayShot(_scrollInterpolated);
      case GamePhase.returning:
        final t = _easeInOutCubic(_phaseTime / returnDuration);
        return CameraShot.lerp(
          gameplayShot(_scrollInterpolated),
          heroShot(_nextShipWorld()),
          t,
        );
    }
  }

  /// 1 in the menu, 0 while playing.
  double get menuAmount => switch (_phase) {
    GamePhase.menu || GamePhase.loading => 1.0,
    GamePhase.launching => 1.0 - _smoothstep(_phaseTime / launchDuration),
    GamePhase.playing => 0.0,
    GamePhase.returning => _smoothstep(_phaseTime / returnDuration),
  };

  void _render(double dt) {
    final shot = currentShot();
    final menu = menuAmount;

    // Depth of field only for the cinematic menu shot. In gameplay it would
    // blur transparent objects (crystals, glows) together with the
    // background behind them, so the background is pre-blurred instead.
    final shipPos = _phase == GamePhase.returning
        ? _nextShipWorld()
        : _shipWorld();
    final dof = renderer.scene.depthOfField;
    // Skipped on mobile: it costs extra render targets and misbehaves in
    // mobile Safari.
    dof.enabled = menu > 0.02 && !GameRenderer.isMobile;
    dof.focusDistance = (shot.eye - shipPos).length;
    dof.fStop = (6.0 / menu.clamp(0.02, 1.0)).clamp(6.0, 96.0);

    // Warp-in scale for the menu ship.
    final appear = _phase == GamePhase.menu
        ? _smoothstep((time - _shipAppearTime) / 0.6)
        : 1.0;

    renderer.render(
      FrameInfo(
        world: world,
        alpha: alpha,
        dt: dt,
        time: time,
        shot: shot,
        showObjects: _phase != GamePhase.menu,
        menuAmount: menu,
        drift: _drift,
        boss: bossMood,
        boost: boostMood,
        shipScale: appear,
      ),
    );
  }

  /// Screen position (game units) of a point on the playfield, projected
  /// through the live camera so it stays attached during camera moves.
  Offset levelToScreen(double x, double y) {
    final p = renderer.camera.worldToScreen(
      Vector3(x * kWorld, -y * kWorld + renderer.originY, 0),
      Size(320, gameHeight),
    );
    return p ?? const Offset(-1000, -1000);
  }

  PlayerState get playerState => world.playerState;
  List<GameObject> get objects => world.children;

  @override
  void dispose() {
    loadProgress.dispose();
    score.dispose();
    coins.dispose();
    frame.dispose();
    super.dispose();
  }
}
