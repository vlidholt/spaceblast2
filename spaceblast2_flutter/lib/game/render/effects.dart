import 'dart:math' as math;

import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';

import '../sim/game_objects.dart';
import 'light_pool.dart';
import 'sprite_batch.dart';

final math.Random _rnd = math.Random();
double _r() => _rnd.nextDouble();
double _rs() => _rnd.nextDouble() * 2.0 - 1.0;

/// World units per original game unit.
const double kWorld = 0.01;

/// All the sprite batches effects and objects draw into.
class EffectBatches {
  EffectBatches({
    required this.particle,
    required this.fire,
    required this.fireball,
    required this.glow,
    required this.spark,
    required this.smoke,
    required this.ring,
    required this.shockwave,
    required this.flare,
    required this.star,
    required this.twinkle,
  });

  /// explosion_particle.png, the original's laser and debris sprite.
  final SpriteBatch particle;

  /// fire_particle.png, the original's fire sprite.
  final SpriteBatch fire;

  /// Billowing additive puffs for fireballs.
  final SpriteBatch fireball;
  final SpriteBatch glow;
  final SpriteBatch spark;

  /// Alpha-blended puffs for smoke and dust.
  final SpriteBatch smoke;
  final SpriteBatch ring;
  final SpriteBatch shockwave;
  final SpriteBatch flare;
  final SpriteBatch star;
  final SpriteBatch twinkle;

  List<SpriteBatch> get all => [
    smoke,
    glow,
    fireball,
    fire,
    ring,
    shockwave,
    flare,
    particle,
    spark,
    star,
    twinkle,
  ];
}

class _Flare {
  _Flare(this.x, this.y, this.angle, this.multiplier, this.scale);
  final double x, y, angle, multiplier, scale;
  double age = 0.0;
}

class _MiniStar {
  _MiniStar(this.x, this.y, this.rotStart, this.rotEnd);
  final double x, y, rotStart, rotEnd;
  double age = 0.0;
}

enum _ChunkKind { rock, metal, crystal }

class _Chunk {
  _Chunk(
    this.kind,
    this.position,
    this.velocity,
    this.spinAxis,
    this.spin,
    this.size,
    this.life,
    this.burning,
  );
  final _ChunkKind kind;
  final Vector3 position;
  final Vector3 velocity;
  final Vector3 spinAxis;
  final double spin;
  final double size;
  final double life;
  final bool burning;
  double age = 0.0;
  double trailTimer = 0.0;
  Quaternion rotation = Quaternion.identity();
}

/// A light that flashes and then burns down (explosion flashes, fires).
class _FlashLight {
  _FlashLight({
    required this.x,
    required this.y,
    required this.z,
    required this.color,
    required this.peak,
    required this.life,
    required this.range,
    this.attack = 0.04,
    this.flicker = 0.0,
    this.sustain = 0.0,
  });
  final double x, y, z;
  final List<double> color;
  final double peak, life, range, attack, flicker;

  /// Level (fraction of [peak]) the light settles to after the flash and
  /// then burns down from, for fires.
  final double sustain;
  double age = 0.0;
}

class _Scheduled {
  _Scheduled(this.delay, this.action);
  double delay;
  final void Function() action;
}

/// Spawns and animates explosions and other one-shot effects.
class EffectsSystem {
  EffectsSystem(this.scene, this.batches, this.lights) {
    fire = ParticleLayer(batches.fire, capacity: 900);
    fireballs = ParticleLayer(batches.fireball, capacity: 900);
    glow = ParticleLayer(batches.glow, capacity: 700);
    debris = ParticleLayer(batches.particle, capacity: 700);
    sparks = ParticleLayer(batches.spark, capacity: 1200);
    smoke = ParticleLayer(batches.smoke, capacity: 700);
    rings = ParticleLayer(batches.ring, capacity: 60);
    shockwaves = ParticleLayer(batches.shockwave, capacity: 80);
    trails = ParticleLayer(batches.glow, capacity: 900);
    embers = ParticleLayer(batches.twinkle, capacity: 500);

    // Flying debris is drawn as three instanced meshes (one draw each)
    // with low-poly shapes, no matter how many chunks are in flight.
    InstancedMesh chunkMesh(Geometry geometry, Material material) {
      final mesh = InstancedMesh(geometry: geometry, material: material);
      scene.add(
        Node()
          ..addComponent(InstancedMeshComponent(mesh))
          ..frustumCulled = false,
      );
      return mesh;
    }

    _chunkMeshes = {
      _ChunkKind.rock: chunkMesh(
        IcosphereGeometry(radius: 0.5, subdivisions: 0),
        PhysicallyBasedMaterial()
          ..baseColorFactor = Vector4(0.3, 0.21, 0.15, 1)
          ..metallicFactor = 0.0
          ..roughnessFactor = 0.9
          ..emissiveFactor = Vector4(0.18, 0.045, 0.01, 1),
      ),
      _ChunkKind.metal: chunkMesh(
        CuboidGeometry(Vector3(1.0, 0.35, 0.6)),
        PhysicallyBasedMaterial()
          ..baseColorFactor = Vector4(0.25, 0.24, 0.28, 1)
          ..metallicFactor = 0.8
          ..roughnessFactor = 0.35
          ..emissiveFactor = Vector4(1.6, 0.55, 0.2, 1),
      ),
      _ChunkKind.crystal: chunkMesh(
        IcosphereGeometry(radius: 0.5, subdivisions: 0),
        PhysicallyBasedMaterial()
          ..baseColorFactor = Vector4(0.35, 0.75, 1.0, 1)
          ..metallicFactor = 0.2
          ..roughnessFactor = 0.1
          ..emissiveFactor = Vector4(0.3, 0.8, 1.6, 1),
      ),
    };
  }

  final Scene scene;
  final EffectBatches batches;
  final LightPool lights;

  late final ParticleLayer fire;
  late final ParticleLayer fireballs;
  late final ParticleLayer glow;
  late final ParticleLayer debris;
  late final ParticleLayer sparks;
  late final ParticleLayer smoke;
  late final ParticleLayer rings;
  late final ParticleLayer shockwaves;
  late final ParticleLayer trails;
  late final ParticleLayer embers;

  List<ParticleLayer> get _layers => [
    fire,
    fireballs,
    glow,
    debris,
    sparks,
    smoke,
    rings,
    shockwaves,
    trails,
    embers,
  ];

  final List<_Flare> _flares = [];
  final List<_MiniStar> _miniStars = [];
  final List<_Chunk> _chunks = [];
  final List<_FlashLight> _flashLights = [];
  final List<_Scheduled> _scheduled = [];
  late final Map<_ChunkKind, InstancedMesh> _chunkMeshes;

  /// World Y of the level origin (see GameRenderer.originY).
  double originY = 0.0;

  /// Effect density, 0.4..1. Lowered by the controller when the frame rate
  /// drops, so heavy scenes stay smooth.
  double quality = 1.0;

  int _n(num count) => math.max(1, (count * quality).round());

  /// Camera shake trauma, 0..1. Decays over time.
  double trauma = 0.0;

  /// A brief bloom boost after big blasts, 0..1. Decays over time.
  double flash = 0.0;

  double _time = 0.0;

  void clear() {
    for (final layer in _layers) {
      layer.clear();
    }
    _flares.clear();
    _miniStars.clear();
    _chunks.clear();
    for (final mesh in _chunkMeshes.values) {
      mesh.clearInstances();
    }
    _flashLights.clear();
    _scheduled.clear();
    trauma = 0;
    flash = 0;
  }

  void _light(
    double x,
    double y,
    double z,
    List<double> color,
    double peak,
    double life,
    double range, {
    double attack = 0.04,
    double flicker = 0.0,
    double sustain = 0.0,
  }) {
    _flashLights.add(
      _FlashLight(
        x: x,
        y: y,
        z: z,
        color: color,
        peak: peak,
        life: life,
        range: range,
        attack: attack,
        flicker: flicker,
        sustain: sustain,
      ),
    );
  }

  /// The original ExplosionBig (debris, fire, ring, five flares), rebuilt as
  /// a layered 3D blast: a white-hot flash, a billowing fireball, the
  /// original fire and debris, sparks, embers, burning chunks, a shockwave,
  /// lingering smoke, and lights that flash and then burn down. Big ships
  /// break apart in a chain of secondary blasts.
  void bigExplosion(
    double gx,
    double gy,
    double scale, {
    required ObjectKind source,
    required int variant,
  }) {
    final x = gx * kWorld;
    final y = -gy * kWorld + originY;
    final s = scale;
    final isRock =
        source == ObjectKind.asteroidBig || source == ObjectKind.asteroidSmall;
    final isCrystal = source == ObjectKind.asteroidPowerUp;
    final isBoss = source == ObjectKind.enemyBoss;
    final isPlayer = source == ObjectKind.ship;
    final isShip =
        source == ObjectKind.enemyDestroyer ||
        source == ObjectKind.enemyScout ||
        isBoss ||
        isPlayer;
    final isBig = s > 1.2 || isBoss;

    _blast(x, y, s, isRock: isRock, isCrystal: isCrystal, isBig: isBig);

    // Tumbling, burning chunks.
    final chunkCount = _n(isBig ? 12 : (isRock ? 7 : 6));
    for (int i = 0; i < chunkCount; i++) {
      _spawnChunk(x, y, s, isRock || isCrystal ? variant : -1, source);
    }

    // Big ships come apart in a chain of secondary blasts.
    final secondaries = isBoss
        ? 9
        : isPlayer
        ? 5
        : source == ObjectKind.enemyDestroyer
        ? 2
        : 0;
    for (int i = 0; i < secondaries; i++) {
      final delay = 0.12 + i * (isBoss ? 0.13 : 0.11) + _r() * 0.06;
      final radius = (isBoss ? 0.55 : 0.3) * s;
      final a = _r() * math.pi * 2;
      final d = radius * (0.35 + 0.65 * _r());
      final sx = x + math.cos(a) * d;
      final sy = y + math.sin(a) * d;
      final ss = s * (0.45 + 0.25 * _r());
      _scheduled.add(
        _Scheduled(delay, () {
          _blast(
            sx,
            sy,
            ss,
            isRock: false,
            isCrystal: false,
            isBig: false,
            withLight: false,
          );
          trauma = math.min(1.0, trauma + 0.15);
        }),
      );
    }

    trauma = math.min(
      1.0,
      trauma +
          (isPlayer
              ? 0.9
              : isBig
              ? 0.75
              : isShip
              ? 0.3
              : 0.2),
    );
    flash = math.min(1.0, flash + (isBig ? 1.0 : 0.45));
  }

  void _blast(
    double x,
    double y,
    double s, {
    required bool isRock,
    required bool isCrystal,
    required bool isBig,
    bool withLight = true,
  }) {
    final many = isBig ? 2 : 1;

    // White-hot core flash.
    glow.spawn(
      x: x,
      y: y,
      z: -0.12,
      life: 0.22,
      size: 0.55 * s,
      endSize: 1.1 * s,
      color: ColorRamp(
        isCrystal ? [3.0, 5.0, 7.0, 1] : [7.0, 5.6, 3.4, 1],
        isCrystal ? [0.8, 1.6, 3.0, 1] : [2.8, 1.2, 0.4, 1],
        const [0, 0, 0, 0],
        mid: 0.2,
      ),
    );
    // Wide heat glow that lingers.
    glow.spawn(
      x: x,
      y: y,
      z: 0.05,
      life: 1.1,
      size: 1.1 * s,
      endSize: 1.7 * s,
      color: ColorRamp(
        isCrystal ? [0.3, 0.7, 1.2, 1] : [1.1, 0.42, 0.12, 1],
        isCrystal ? [0.05, 0.15, 0.4, 1] : [0.35, 0.08, 0.06, 1],
        const [0, 0, 0, 0],
        mid: 0.3,
      ),
    );

    // Billowing fireball: puffs that bloom outward, cooling from white-yellow
    // through orange to a dark red.
    final puffs = _n((isCrystal ? 8 : 14) * (isBig ? 1.5 : 1.0));
    for (int i = 0; i < puffs; i++) {
      final a = _r() * math.pi * 2;
      final speed = (0.35 + 0.9 * _r()) * s;
      final start = (0.22 + 0.16 * _r()) * s;
      fireballs.spawn(
        x: x + _rs() * 0.06 * s,
        y: y + _rs() * 0.06 * s,
        z: -0.05 - _r() * 0.2,
        vx: math.cos(a) * speed,
        vy: math.sin(a) * speed,
        vz: -_r() * speed * 0.5,
        life: 0.45 + 0.55 * _r(),
        size: start,
        endSize: start * (1.9 + 0.6 * _r()),
        rotation: _r() * math.pi * 2,
        spin: _rs() * 2.5,
        drag: 3.2,
        color: isCrystal
            ? const ColorRamp(
                [2.0, 3.6, 5.0, 1],
                [0.4, 1.0, 2.6, 1],
                [0, 0, 0, 0],
                mid: 0.3,
              )
            : const ColorRamp(
                [3.4, 2.4, 1.1, 1],
                [2.0, 0.6, 0.16, 1],
                [0, 0, 0, 0],
                mid: 0.28,
              ),
      );
    }

    // The original fire particles (yellow -> red -> gone).
    for (int i = 0; i < _n(25 * many); i++) {
      final a = _r() * math.pi * 2;
      final speed = (0.25 + 0.35 * _r()) * s;
      final start = (0.5 + 0.1 * _rs()) * 0.55 * s;
      fire.spawn(
        x: x + _rs() * 0.1 * s,
        y: y + _rs() * 0.1 * s,
        z: _rs() * 0.15,
        vx: math.cos(a) * speed,
        vy: math.sin(a) * speed,
        vz: -_r() * speed,
        life: math.max(0.1, 0.75 + 0.5 * _rs()),
        size: start,
        endSize: start * 1.8,
        rotation: _r() * math.pi * 2,
        spin: _rs() * 2.0,
        drag: 2.0,
        color: isCrystal
            ? const ColorRamp(
                [1.2, 2.4, 3.2, 1],
                [0.3, 0.6, 2.2, 1],
                [0, 0, 0, 0],
              )
            : const ColorRamp(
                [2.6, 2.4, 0.6, 1],
                [2.2, 0.45, 0.35, 1],
                [0, 0, 0, 0],
              ),
      );
    }

    // The original debris: 25 streaks with random red/green.
    for (int i = 0; i < _n(25 * many); i++) {
      final a = _r() * math.pi * 2;
      final speed = (1.0 + 0.5 * _rs()) * 1.3 * s;
      final r = (255 + 127 * _rs()).clamp(0, 255) / 255.0;
      final g = (255 + 127 * _rs()).clamp(0, 255) / 255.0;
      debris.spawn(
        x: x,
        y: y,
        vx: math.cos(a) * speed,
        vy: math.sin(a) * speed,
        vz: _rs() * speed * 0.6,
        life: math.max(0.05, 0.75 + 0.5 * _rs()),
        size: (0.3 + 0.1 * _rs()) * 0.36 * s,
        aspect: 1.7,
        drag: 1.5,
        alignToVelocity: true,
        color: ColorRamp.fade([r * 2.2, g * 2.2, 2.2, 1]),
      );
    }

    // Fast sparks.
    for (int i = 0; i < _n(isBig ? 50 : 22); i++) {
      final a = _r() * math.pi * 2;
      final speed = (1.6 + 3.0 * _r()) * s;
      sparks.spawn(
        x: x,
        y: y,
        vx: math.cos(a) * speed,
        vy: math.sin(a) * speed,
        vz: _rs() * speed * 0.8,
        life: 0.3 + 0.5 * _r(),
        size: 0.03 * s,
        aspect: 6.0,
        drag: 3.0,
        alignToVelocity: true,
        color: isCrystal
            ? const ColorRamp.fade([2.0, 4.0, 6.0, 1])
            : const ColorRamp(
                [6.0, 4.5, 2.0, 1],
                [4.0, 1.4, 0.4, 1],
                [0, 0, 0, 0],
              ),
      );
    }

    // Embers drifting out and flickering for a while.
    for (int i = 0; i < _n(isBig ? 36 : 14); i++) {
      final a = _r() * math.pi * 2;
      final speed = (0.2 + 0.7 * _r()) * s;
      embers.spawn(
        x: x + _rs() * 0.1 * s,
        y: y + _rs() * 0.1 * s,
        z: -0.05,
        vx: math.cos(a) * speed,
        vy: math.sin(a) * speed,
        life: 0.9 + 1.2 * _r(),
        size: 0.05 + 0.05 * _r(),
        endSize: 0.0,
        rotation: _r() * math.pi,
        spin: _rs() * 4,
        drag: 1.2,
        color: isCrystal
            ? const ColorRamp.fade([1.5, 3.0, 4.5, 1])
            : const ColorRamp(
                [4.0, 2.4, 0.8, 1],
                [2.6, 0.9, 0.2, 1],
                [0, 0, 0, 0],
              ),
      );
    }

    // Smoke (or rock dust) that rolls out after the flash and lingers. The
    // first moments are tinted by the fire behind it.
    final smokeCount = _n((isRock ? 9 : 7) * many);
    for (int i = 0; i < smokeCount; i++) {
      final a = _r() * math.pi * 2;
      final speed = (0.12 + 0.35 * _r()) * s;
      final size = (0.35 + 0.3 * _r()) * s;
      smoke.spawn(
        x: x + _rs() * 0.15 * s,
        y: y + _rs() * 0.15 * s,
        z: 0.1 + _r() * 0.15,
        vx: math.cos(a) * speed,
        vy: math.sin(a) * speed,
        life: 1.8 + 1.4 * _r(),
        size: size,
        endSize: size * 3.0,
        rotation: _r() * math.pi * 2,
        spin: _rs() * 0.5,
        drag: 1.1,
        color: isCrystal
            ? const ColorRamp(
                [0.25, 0.45, 0.8, 0.0],
                [0.06, 0.1, 0.22, 0.45],
                [0.02, 0.02, 0.05, 0.0],
                mid: 0.12,
              )
            : isRock
            ? const ColorRamp(
                [0.9, 0.5, 0.25, 0.0],
                [0.25, 0.19, 0.16, 0.5],
                [0.1, 0.08, 0.09, 0.0],
                mid: 0.12,
              )
            : const ColorRamp(
                [1.1, 0.45, 0.15, 0.0],
                [0.18, 0.14, 0.18, 0.55],
                [0.08, 0.06, 0.1, 0.0],
                mid: 0.12,
              ),
      );
    }

    // The original red ring (0.2 -> 1.0 scale over 0.75s).
    rings.spawn(
      x: x,
      y: y,
      z: 0.02,
      life: 0.75,
      size: 2.56 * 0.2 * s,
      endSize: 2.56 * s,
      color: const ColorRamp.fade([1.6, 1.6, 1.6, 1]),
    );
    // A crisp shockwave on top.
    shockwaves.spawn(
      x: x,
      y: y,
      life: 0.45,
      size: 0.2 * s,
      endSize: 2.6 * s,
      color: ColorRamp(
        isCrystal ? [1.0, 2.2, 3.5, 1] : [3.2, 2.4, 1.5, 1],
        isCrystal ? [0.3, 0.7, 1.4, 0.6] : [1.3, 0.5, 0.3, 0.6],
        const [0, 0, 0, 0],
        mid: 0.35,
      ),
    );

    // Five flares.
    for (int i = 0; i < 5; i++) {
      _flares.add(_Flare(x, y, _r() * math.pi * 2, _r() * 0.3 + 1.0, s));
    }

    // Light: a hard flash that lights up everything around, then the fire
    // keeps glowing and flickering while it burns down.
    if (withLight) {
      final color = isCrystal ? [0.45, 0.8, 1.0] : [1.0, 0.6, 0.28];
      _light(
        x,
        y,
        -0.6,
        color,
        (isBig ? 48.0 : 26.0) * s,
        1.4,
        (isBig ? 5.0 : 3.6) * s,
        flicker: 0.35,
        sustain: 0.28,
      );
    }
  }

  void _spawnChunk(
    double x,
    double y,
    double s,
    int rockVariant,
    ObjectKind source,
  ) {
    _ChunkKind kind;
    double size;
    bool burning = true;
    if (source == ObjectKind.asteroidPowerUp) {
      kind = _ChunkKind.crystal;
      size = (0.05 + 0.05 * _r()) * s;
      burning = false;
    } else if (rockVariant >= 0) {
      kind = _ChunkKind.rock;
      size = (0.06 + 0.07 * _r()) * s;
      burning = _r() < 0.5;
    } else {
      kind = _ChunkKind.metal;
      size = (0.05 + 0.07 * _r()) * s;
    }
    final a = _r() * math.pi * 2;
    final speed = (0.6 + 1.3 * _r()) * s;
    _chunks.add(
      _Chunk(
        kind,
        Vector3(x, y, 0),
        Vector3(math.cos(a) * speed, math.sin(a) * speed, _rs() * speed * 0.7),
        Vector3(_rs(), _rs(), _rs()).normalized(),
        (4 + 8 * _r()) * (_rnd.nextBool() ? 1 : -1),
        size,
        0.7 + 0.8 * _r(),
        burning,
      ),
    );
  }

  /// The original ExplosionMini: two cyan stars twisting out over 0.2s.
  void miniExplosion(double gx, double gy) {
    final x = gx * kWorld;
    final y = -gy * kWorld + originY;
    for (int i = 0; i < 2; i++) {
      double rotationStart = _r() * 90.0;
      double rotationEnd = 180.0 + _r() * 90.0;
      if (i == 0) {
        rotationStart = -rotationStart;
        rotationEnd = -rotationEnd;
      }
      _miniStars.add(_MiniStar(x, y, rotationStart, rotationEnd));
    }
    for (int i = 0; i < 7; i++) {
      final a = -math.pi / 2 + _rs() * 1.4;
      final speed = 1.0 + 1.8 * _r();
      sparks.spawn(
        x: x,
        y: y,
        z: -0.05,
        vx: math.cos(a) * speed,
        vy: -math.sin(a) * speed,
        vz: _rs() * 0.8,
        life: 0.12 + 0.18 * _r(),
        size: 0.02,
        aspect: 5.0,
        drag: 4.0,
        alignToVelocity: true,
        color: const ColorRamp.fade([1.5, 3.5, 4.0, 1]),
      );
    }
    glow.spawn(
      x: x,
      y: y,
      z: -0.05,
      life: 0.15,
      size: 0.35,
      endSize: 0.2,
      color: const ColorRamp.fade([1.0, 2.6, 3.0, 1]),
    );
    _light(x, y, -0.3, const [0.5, 0.9, 1.0], 4, 0.14, 1.1);
  }

  void muzzleFlash(double gx, double gy, double directionDeg, double size) {
    final x = gx * kWorld;
    final y = -gy * kWorld + originY;
    glow.spawn(
      x: x,
      y: y,
      z: -0.05,
      life: 0.18,
      size: 0.35 * size,
      endSize: 0.15 * size,
      color: const ColorRamp.fade([4.0, 2.8, 1.0, 1]),
    );
    final a = -directionDeg * math.pi / 180.0;
    for (int i = 0; i < 4; i++) {
      final spread = a + _rs() * 0.5;
      final speed = 1.0 + _r();
      sparks.spawn(
        x: x,
        y: y,
        vx: math.cos(spread) * speed,
        vy: math.sin(spread) * speed,
        life: 0.1 + 0.1 * _r(),
        size: 0.02,
        aspect: 4,
        drag: 3,
        alignToVelocity: true,
        color: const ColorRamp.fade([4.0, 2.5, 0.8, 1]),
      );
    }
    _light(x, y, -0.3, const [1.0, 0.7, 0.3], 6 * size, 0.16, 1.4 * size);
  }

  void pickupBurst(
    double gx,
    double gy,
    List<double> color, {
    bool big = false,
  }) {
    final x = gx * kWorld;
    final y = -gy * kWorld + originY;
    final n = big ? 26 : 10;
    for (int i = 0; i < n; i++) {
      final a = _r() * math.pi * 2;
      final speed = (big ? 1.4 : 0.7) * (0.5 + _r());
      sparks.spawn(
        x: x,
        y: y,
        z: -0.1,
        vx: math.cos(a) * speed,
        vy: math.sin(a) * speed,
        vz: _rs() * 0.5,
        life: 0.25 + 0.25 * _r(),
        size: 0.025,
        aspect: 4,
        drag: 3,
        alignToVelocity: true,
        color: ColorRamp.fade(color),
      );
    }
    shockwaves.spawn(
      x: x,
      y: y,
      z: -0.05,
      life: big ? 0.5 : 0.3,
      size: 0.1,
      endSize: big ? 1.6 : 0.6,
      color: ColorRamp.fade([
        color[0] * 0.6,
        color[1] * 0.6,
        color[2] * 0.6,
        1,
      ]),
    );
    final m = math.max(color[0], math.max(color[1], color[2]));
    _light(
      x,
      y,
      -0.4,
      [color[0] / m, color[1] / m, color[2] / m],
      big ? 12 : 3,
      big ? 0.5 : 0.25,
      big ? 3.0 : 1.4,
    );
  }

  void update(double dt) {
    _time += dt;
    for (int i = _scheduled.length - 1; i >= 0; i--) {
      final s = _scheduled[i];
      s.delay -= dt;
      if (s.delay <= 0) {
        _scheduled.removeAt(i);
        s.action();
      }
    }

    for (final layer in _layers) {
      layer.update(dt);
    }

    for (int i = _flares.length - 1; i >= 0; i--) {
      final f = _flares[i];
      f.age += dt;
      if (f.age >= 0.75 * f.multiplier) _flares.removeAt(i);
    }
    for (int i = _miniStars.length - 1; i >= 0; i--) {
      final m = _miniStars[i];
      m.age += dt;
      if (m.age >= 0.2) _miniStars.removeAt(i);
    }
    for (final mesh in _chunkMeshes.values) {
      mesh.clearInstances();
    }
    for (int i = _chunks.length - 1; i >= 0; i--) {
      final c = _chunks[i];
      c.age += dt;
      if (c.age >= c.life) {
        _chunks.removeAt(i);
        continue;
      }
      c.velocity.scale(math.exp(-1.2 * dt));
      c.position.addScaled(c.velocity, dt);
      c.rotation = Quaternion.axisAngle(c.spinAxis, c.spin * dt) * c.rotation;
      final t = c.age / c.life;
      final k = t < 0.7 ? 1.0 : 1.0 - (t - 0.7) / 0.3;
      _chunkMeshes[c.kind]!.addInstance(
        Matrix4.compose(c.position, c.rotation, Vector3.all(c.size * k)),
      );
      if (!c.burning) continue;
      // Burning chunks leave fire and smoke behind.
      c.trailTimer -= dt;
      if (c.trailTimer <= 0) {
        c.trailTimer = 0.025;
        final p = c.position;
        trails.spawn(
          x: p.x,
          y: p.y,
          z: p.z,
          life: 0.35,
          size: 0.12 * k,
          endSize: 0.03,
          color: const ColorRamp(
            [2.6, 1.2, 0.4, 1],
            [0.8, 0.2, 0.08, 1],
            [0, 0, 0, 0],
          ),
        );
        if (_r() < 0.4) {
          smoke.spawn(
            x: p.x,
            y: p.y,
            z: p.z + 0.05,
            life: 0.8 + 0.5 * _r(),
            size: 0.08,
            endSize: 0.3,
            rotation: _r() * math.pi * 2,
            color: const ColorRamp(
              [0.3, 0.15, 0.08, 0.0],
              [0.2, 0.17, 0.2, 0.45],
              [0.03, 0.03, 0.04, 0.0],
              mid: 0.2,
            ),
          );
        }
      }
    }

    for (int i = _flashLights.length - 1; i >= 0; i--) {
      final l = _flashLights[i];
      l.age += dt;
      if (l.age >= l.life) _flashLights.removeAt(i);
    }

    trauma = math.max(0.0, trauma - dt * 1.4);
    flash = math.max(0.0, flash - dt * 3.0);
  }

  /// Hands this frame's effect lights to the light pool.
  void requestLights() {
    for (final l in _flashLights) {
      final t = (l.age / l.life).clamp(0.0, 1.0);
      final a = l.attack / l.life;
      double env;
      if (t < a) {
        env = t / a;
      } else if (l.sustain > 0) {
        // Flash, settle to the fire's glow, then burn down.
        final flashT = ((l.age - l.attack) / 0.3).clamp(0.0, 1.0);
        final flash = 1.0 - flashT * flashT * (3 - 2 * flashT);
        final burn = math.pow(1.0 - (t - a) / (1 - a), 1.5).toDouble();
        env = l.sustain * burn + (1 - l.sustain) * flash;
      } else {
        env = math.pow(1.0 - (t - a) / (1 - a), 2.0).toDouble();
      }
      if (l.flicker > 0) {
        env *=
            1.0 -
            l.flicker *
                (0.5 +
                    0.5 *
                        math.sin(_time * 31.0 + l.x * 13) *
                        math.sin(_time * 17.0 + l.y * 7));
      }
      lights.request(
        l.x,
        l.y,
        l.z,
        l.color[0],
        l.color[1],
        l.color[2],
        l.peak * env,
        l.range,
      );
    }
  }

  /// Writes the non-particle sprites (flares, mini stars) and all layers.
  void write() {
    for (final layer in _layers) {
      layer.write();
    }

    for (final f in _flares) {
      final m = f.multiplier;
      final t = (f.age / (0.75 * m)).clamp(0.0, 1.0);
      final scaleY = 0.3 * m + (0.8 - 0.3 * m) * t;
      double opacity;
      if (f.age < 0.25 * m) {
        opacity = f.age / (0.25 * m);
      } else {
        opacity = (1.0 - (f.age - 0.25 * m) / (0.5 * m)).clamp(0.0, 1.0);
      }
      final w = 0.64 * 0.24 * f.scale;
      final h = 2.56 * scaleY * f.scale * 0.72;
      // Pivot at (0.3, 1.0): the flare grows outward from the center.
      final dirX = math.cos(f.angle + math.pi / 2);
      final dirY = math.sin(f.angle + math.pi / 2);
      final cx = f.x + dirX * h * 0.5;
      final cy = f.y + dirY * h * 0.5;
      batches.flare.add(
        cx,
        cy,
        -0.02,
        w,
        h,
        f.angle,
        1.6 * opacity,
        1.3 * opacity,
        1.0 * opacity,
        opacity,
      );
    }

    for (final s in _miniStars) {
      final t = s.age / 0.2;
      final rot = (s.rotStart + (s.rotEnd - s.rotStart) * t) * math.pi / 180;
      final o = 1.0 - t;
      batches.star.add(
        s.x,
        s.y,
        -0.05,
        0.31,
        0.31,
        -rot,
        0.58 * 2.5 * o,
        0.96 * 2.5 * o,
        0.98 * 2.5 * o,
        o,
      );
    }
  }

  /// Current shake offset (world units) and roll.
  (double, double, double) shake(double time) {
    final k = trauma * trauma;
    if (k <= 0) return (0, 0, 0);
    final dx =
        (math.sin(time * 47.0) + math.sin(time * 71.3) * 0.5) * 0.035 * k;
    final dy =
        (math.cos(time * 53.0) + math.sin(time * 67.1) * 0.5) * 0.035 * k;
    final roll = math.sin(time * 37.0) * 0.014 * k;
    return (dx, dy, roll);
  }
}
