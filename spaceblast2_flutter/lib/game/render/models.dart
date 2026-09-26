import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_scene/scene.dart';
import 'package:vector_math/vector_math.dart';

/// Loads the .glb models once and hands out pooled instances.
class ModelLibrary {
  final Map<String, Node> _templates = {};
  final Map<String, List<ModelInstance>> _pools = {};

  static const modelNames = [
    'ship',
    'asteroid_big_0',
    'asteroid_big_1',
    'asteroid_big_2',
    'asteroid_small_0',
    'asteroid_small_1',
    'asteroid_small_2',
    'crystal_0',
    'crystal_1',
    'crystal_2',
    'enemy_scout_0',
    'enemy_scout_1',
    'enemy_scout_2',
    'enemy_destroyer_0',
    'enemy_destroyer_1',
    'enemy_destroyer_2',
    'enemy_boss_0',
    'enemy_boss_1',
    'enemy_boss_2',
  ];

  Future<void> load({void Function(double progress)? onProgress}) async {
    // Textures live next to the models as regular image assets (see
    // tool/split_glb_textures.dart): Safari cannot decode images embedded in
    // a .glb on the web.
    final manifest =
        jsonDecode(await rootBundle.loadString('models/textures.json'))
            as Map<String, dynamic>;
    var done = 0;
    await Future.wait([
      for (final name in modelNames)
        _loadModel(name, manifest[name] as Map<String, dynamic>?).then((_) {
          done++;
          onProgress?.call(done / modelNames.length);
        }),
    ]);
  }

  Future<void> _loadModel(String name, Map<String, dynamic>? textures) async {
    final results = await Future.wait<Object?>([
      Node.fromGlbAsset(
        'models/$name.glb',
        onWarning: (w) => debugPrint('model $name: $w'),
      ),
      if (textures?['base'] case final String path) Texture2D.fromAsset(path),
      if (textures?['emissive'] case final String path)
        Texture2D.fromAsset(path),
    ]);
    final node = results[0] as Node;
    final base = textures?['base'] != null ? results[1] as Texture2D : null;
    final emissive = textures?['emissive'] != null
        ? results.last as Texture2D
        : null;
    for (final meshNode in node.meshNodes) {
      for (final primitive in meshNode.mesh?.primitives ?? const []) {
        final material = primitive.material;
        if (material is! PhysicallyBasedMaterial) continue;
        if (base != null) material.baseColorTexture = base;
        if (emissive != null) material.emissiveTexture = emissive;
      }
    }
    _templates[name] = node;
  }

  Node template(String name) => _templates[name]!;

  /// Pre-creates instances so the first waves do not clone on the fly.
  void warm(String name, int count) {
    final pool = _pools.putIfAbsent(name, () => []);
    while (pool.length < count) {
      pool.add(ModelInstance._(name, _templates[name]!.clone()));
    }
  }

  ModelInstance acquire(String name) {
    final pool = _pools.putIfAbsent(name, () => []);
    if (pool.isNotEmpty) return pool.removeLast()..reset();
    final template = _templates[name];
    if (template == null) {
      throw ArgumentError('Unknown model $name');
    }
    return ModelInstance._(name, template.clone());
  }

  void release(ModelInstance instance) {
    instance.root.detach();
    _pools.putIfAbsent(instance.name, () => []).add(instance);
  }
}

/// One placed copy of a model. [root] carries the game transform, [model] is
/// the cloned asset beneath it (never overwrite its transform).
class ModelInstance {
  ModelInstance._(this.name, this.model) {
    root.add(pivot);
    pivot.add(model);
  }

  final String name;
  final Node root = Node();

  /// Extra local rotation (banking, tumbling) between root and model.
  final Node pivot = Node();
  final Node model;

  List<PhysicallyBasedMaterial>? _materials;
  List<Vector4>? _baseEmissive;

  double _tintAmount = 0.0;

  void reset() {
    if (_tintAmount != 0.0) setTint(0, 0, 0, 0);
    pivot.rotation = Quaternion.identity();
    root.visible = true;
  }

  /// Adds an emissive color overlay (damage, hit flashes). [amount] 0 clears.
  /// Materials are copied on first use so instances never share a tint.
  void setTint(double r, double g, double b, double amount) {
    if (amount == 0.0 && _tintAmount == 0.0) return;
    _tintAmount = amount;
    _ensureOwnMaterials();
    final mats = _materials!;
    for (int i = 0; i < mats.length; i++) {
      final base = _baseEmissive![i];
      mats[i].emissiveFactor = Vector4(
        base.x + r * amount,
        base.y + g * amount,
        base.z + b * amount,
        1.0,
      );
    }
  }

  /// Direct access to the per-instance materials, copying them if needed.
  List<PhysicallyBasedMaterial> get materials {
    _ensureOwnMaterials();
    return _materials!;
  }

  void _ensureOwnMaterials() {
    if (_materials != null) return;
    final mats = <PhysicallyBasedMaterial>[];
    final base = <Vector4>[];
    for (final node in model.meshNodes) {
      final mesh = node.mesh;
      if (mesh == null) continue;
      for (final primitive in mesh.primitives) {
        final m = primitive.material;
        if (m is PhysicallyBasedMaterial) {
          final copy = copyPbrMaterial(m);
          primitive.material = copy;
          mats.add(copy);
          base.add(m.emissiveFactor.clone());
        }
      }
    }
    _materials = mats;
    _baseEmissive = base;
  }
}

PhysicallyBasedMaterial copyPbrMaterial(PhysicallyBasedMaterial m) {
  final c = PhysicallyBasedMaterial(
    baseColorTexture: m.baseColorTexture,
    metallicRoughnessTexture: m.metallicRoughnessTexture,
    normalTexture: m.normalTexture,
    emissiveTexture: m.emissiveTexture,
    occlusionTexture: m.occlusionTexture,
  );
  c.baseColorFactor = m.baseColorFactor.clone();
  c.baseColorTextureTransform = m.baseColorTextureTransform;
  c.baseColorTextureTexCoord = m.baseColorTextureTexCoord;
  c.vertexColorWeight = m.vertexColorWeight;
  c.metallicFactor = m.metallicFactor;
  c.roughnessFactor = m.roughnessFactor;
  c.metallicRoughnessTextureTransform = m.metallicRoughnessTextureTransform;
  c.metallicRoughnessTextureTexCoord = m.metallicRoughnessTextureTexCoord;
  c.normalScale = m.normalScale;
  c.normalTextureTransform = m.normalTextureTransform;
  c.normalTextureTexCoord = m.normalTextureTexCoord;
  c.emissiveFactor = m.emissiveFactor.clone();
  c.emissiveStrength = m.emissiveStrength;
  c.emissiveTextureTransform = m.emissiveTextureTransform;
  c.emissiveTextureTexCoord = m.emissiveTextureTexCoord;
  c.occlusionStrength = m.occlusionStrength;
  c.occlusionTextureTransform = m.occlusionTextureTransform;
  c.occlusionTextureTexCoord = m.occlusionTextureTexCoord;
  c.alphaMode = m.alphaMode;
  c.alphaCutoff = m.alphaCutoff;
  c.doubleSided = m.doubleSided;
  c.environment = m.environment;
  return c;
}
