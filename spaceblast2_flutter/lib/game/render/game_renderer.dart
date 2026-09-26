import 'dart:math' as math;

import 'package:flutter/animation.dart' show Curves;
import 'package:flutter/foundation.dart';
import 'package:flutter_scene/gpu.dart' as gpu;
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';

import '../sim/events.dart';
import '../sim/game_objects.dart';
import '../sim/power_up_type.dart';
import '../sim/world.dart';
import 'effects.dart';
import 'game_camera.dart';
import 'geometry.dart';
import 'light_pool.dart';
import 'models.dart';
import 'procedural_textures.dart';
import 'sprite_batch.dart';

final math.Random _rnd = math.Random();

/// Colors of the player's laser by laser level (from the original).
const List<List<double>> laserColors = [
  [0x95 / 255, 0xf4 / 255, 0xfb / 255],
  [0x5b / 255, 0xff / 255, 0x35 / 255],
  [0xff / 255, 0x88 / 255, 0x6c / 255],
  [0xff / 255, 0xd0 / 255, 0x12 / 255],
  [0xfd / 255, 0x7f / 255, 0xff / 255],
];

/// Per-object render state, stored in [GameObject.visual].
class _Visual {
  _Visual(this.object);

  final GameObject object;
  ModelInstance? model;
  ModelInstance? second;

  // Asteroid tumble.
  Vector3 spinAxis = Vector3(0, 0, 1);
  Quaternion tumble = Quaternion.identity();

  // Banking for ships.
  double bank = 0.0;
  double phase = _rnd.nextDouble() * 100;

  List<Node>? sparkles;
  Node? anchor;
}

/// Frame inputs from the controller.
class FrameInfo {
  FrameInfo({
    required this.world,
    required this.alpha,
    required this.dt,
    required this.time,
    required this.shot,
    required this.showObjects,
    required this.menuAmount,
    required this.drift,
    required this.boss,
    required this.boost,
    this.shipScale = 1.0,
  });

  final GameWorld world;

  /// Interpolation factor between the previous and the current step.
  final double alpha;
  final double dt;
  final double time;
  final CameraShot shot;

  /// False in the menu, where only the ship is shown.
  final bool showObjects;

  /// 1 in the menu, 0 in gameplay.
  final double menuAmount;

  /// Extra scroll (world units) used to keep the menu background moving.
  final double drift;

  /// Boss mood 0..1 and speed boost amount 0..1, eased.
  final double boss;
  final double boost;

  /// Scale of the player's ship (the menu warp-in).
  final double shipScale;
}

/// Owns the flutter_scene [Scene] and turns the simulation into pictures.
class GameRenderer {
  late final Scene scene;
  final GameCamera camera = GameCamera();
  final ModelLibrary models = ModelLibrary();

  late final EffectBatches batches;
  late final EffectsSystem effects;
  late final LightPool lights;

  late final List<SpriteBatch> _iconBatches;
  late final SpriteBatch _shieldBatch;
  late final SpriteBatch _hexShieldBatch;
  late final SpriteBatch _starBatch0;
  late final SpriteBatch _starBatch1;
  late final SpriteBatch _dustBatch;
  late final SpriteBatch _flameBatch;
  late final SpriteBatch _streakBatch;
  late final SpriteBatch _menuStreakBatch;
  late final ParticleLayer _menuStreaks;

  late final Geometry _coinGeometry;
  late final PhysicallyBasedMaterial _coinMaterial;
  final List<Node> _coinPool = [];
  late final Geometry _gemGeometry;
  late final PhysicallyBasedMaterial _gemMaterial;
  final List<Node> _gemPool = [];

  PreprocessedMaterial? _backdropMaterial;
  final List<PreprocessedMaterial> _nebulaMaterials = [];
  final List<Node> _backgroundPlanes = [];
  final List<double> _backgroundDepths = [];

  final List<_Visual> _live = [];
  final _Stars _stars = _Stars();

  final List<Node> _shotLightNodes = [];

  bool _ready = false;
  bool get ready => _ready;

  /// World Y (units) of the current run's level origin. Each new run starts
  /// where the previous one ended so the camera never jumps.
  double _originY = 0.0;
  double get originY => _originY;
  set originY(double value) {
    _originY = value;
    effects.originY = value;
  }

  /// Phones and tablets (including mobile browsers) get a lighter setup:
  /// mobile Safari kills tabs that use too much GPU memory.
  static bool get isMobile =>
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android;

  /// Render resolution cap (device pixels per logical pixel).
  static double get maxPixelRatio => isMobile ? 1.5 : 2.0;

  /// Gameplay camera distance from the playfield, in world units.
  static const double cameraDistance = 6.5;

  /// How far south of the screen center the gameplay camera sits.
  static const double cameraOffset = 1.7;

  Future<void> load({void Function(double progress)? onProgress}) async {
    // The engine logs and swallows loading errors; load the shader bundle
    // first so a failure surfaces with its real message.
    await loadBaseShaderLibrary();
    await Scene.initializeStaticResources();
    if (!Scene.isReadyToRender) {
      throw StateError('Flutter Scene failed to initialize.');
    }
    scene = Scene();

    final watch = Stopwatch()..start();
    debugPrint('load: static resources ${watch.elapsedMilliseconds}ms');
    double modelProgress = 0.0;
    double otherProgress = 0.0;
    void report() =>
        onProgress?.call(modelProgress * 0.7 + otherProgress * 0.3);

    final modelsFuture = models.load(
      onProgress: (p) {
        modelProgress = p;
        report();
      },
    );

    Future<Texture2D> tex(String name) =>
        Texture2D.fromAsset('assets/sprites/$name.png');

    final results = await Future.wait<Object>([
      tex('explosion_particle'), // 0
      tex('fire_particle'), // 1
      tex('explosion_ring'), // 2
      tex('explosion_flare'), // 3
      tex('star_0'), // 4
      tex('star_1'), // 5
      tex('shield'), // 6
      tex('powerup'), // 7
      tex('powerup_0'), // 8
      tex('powerup_1'), // 9
      tex('powerup_2'), // 10
      tex('powerup_3'), // 11
      ProceduralTextures.glow(), // 12
      ProceduralTextures.puff(), // 13
      ProceduralTextures.spark(), // 14
      ProceduralTextures.ring(), // 15
      ProceduralTextures.twinkle(), // 16
      ProceduralTextures.shield(), // 17
      Texture2D.fromAsset('assets/textures/starfield.png'), // 18
      Texture2D.fromAsset('assets/textures/nebula.png'), // 19
      ProceduralTextures.flame(), // 20
      ProceduralTextures.streak(), // 21
    ]);
    otherProgress = 0.6;
    report();
    debugPrint('load: textures ${watch.elapsedMilliseconds}ms');

    Texture2D t(int i) => results[i] as Texture2D;

    batches = EffectBatches(
      particle: SpriteBatch(t(0), capacity: 1400),
      fire: SpriteBatch(t(1), capacity: 1000),
      glow: SpriteBatch(t(12), capacity: 2600),
      spark: SpriteBatch(t(14), capacity: 1400),
      fireball: SpriteBatch(t(13), capacity: 1000),
      smoke: SpriteBatch(t(13), additive: false, capacity: 800),
      ring: SpriteBatch(t(2), capacity: 64),
      shockwave: SpriteBatch(t(15), capacity: 96),
      flare: SpriteBatch(t(3), capacity: 256),
      star: SpriteBatch(t(4), capacity: 256),
      twinkle: SpriteBatch(t(16), capacity: 800),
    );
    // The original power-up icons (256px sprites, icon in the middle).
    _iconBatches = [
      for (int i = 8; i <= 11; i++)
        SpriteBatch(t(i), additive: false, capacity: 64),
    ];
    _shieldBatch = SpriteBatch(t(6), capacity: 4);
    _hexShieldBatch = SpriteBatch(t(17), capacity: 4);
    _starBatch0 = SpriteBatch(t(4), capacity: 512);
    _starBatch1 = SpriteBatch(t(5), capacity: 512);
    _dustBatch = SpriteBatch(t(12), capacity: 512);
    _flameBatch = SpriteBatch(t(20), capacity: 16);
    _streakBatch = SpriteBatch(t(21), capacity: 512);
    // Menu shooting stars: velocity-stretched so they stay aligned with
    // their motion from any camera angle.
    _menuStreakBatch = SpriteBatch(
      t(21),
      capacity: 128,
      facing: BillboardFacing.velocityStretched,
      velocityStretch: 0.07,
    );
    _menuStreaks = ParticleLayer(_menuStreakBatch, capacity: 128);

    lights = LightPool(scene, size: 14);
    effects = EffectsSystem(scene, batches, lights);

    // Background layers.
    try {
      final backdrop = await loadFmatMaterial(
        'assets/materials/space_backdrop.fmat',
      );
      final sampler = gpu.SamplerOptions(
        minFilter: gpu.MinMagFilter.linear,
        magFilter: gpu.MinMagFilter.linear,
        mipFilter: gpu.MipFilter.linear,
        widthAddressMode: gpu.SamplerAddressMode.repeat,
        heightAddressMode: gpu.SamplerAddressMode.repeat,
      );
      backdrop.parameters.setTexture(
        'starfield_texture',
        t(18).gpuTexture,
        sampler: sampler,
      );
      backdrop.parameters.setTexture(
        'nebula_texture',
        t(19).gpuTexture,
        sampler: sampler,
      );
      _backdropMaterial = backdrop;

      for (int i = 0; i < 2; i++) {
        final neb = await loadFmatMaterial(
          'assets/materials/nebula_layer.fmat',
        );
        neb.parameters.setTexture(
          'nebula_texture',
          t(19).gpuTexture,
          sampler: sampler,
        );
        _nebulaMaterials.add(neb);
      }
    } catch (e, st) {
      debugPrint('Background materials failed to load: $e\n$st');
    }
    otherProgress = 0.8;
    report();

    debugPrint('load: materials ${watch.elapsedMilliseconds}ms');
    await modelsFuture;
    debugPrint('load: models ${watch.elapsedMilliseconds}ms');

    _coinGeometry = buildGemGeometry();
    // The power-up pickup gem: vertex-colored facets, glossy, with a faint
    // inner glow.
    _gemGeometry = buildBadgeGemGeometry();
    _gemMaterial = PhysicallyBasedMaterial()
      ..baseColorFactor = Vector4(1, 1, 1, 1)
      ..metallicFactor = 0.1
      ..roughnessFactor = 0.25
      ..emissiveFactor = Vector4(0.1, 0.16, 0.3, 1);
    // A glossy green gem that relies on the lights for its look: only a
    // faint inner glow, so the facets read as 3D.
    _coinMaterial = PhysicallyBasedMaterial()
      ..baseColorFactor = Vector4(0.05, 0.62, 0.3, 1)
      ..metallicFactor = 0.2
      ..roughnessFactor = 0.2
      ..emissiveFactor = Vector4(0.02, 0.16, 0.08, 1);

    _buildScene();
    _warmPools();
    otherProgress = 1.0;
    report();
    debugPrint('load: done ${watch.elapsedMilliseconds}ms');
    _ready = true;
  }

  void _warmPools() {
    for (final name in [
      'asteroid_small_0',
      'asteroid_small_1',
      'asteroid_small_2',
    ]) {
      models.warm(name, 16);
    }
    for (final name in ['asteroid_big_0', 'asteroid_big_1', 'asteroid_big_2']) {
      models.warm(name, 6);
    }
    for (int i = 0; i < 3; i++) {
      models.warm('enemy_scout_$i', 4);
      models.warm('enemy_destroyer_$i', 3);
    }
  }

  void _buildScene() {
    // Background planes: deep backdrop, then two nebula layers.
    _addBackgroundPlane(_backdropMaterial, cameraDistance * 9.0);
    if (_nebulaMaterials.length == 2) {
      _addBackgroundPlane(_nebulaMaterials[0], cameraDistance * 2.4);
      _addBackgroundPlane(_nebulaMaterials[1], cameraDistance * 0.9);
      _nebulaMaterials[0].parameters.setVec4(
        'layer',
        Vector4(30.0, 0.9, 0.3, 1.3),
      );
      _nebulaMaterials[0].parameters.setVec4(
        'tint',
        Vector4(0.55, 0.6, 1.2, 1),
      );
      _nebulaMaterials[1].parameters.setVec4(
        'layer',
        Vector4(18.0, 0.7, 0.32, 4.1),
      );
      _nebulaMaterials[1].parameters.setVec4(
        'tint',
        Vector4(1.1, 0.55, 1.0, 1),
      );
    }

    for (final batch in [
      _starBatch0,
      _starBatch1,
      batches.smoke,
      batches.glow,
      batches.fireball,
      batches.fire,
      batches.ring,
      batches.shockwave,
      batches.flare,
      batches.particle,
      batches.spark,
      batches.star,
      batches.twinkle,
      ..._iconBatches,
      _shieldBatch,
      _hexShieldBatch,
      _dustBatch,
      _flameBatch,
      _streakBatch,
      _menuStreakBatch,
    ]) {
      scene.add(batch.node);
    }

    // Dramatic base lighting: a strong, warm key light raking in from the
    // upper left, very little ambient, and colored rim lights behind the
    // playfield. Everything else comes from dynamic lights (explosions,
    // lasers, engines, crystals) handed out by [lights].
    scene.directionalLight = DirectionalLight(
      direction: Vector3(0.75, -0.5, 0.45).normalized(),
      color: Vector3(1.0, 0.9, 0.78),
      intensity: 3.0,
    );
    scene.environmentIntensity = 0.16;

    for (final (pos, color, intensity) in [
      (Vector3(-3.2, 3.0, 1.2), Vector3(0.55, 0.3, 1.0), 38.0),
      (Vector3(3.4, -1.5, 1.0), Vector3(0.15, 0.75, 1.0), 30.0),
    ]) {
      final light = PointLight(color: color, intensity: intensity, range: 8.0);
      final node = Node()..addComponent(PointLightComponent(light));
      node.position = pos;
      scene.add(node);
      _shotLightNodes.add(node);
    }
    _shotLightOffsets.addAll([
      Vector3(-3.2, 3.0, 1.2),
      Vector3(3.4, -1.5, 1.0),
    ]);

    scene.environmentSettings = EnvironmentSettings(
      toneMapping: ToneMappingMode.aces,
      exposure: 1.0,
      environmentIntensity: 0.16,
      colorGradingEnabled: true,
      contrast: 1.12,
      saturation: 1.15,
      brightness: 1.0,
      bloomEnabled: true,
      bloomThreshold: 0.9,
      bloomIntensity: 0.32,
      bloomScatter: 0.72,
      vignetteEnabled: true,
      vignetteIntensity: 0.38,
      vignetteRadius: 0.8,
      chromaticAberrationEnabled: true,
      chromaticAberrationIntensity: 0.05,
      filmGrainEnabled: true,
      filmGrainIntensity: 0.035,
      // Only used by the menu shot (see GameController).
      depthOfFieldEnabled: false,
      depthOfFieldFocusDistance: cameraDistance,
      depthOfFieldFStop: 2.4,
      depthOfFieldQuality: DepthOfFieldQuality.low,
      depthOfFieldMaxBackgroundBlur: 14,
      depthOfFieldMaxForegroundBlur: 12,
      depthOfFieldBlurScale: 2.5,
      fogEnabled: true,
      fogMode: FogMode.exponential,
      fogColor: Vector3(0.012, 0.008, 0.035),
      fogDensity: 0.012,
    );
    if (isMobile) {
      // Post-process FXAA instead of multisampled HDR targets, and no film
      // grain or chromatic aberration passes.
      scene.antiAliasingMode = AntiAliasingMode.fxaa;
      scene.postProcess.filmGrain.enabled = false;
      scene.postProcess.chromaticAberration.enabled = false;
    }
  }

  final List<Vector3> _shotLightOffsets = [];

  void _addBackgroundPlane(Material? material, double depth) {
    if (material == null) return;
    final node = Node(
      mesh: Mesh(PlaneGeometry(width: 1, depth: 1), material),
    )..frustumCulled = false;
    scene.add(node);
    _backgroundPlanes.add(node);
    _backgroundDepths.add(depth);
  }

  /// Releases every object visual (a new game starts).
  void resetWorld() {
    for (final v in _live) {
      _releaseVisual(v);
      v.object.visual = null;
    }
    _live.clear();
    effects.clear();
  }

  // --- Events ---------------------------------------------------------------

  void handleEvent(GameEvent event, GameWorld world) {
    switch (event) {
      case ExplosionEvent e:
        if (e.kind == ExplosionKind.big) {
          effects.bigExplosion(
            e.x,
            e.y,
            e.scale,
            source: e.source,
            variant: e.variant,
          );
        } else {
          effects.miniExplosion(e.x, e.y);
        }
      case MuzzleFlashEvent e:
        effects.muzzleFlash(e.x, e.y, e.direction, e.size);
      case PowerUpCollectedEvent e:
        effects.pickupBurst(e.x, e.y, [1.2, 3.0, 4.0, 1], big: true);
      default:
        break;
    }
  }

  void coinCollected(double x, double y) {
    effects.pickupBurst(x, y, [0.8, 4.0, 2.0, 1]);
  }

  // --- Frame ----------------------------------------------------------------

  void render(FrameInfo f) {
    if (!_ready) return;
    final world = f.world;

    // Camera with shake.
    final (sx, sy, roll) = effects.shake(f.time);
    final shot = f.shot;
    camera.apply(shot);
    if (sx != 0 || sy != 0) {
      camera.eye.x += sx;
      camera.eye.y += sy;
      camera.target.x += sx;
      camera.target.y += sy;
      camera.upVector.x = math.sin(roll);
      camera.upVector.y = math.cos(roll);
    }

    for (final b in batches.all) {
      b.begin();
    }
    for (final b in [
      ..._iconBatches,
      _shieldBatch,
      _hexShieldBatch,
      _starBatch0,
      _starBatch1,
      _dustBatch,
      _flameBatch,
      _streakBatch,
      _menuStreakBatch,
    ]) {
      b.begin();
    }

    lights.begin();

    // Objects.
    for (final obj in world.children) {
      if (!f.showObjects && obj is! Ship) continue;
      var v = obj.visual as _Visual?;
      if (v == null) {
        v = _createVisual(obj);
        obj.visual = v;
        _live.add(v);
      }
      _updateVisual(v, f);
    }
    for (int i = _live.length - 1; i >= 0; i--) {
      final v = _live[i];
      if (!v.object.attached || (!f.showObjects && v.object is! Ship)) {
        _releaseVisual(v);
        v.object.visual = null;
        _live.removeAt(i);
      }
    }

    _updateMenuStreaks(f);

    effects.update(f.dt);
    effects.write();
    effects.requestLights();
    lights.end();

    // Big blasts briefly push the bloom.
    scene.postProcess.bloom.intensity = 0.3 + effects.flash * 0.18;

    _updateBackground(f);

    for (final b in batches.all) {
      b.end();
    }
    for (final b in [
      ..._iconBatches,
      _shieldBatch,
      _hexShieldBatch,
      _starBatch0,
      _starBatch1,
      _dustBatch,
      _flameBatch,
      _streakBatch,
      _menuStreakBatch,
    ]) {
      b.end();
    }
  }

  // --- Background -------------------------------------------------------------

  void _updateBackground(FrameInfo f) {
    final eye = camera.eye;
    final forward = camera.forward;
    final lens = camera.lens;
    final h = math.tan(lens.fovRadiansY / 2);

    for (int i = 0; i < _backgroundPlanes.length; i++) {
      final depth = _backgroundDepths[i];
      final node = _backgroundPlanes[i];
      // Where the view center meets the plane (account for the lens shift).
      final dist = depth - eye.z;
      final centerY = eye.y - lens.shiftY * h * dist;
      final t = forward.z.abs() > 0.2 ? dist / forward.z : dist;
      final hitX = eye.x + forward.x * t;
      final hitY = forward.z.abs() > 0.2 ? eye.y + forward.y * t : centerY;
      final cy = f.menuAmount > 0
          ? hitY * f.menuAmount + centerY * (1 - f.menuAmount)
          : centerY;
      final size = dist * h * 2.0 * (2.2 + 2.5 * f.menuAmount);
      node.localTransform = Matrix4.compose(
        Vector3(hitX * f.menuAmount, cy, depth),
        Quaternion.axisAngle(Vector3(1, 0, 0), -math.pi / 2),
        Vector3(size, 1, size),
      );
    }

    final boss = f.boss;
    _backdropMaterial?.parameters
      ?..setVec4('tiling', Vector4(102.4, 260.0, 0.0, f.drift))
      ..setVec4('tint', Vector4(1.0, 1.0, 1.0, 1.0))
      ..setVec4('state', Vector4(f.time, boss, f.boost, 0));
    for (final m in _nebulaMaterials) {
      m.parameters.setVec4('state', Vector4(f.time, boss, f.boost, f.drift));
    }

    // Parallax star field.
    _stars.update(this, f);

    // Shot lights follow the camera target.
    for (int i = 0; i < _shotLightNodes.length; i++) {
      final base = _shotLightOffsets[i];
      _shotLightNodes[i].position = Vector3(
        base.x,
        camera.target.y + base.y,
        base.z,
      );
    }
  }

  // --- Visuals ----------------------------------------------------------------

  _Visual _createVisual(GameObject obj) {
    final v = _Visual(obj);
    String? model;
    switch (obj.kind) {
      case ObjectKind.ship:
        model = 'ship';
      case ObjectKind.asteroidBig:
        model = 'asteroid_big_${obj.variant}';
      case ObjectKind.asteroidSmall:
        model = 'asteroid_small_${obj.variant}';
      case ObjectKind.asteroidPowerUp:
        model = 'crystal_${obj.variant}';
      case ObjectKind.enemyScout:
        model = 'enemy_scout_${obj.variant}';
      case ObjectKind.enemyDestroyer:
        model = 'enemy_destroyer_${obj.variant}';
      case ObjectKind.enemyBoss:
        model = 'enemy_boss_${obj.variant}';
      default:
        break;
    }
    if (model != null) {
      final instance = models.acquire(model);
      v.model = instance;
      scene.add(instance.root);
      if (obj.kind == ObjectKind.asteroidPowerUp) {
        v.anchor = _findNode(instance.model, 'powerup_anchor');
        v.sparkles = [
          for (int i = 0; i < 4; i++) ?_findNode(instance.model, 'sparkle_$i'),
        ];
      }
    }
    if (obj.kind == ObjectKind.asteroidBig ||
        obj.kind == ObjectKind.asteroidSmall) {
      v.spinAxis = Vector3(
        _rnd.nextDouble() * 2 - 1,
        _rnd.nextDouble() * 2 - 1,
        _rnd.nextDouble() * 2 - 1,
      ).normalized();
      v.tumble = Quaternion.axisAngle(
        Vector3(
          _rnd.nextDouble(),
          _rnd.nextDouble(),
          _rnd.nextDouble(),
        ).normalized(),
        _rnd.nextDouble() * math.pi * 2,
      );
    }
    if (obj.kind == ObjectKind.powerUp) {
      final node = _gemPool.isNotEmpty
          ? _gemPool.removeLast()
          : Node(mesh: Mesh(_gemGeometry, _gemMaterial));
      scene.add(node);
      v.anchor = node;
    }
    if (obj.kind == ObjectKind.coin) {
      final node = _coinPool.isNotEmpty
          ? _coinPool.removeLast()
          : Node(mesh: Mesh(_coinGeometry, _coinMaterial));
      scene.add(node);
      v.second = null;
      v.anchor = node;
    }
    return v;
  }

  Node? _findNode(Node root, String name) {
    if (root.name == name) return root;
    for (final child in root.children) {
      final found = _findNode(child, name);
      if (found != null) return found;
    }
    return null;
  }

  void _releaseVisual(_Visual v) {
    final m = v.model;
    if (m != null) models.release(m);
    v.model = null;
    if (v.object.kind == ObjectKind.coin && v.anchor != null) {
      v.anchor!.detach();
      _coinPool.add(v.anchor!);
      v.anchor = null;
    }
    if (v.object.kind == ObjectKind.powerUp && v.anchor != null) {
      v.anchor!.detach();
      _gemPool.add(v.anchor!);
      v.anchor = null;
    }
  }

  static double _lerpAngle(double a, double b, double t) {
    double d = b - a;
    while (d > 180) {
      d -= 360;
    }
    while (d < -180) {
      d += 360;
    }
    return a + d * t;
  }

  void _updateVisual(_Visual v, FrameInfo f) {
    final o = v.object;
    final a = f.alpha;
    final gx = o.prevX + (o.x - o.prevX) * a;
    final gy = o.prevY + (o.y - o.prevY) * a;
    final x = gx * kWorld;
    final y = -gy * kWorld + originY;
    final rotDeg = _lerpAngle(o.prevRotation, o.rotation, a);
    final time = f.time;
    final dt = f.dt;
    final step = f.world.stepCount;

    switch (o) {
      case Ship ship:
        _updateShip(v, ship, x, y, f);
      case Laser laser:
        _drawLaser(laser, x, y);
      case EnemyLaser laser:
        _drawEnemyLaser(laser, x, y, time);
      case AsteroidPowerUp crystal:
        _updateCrystal(v, crystal, x, y, time, step);
      case Asteroid asteroid:
        final m = v.model!;
        final angle =
            2 * math.pi / asteroid.spinPeriod * asteroid.spinDirection;
        v.tumble = Quaternion.axisAngle(v.spinAxis, angle * dt) * v.tumble;
        m.root.position = Vector3(x, y, 0);
        m.root.rotation = v.tumble;
        m.root.scale = Vector3.all(0.3);
        _applyDamageTint(m, o, step, 1.0, 3 / 255, 86 / 255);
      case EnemyScout _:
      case EnemyDestroyer _:
        _updateEnemy(v, x, y, rotDeg, 0.32, f);
        _applyDamageTint(v.model!, o, step, 1.0, 3 / 255, 86 / 255);
      case EnemyBoss boss:
        _updateEnemy(v, x, y, rotDeg, 0.32, f);
        // The original flashes the boss red for 0.3s on every hit.
        final since = (step - boss.lastDamageStep) / GameWorld.stepsPerSecond;
        final flash = boss.lastDamageStep < 0
            ? 0.0
            : (1.0 - since / 0.3).clamp(0.0, 1.0) * (180 / 255);
        v.model!.setTint(1.0 * 3, 3 / 255, 86 / 255 * 3, flash);
      case Coin coin:
        _updateCoin(v, coin, x, y, time, step);
      case PowerUp powerUp:
        _updatePowerUp(v, powerUp, x, y, time, step);
      default:
        break;
    }
  }

  void _applyDamageTint(
    ModelInstance m,
    GameObject o,
    int step,
    double r,
    double g,
    double b,
  ) {
    if (o.lastDamageStep < 0) return;
    // Persistent tint grows with damage like colorForDamage, plus a quick
    // bright flash on each hit.
    final amount = ((200.0 * o.damage) ~/ o.maxDamage).clamp(0, 200) / 255.0;
    final since = (step - o.lastDamageStep) / GameWorld.stepsPerSecond;
    final flash = (1.0 - since / 0.12).clamp(0.0, 1.0);
    m.setTint(
      r * (1.2 + flash * 2),
      g + flash * 1.5,
      b * (1.2 + flash * 2) + flash,
      amount * 0.9 + flash * 0.8,
    );
  }

  void _updateShip(_Visual v, Ship ship, double x, double y, FrameInfo f) {
    final m = v.model!;
    final world = f.world;
    m.root.visible = ship.visible;
    if (!ship.visible) return;

    // Bank into lateral movement and pitch with vertical movement.
    final vx = (ship.x - ship.prevX) * GameWorld.stepsPerSecond;
    final targetBank = (-vx / 260.0).clamp(-1.0, 1.0) * 0.75;
    v.bank += (targetBank - v.bank) * (1 - math.exp(-f.dt * 10));

    final hover = f.menuAmount > 0
        ? math.sin(f.time * 1.6) * 0.05 * f.menuAmount
        : 0.0;
    final sway = f.menuAmount * math.sin(f.time * 0.9) * 0.12;

    m.root.position = Vector3(x, y + hover, 0);
    m.root.rotation = Quaternion.axisAngle(Vector3(0, 0, 1), math.pi / 2);
    m.root.scale = Vector3.all(0.3 * math.max(0.001, f.shipScale));
    m.pivot.rotation = Quaternion.axisAngle(Vector3(1, 0, 0), v.bank + sway);

    // Engine flame, which also lights the ship and whatever flies nearby.
    final boost = f.boost;
    _shipFlame(x, y + hover, boost, f.time);
    lights.request(
      x,
      y + hover - 0.45,
      -0.25,
      0.35,
      0.6,
      1.0,
      1.6 * (1 + boost),
      1.3 + boost * 0.5,
    );
    if (world.playerState.shieldActive) {
      lights.request(x, y, -0.6, 0.3, 0.8, 1.0, 1.6, 1.6);
    }

    // Shield.
    final ps = world.playerState;
    if (ps.shieldActive) {
      final blinkOff = ps.shieldDeactivating && (world.stepCount ~/ 3).isOdd;
      if (!blinkOff) {
        final rot = -(f.time * 2 * math.pi);
        // In front of the ship, on the camera ray through its center, so the
        // bubble stays centered on screen with the off-axis camera.
        final front = _inFront(x, y, 0.15);
        _shieldBatch.add(
          front.x,
          front.y,
          front.z,
          0.66,
          0.66,
          rot,
          1.4,
          1.5,
          1.9,
          1,
        );
        final pulse = 0.8 + 0.2 * math.sin(f.time * 6);
        _hexShieldBatch.add(
          front.x,
          front.y,
          front.z - 0.01,
          0.72,
          0.72,
          f.time * 0.4,
          0.3 * pulse,
          0.9 * pulse,
          1.6 * pulse,
          1,
        );
      }
    }
  }

  /// The player's engine flames: one flickering blue flame out of each
  /// exhaust, wide at the nozzle and tapering to a soft tip, with a hot core.
  /// Shooting stars rushing past the ship on the start screen.
  void _updateMenuStreaks(FrameInfo f) {
    final amount = f.menuAmount;
    if (amount > 0.3 && _rnd.nextDouble() < f.dt * 12 * amount) {
      final ship = f.world.ship;
      final sx = ship.x * kWorld;
      final sy = -ship.y * kWorld + originY;
      final speed = 11.0 + _rnd.nextDouble() * 8.0;
      final b = 1.4 + _rnd.nextDouble() * 2.0;
      _menuStreaks.spawn(
        x: sx + (_rnd.nextDouble() * 2 - 1) * 2.6,
        y: sy + 7.0 + _rnd.nextDouble() * 5.0,
        z: -1.8 + _rnd.nextDouble() * 5.5,
        vy: -speed,
        life: 0.9 + _rnd.nextDouble() * 0.5,
        size: 0.04 + _rnd.nextDouble() * 0.03,
        aspect: 8,
        color: ColorRamp(
          [0.0, 0.0, 0.0, 0.0],
          [b * 0.75, b * 0.9, b * 1.3, 1],
          const [0, 0, 0, 0],
          mid: 0.35,
        ),
      );
    }
    _menuStreaks.update(f.dt);
    _menuStreaks.write();
  }

  /// The point [amount] world units in front of (x, y, 0), toward the
  /// camera along the ray through it: a billboard there lands exactly over
  /// the object on screen.
  Vector3 _inFront(double x, double y, double amount) {
    final eye = camera.eye;
    final dx = x - eye.x, dy = y - eye.y, dz = -eye.z;
    final len = math.sqrt(dx * dx + dy * dy + dz * dz);
    final k = amount / len;
    return Vector3(x - dx * k, y - dy * k, -dz * k);
  }

  void _shipFlame(double x, double y, double boost, double time) {
    const nozzleX = 0.043;
    const nozzleY = 0.165;
    for (int i = 0; i < 2; i++) {
      final side = i == 0 ? -1.0 : 1.0;
      final phase = i * 1.7;
      final flicker =
          0.86 +
          0.1 * math.sin(time * 41.0 + phase) * math.sin(time * 23.0 + phase) +
          0.04 * math.sin(time * 97.0 + phase);
      final length = 0.3 * (1.0 + boost * 1.0) * flicker;
      final nx = x + side * nozzleX;
      final ny = y - nozzleY;
      // A wide, faint glow around the flame softens its silhouette.
      batches.glow.add(
        nx,
        ny - length * 0.38,
        0.03,
        0.16,
        length * 0.95,
        0,
        0.12 * flicker,
        0.28 * flicker,
        0.8 * flicker,
        1,
      );
      // Outer flame; the texture's wide base sits at the nozzle.
      _flameBatch.add(
        nx,
        ny - length * 0.5,
        0.02,
        0.095,
        length,
        0,
        0.3 * flicker,
        0.72 * flicker,
        2.3 * flicker,
        1,
      );
      // Inner core.
      _flameBatch.add(
        nx,
        ny - length * 0.26,
        0.01,
        0.05,
        length * 0.52,
        0,
        1.2,
        1.8,
        2.8,
        1,
      );
      // Nozzle glow.
      batches.glow.add(nx, ny + 0.005, 0.0, 0.085, 0.06, 0, 1.2, 1.7, 3.0, 1);
    }
  }

  void _drawLaser(Laser laser, double x, double y) {
    final level = laser.level;
    final numLasers = level % 3 + 1;
    final c = laserColors[(level ~/ 3) % laserColors.length];
    // Sprite rotation = r + 90 in the original (the teardrop points up).
    final rot = -laser.rotation * math.pi / 180.0;
    final cosR = math.cos(rot), sinR = math.sin(rot);
    const offsets = [
      [
        [0.0, 0.0],
      ],
      [
        [-3.0, 0.0],
        [3.0, 0.0],
      ],
      [
        [-4.0, 0.0],
        [4.0, 0.0],
        [0.0, -2.0],
      ],
    ];
    for (final off in offsets[numLasers - 1]) {
      // Local sprite offset (y down) rotated into world space (y up).
      final lx = off[0] * kWorld;
      final ly = -off[1] * kWorld;
      final wx = x + lx * cosR - ly * sinR;
      final wy = y + lx * sinR + ly * cosR;
      batches.particle.add(
        wx,
        wy,
        -0.02,
        0.26,
        0.34,
        rot,
        c[0] * 1.5,
        c[1] * 1.5,
        c[2] * 1.5,
        1,
      );
    }
    lights.request(x, y, -0.2, c[0], c[1], c[2], 1.4, 0.8);
    batches.glow.add(
      x,
      y,
      0.0,
      0.16,
      0.42,
      rot,
      c[0] * c[0] * 0.5,
      c[1] * c[1] * 0.5,
      c[2] * c[2] * 0.5,
      1,
    );
  }

  void _drawEnemyLaser(EnemyLaser laser, double x, double y, double time) {
    final rot = -(laser.direction + 90) * math.pi / 180.0;
    final pulse = 1.0 + 0.2 * math.sin(time * 30 + laser.id);
    lights.request(x, y, -0.2, 1.0, 0.65, 0.25, 1.8 * pulse, 0.9);
    batches.particle.add(
      x,
      y,
      -0.02,
      0.32,
      0.32,
      rot,
      3.2 * pulse,
      2.6 * pulse,
      1.2 * pulse,
      1,
    );
    batches.glow.add(
      x,
      y,
      0.0,
      0.4 * pulse,
      0.4 * pulse,
      0,
      1.1,
      0.55,
      0.15,
      1,
    );
  }

  void _updateEnemy(
    _Visual v,
    double x,
    double y,
    double rotDeg,
    double scale,
    FrameInfo f,
  ) {
    final m = v.model!;
    final o = v.object;
    // Bank into turns.
    double turn = o.rotation - o.prevRotation;
    while (turn > 180) {
      turn -= 360;
    }
    while (turn < -180) {
      turn += 360;
    }
    final targetBank = (turn * 0.12).clamp(-0.7, 0.7);
    v.bank += (targetBank - v.bank) * (1 - math.exp(-f.dt * 6));
    final bob = math.sin(f.time * 2.0 + v.phase) * 0.03;

    m.root.position = Vector3(x, y, bob);
    m.root.rotation = Quaternion.axisAngle(
      Vector3(0, 0, 1),
      -rotDeg * math.pi / 180,
    );
    m.root.scale = Vector3.all(scale);
    m.pivot.rotation = Quaternion.axisAngle(Vector3(1, 0, 0), v.bank);
  }

  void _updateCrystal(
    _Visual v,
    AsteroidPowerUp crystal,
    double x,
    double y,
    double time,
    int step,
  ) {
    final m = v.model!;
    final t = time + v.phase;
    lights.request(
      x,
      y,
      -0.9,
      0.4,
      0.8,
      1.0,
      1.6 + 0.4 * math.sin(t * 2),
      1.8,
    );
    m.root.position = Vector3(x, y, 0);
    m.root.rotation =
        Quaternion.axisAngle(Vector3(1, 0, 0), math.sin(t * 0.6) * 0.3) *
        Quaternion.axisAngle(Vector3(0, 1, 0), math.sin(t * 0.8) * 0.5);
    m.root.scale = Vector3.all(0.3);
    _applyDamageTint(m, crystal, step, 200 / 255, 200 / 255, 1.0);

    // Halo, core glow and the power-up icon inside the heart.
    final halo = 0.25 + 0.07 * math.sin(t * 2);
    batches.glow.add(
      x,
      y,
      0.05,
      0.3 * 2.0 * 1.4,
      0.3 * 2.0 * 1.4,
      0,
      0.37 * halo * 3,
      0.85 * halo * 3,
      1.0 * halo * 3,
      1,
    );
    Vector3 anchor = Vector3(x, y, -0.02);
    final anchorNode = v.anchor;
    if (anchorNode != null) {
      anchor = anchorNode.globalTransform.getTranslation();
    }
    batches.glow.add(
      anchor.x,
      anchor.y,
      anchor.z + 0.01,
      0.35,
      0.35,
      0,
      0.45,
      0.85,
      1.0,
      1,
    );
    final iconSize = 0.2 * (1 + 0.04 * math.sin(t * 3));
    _iconBatches[crystal.powerUpType.index].add(
      anchor.x,
      anchor.y,
      anchor.z - 0.03,
      iconSize * 2.56 / 0.66,
      iconSize * 2.56 / 0.66,
      0,
      1.3,
      1.3,
      1.3,
      1,
    );

    // Sparkles on the prism tips: short, sharp twinkles.
    final sparkles = v.sparkles;
    if (sparkles != null) {
      for (int i = 0; i < sparkles.length; i++) {
        final p = sparkles[i].globalTransform.getTranslation();
        final k = math
            .pow(
              math.max(0.0, math.sin(t * (0.7 + i * 0.23) + i * 2.1)),
              12,
            )
            .toDouble();
        if (k < 0.01) continue;
        final s = 0.6 * 0.2 * k;
        batches.twinkle.add(
          p.x,
          p.y,
          p.z - 0.05,
          s,
          s,
          t * 0.5 + i,
          2.5 * k,
          3.0 * k,
          3.2 * k,
          1,
        );
      }
    }
  }

  void _updateCoin(
    _Visual v,
    Coin coin,
    double x,
    double y,
    double time,
    int step,
  ) {
    final node = v.anchor!;
    final age = (step - coin.spawnStep) / GameWorld.stepsPerSecond;
    final fade = (age / 0.6).clamp(0.0, 1.0);
    lights.request(x, y, -0.25, 0.3, 1.0, 0.6, 0.8 * fade, 0.7);
    final spin = age * 2 * math.pi;
    node.position = Vector3(x, y, -0.05);
    // Spin in the screen plane once per second like the original coin,
    // tilted and turning on its long axis so the facets flash.
    node.rotation =
        Quaternion.axisAngle(Vector3(0, 0, 1), -spin) *
        Quaternion.axisAngle(Vector3(1, 0, 0), 0.6) *
        Quaternion.axisAngle(Vector3(0, 1, 0), spin * 1.5);
    node.scale = Vector3.all(0.23 * (0.4 + 0.6 * fade));
    final pulse = 0.8 + 0.2 * math.sin(time * 6 + coin.id);
    batches.glow.add(
      x,
      y,
      0.05,
      0.34,
      0.34,
      0,
      0.05 * fade * pulse,
      0.3 * fade * pulse,
      0.16 * fade * pulse,
      1,
    );
  }

  void _updatePowerUp(
    _Visual v,
    PowerUp p,
    double x,
    double y,
    double time,
    int step,
  ) {
    final age = (step - p.spawnStep) / GameWorld.stepsPerSecond;
    // Fades in over 0.6s like the original, with a little pop.
    final fade = (age / 0.6).clamp(0.0, 1.0);
    final pop = Curves.easeOutBack.transform(fade);
    final t = time + v.phase;
    const size = 0.38;
    final node = v.anchor!;
    node.position = Vector3(x, y, -0.02);
    // Turns slowly in the screen plane and rocks so the facets catch the
    // lights.
    node.rotation =
        Quaternion.axisAngle(Vector3(0, 0, 1), -age * 0.9) *
        Quaternion.axisAngle(Vector3(1, 0, 0), math.sin(t * 1.7) * 0.35) *
        Quaternion.axisAngle(Vector3(0, 1, 0), math.cos(t * 1.3) * 0.35);
    node.scale = Vector3.all(size * math.max(0.01, pop));

    final pulse = 1.0 + 0.08 * math.sin(time * 4);
    lights.request(x, y, -1.0, 0.4, 0.8, 1.0, 1.6 * fade, 1.8);
    // Halo behind the gem.
    batches.glow.add(
      x,
      y,
      0.1,
      0.75 * pulse,
      0.75 * pulse,
      0,
      0.1 * fade,
      0.24 * fade,
      0.55 * fade,
      1,
    );
    // A soft ring pings outward now and then: this one is to be collected.
    final ping = (t * 0.8) % 1.0;
    final pingFade = (1 - ping) * (1 - ping) * fade;
    batches.shockwave.add(
      x,
      y,
      0.05,
      0.4 + 0.45 * ping,
      0.4 + 0.45 * ping,
      0,
      0.5 * pingFade,
      0.9 * pingFade,
      1.2 * pingFade,
      1,
    );
    // The icon floats just above the gem's glass table.
    final iconPos = _inFront(x, y, 0.12);
    _iconBatches[p.type.index].add(
      iconPos.x,
      iconPos.y,
      iconPos.z,
      0.72 * pop,
      0.72 * pop,
      0,
      1.25,
      1.25,
      1.25,
      fade,
    );
    // An occasional glint drifting off the gem.
    if (_rnd.nextDouble() < 0.05) {
      final a = _rnd.nextDouble() * math.pi * 2;
      effects.embers.spawn(
        x: x + math.cos(a) * 0.2,
        y: y + math.sin(a) * 0.2,
        z: -0.1,
        vx: math.cos(a) * 0.15,
        vy: math.sin(a) * 0.15,
        life: 0.6,
        size: 0.08,
        endSize: 0.0,
        color: const ColorRamp.fade([1.0, 2.0, 2.8, 1]),
      );
    }
  }

  /// The icon batch for a power-up type (used by the HUD preview).
  SpriteBatch iconBatch(PowerUpType type) => _iconBatches[type.index];

  // Accessors used by the star field.
  SpriteBatch get starBatch0 => _starBatch0;
  SpriteBatch get starBatch1 => _starBatch1;
  SpriteBatch get dustBatch => _dustBatch;
  SpriteBatch get streakBatch => _streakBatch;
}

/// Parallax star field: 3D points at depths matching the original's star
/// speeds (0.1x to 0.4x of the scroll), wrapped around the camera.
class _Stars {
  /// World length of a star streak at full speed boost.
  static const double streakLength = 1.1;

  static const int count = 220;
  static const int dustCount = 40;

  final List<double> _x = [];
  final List<double> _y = [];
  final List<double> _z = [];
  final List<double> _bright = [];
  final List<int> _tex = [];
  final List<double> _twinkle = [];
  final List<double> _size = [];

  final List<double> _dx = [];
  final List<double> _dy = [];
  final List<double> _dz = [];

  bool _init = false;

  void _setup() {
    final d = GameRenderer.cameraDistance;
    for (int i = 0; i < count; i++) {
      // Parallax factor p in 0.1..0.45 -> depth behind the playfield.
      final p = 0.1 + _rnd.nextDouble() * 0.35;
      _z.add(d / p - d);
      _x.add((_rnd.nextDouble() * 2 - 1) * 40);
      _y.add((_rnd.nextDouble() * 2 - 1) * 40);
      _bright.add(0.5 + 0.5 * _rnd.nextDouble());
      _tex.add(_rnd.nextInt(2));
      _twinkle.add(_rnd.nextDouble() * 10);
      // Mostly small stars with the odd bright one.
      final r = _rnd.nextDouble();
      _size.add(0.12 + r * r * r * 0.4);
    }
    for (int i = 0; i < dustCount; i++) {
      _dx.add((_rnd.nextDouble() * 2 - 1) * 3);
      _dy.add((_rnd.nextDouble() * 2 - 1) * 5);
      _dz.add(-0.8 - _rnd.nextDouble() * 3.5);
    }
    _init = true;
  }

  void update(GameRenderer r, FrameInfo f) {
    if (!_init) _setup();
    final cam = r.camera;
    final h = math.tan(cam.lens.fovRadiansY / 2);
    final eyeX = cam.eye.x;
    final eyeY = cam.eye.y;
    final lensShift = cam.lens.shiftY;
    final drift = f.drift;
    final aspect = 320 / (f.world.gameHeight);
    for (int i = 0; i < count; i++) {
      final z = _z[i];
      final dist = z - cam.eye.z;
      final halfH = dist * h * (1.25 + f.menuAmount * 1.5) + 0.5;
      final halfW = halfH * math.max(aspect, 0.8) + 0.5;
      final cy = eyeY - lensShift * h * dist;
      // Star positions are relative; the drift moves them in the menu.
      double y = _y[i] - drift;
      double x = _x[i];
      y = cy + _wrap(y - cy, halfH);
      x = eyeX + _wrap(x - eyeX, halfW);
      _y[i] = y + drift;
      _x[i] = x;
      // Constant world size: nearer stars look bigger and move faster, like
      // the original where star scale and speed were the same number.
      final size = _size[i];
      final tw = 0.7 + 0.3 * math.sin(f.time * 2.3 + _twinkle[i]);
      final b = _bright[i] * tw;
      // At high speed stars smear into motion-blur streaks. The camera moves
      // the same world distance past every star, so the streak has the same
      // world length at any depth; its light is spread over that length.
      final blur = f.boost;
      if (blur > 0.01) {
        final length = size * 0.6 + streakLength * blur;
        final spread = (size / length).clamp(0.12, 1.0);
        final sb = b * (0.6 + 0.9 * spread) * blur;
        r.streakBatch.add(
          x,
          y,
          z,
          size * 0.32,
          length,
          0,
          sb * 0.85,
          sb * 0.95,
          sb * 1.25,
          1,
        );
      }
      final still = 1.0 - blur;
      if (still <= 0.01) continue;
      // Distant stars are drawn as soft dots: a pre-blurred stand-in for
      // depth of field, which the gameplay camera does not use.
      final far = (z - 25.0) / 30.0;
      if (far > 0) {
        final soft = far.clamp(0.0, 1.0);
        final sb = b * (0.55 - 0.2 * soft) * still;
        r.dustBatch.add(
          x,
          y,
          z,
          size * (0.9 + 0.5 * soft),
          size * (0.9 + 0.5 * soft),
          0,
          sb * 0.85,
          sb * 0.95,
          sb * 1.2,
          1,
        );
        continue;
      }
      final sb = b * still;
      final batch = _tex[i] == 0 ? r.starBatch0 : r.starBatch1;
      batch.add(x, y, z, size, size, 0, sb * 0.9, sb * 0.95, sb * 1.1, 1);
    }

    // Foreground dust between the camera and the playfield.
    for (int i = 0; i < dustCount; i++) {
      final z = _dz[i];
      final dist = z - cam.eye.z;
      final halfH = dist * h * 1.2 + 0.3;
      final halfW = halfH * 0.8 + 0.3;
      final cy = eyeY - lensShift * h * dist;
      double y = _dy[i] - drift * 1.6;
      y = cy + _wrap(y - cy, halfH);
      final x = eyeX + _wrap(_dx[i] - eyeX, halfW);
      _dy[i] = y + drift * 1.6;
      _dx[i] = x;
      final blur = f.boost;
      final length = 0.05 + streakLength * 0.6 * blur;
      final a = (0.05 + 0.12 * blur) * (0.05 / length).clamp(0.3, 1.0);
      final batch = blur > 0.01 ? r.streakBatch : r.dustBatch;
      batch.add(
        x,
        y,
        z,
        blur > 0.01 ? 0.03 : 0.05,
        length,
        0,
        a,
        a * 1.1,
        a * 1.4,
        1,
      );
    }
  }

  static double _wrap(double v, double half) {
    final span = half * 2;
    v = (v + half) % span;
    if (v < 0) v += span;
    return v - half;
  }
}
