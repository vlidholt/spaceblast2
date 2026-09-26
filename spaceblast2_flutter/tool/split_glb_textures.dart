// Moves the textures embedded in the game's .glb models out into separate
// image files and writes models/textures.json describing which material slot
// each one belongs to.
//
// Why: Safari cannot decode images embedded in a .glb through Flutter web's
// byte-based image codec (the models render untextured), while image files
// loaded as regular assets work everywhere. The game loads these files with
// Texture2D.fromAsset and assigns them after importing each model.
//
// Usage (from spaceblast2_flutter/):
//   dart run tool/split_glb_textures.dart <source models dir>
// e.g. dart run tool/split_glb_textures.dart ../reference/spaceblast_assets/models
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

void main(List<String> args) {
  final sourceDir = Directory(args.isEmpty ? 'models' : args.first);
  final outDir = Directory('models');
  final texDir = Directory('models/textures')..createSync(recursive: true);
  final manifest = <String, Map<String, String>>{};

  final sources =
      sourceDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.glb'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  for (final file in sources) {
    final name = file.uri.pathSegments.last.replaceAll('.glb', '');
    final glb = _Glb.parse(file.readAsBytesSync());
    final json = glb.json;
    final images = (json['images'] as List?) ?? const [];
    final textures = (json['textures'] as List?) ?? const [];
    if (images.isEmpty) {
      stdout.writeln('$name: no embedded images, copied as is');
      File('${outDir.path}/$name.glb').writeAsBytesSync(glb.encode());
      continue;
    }

    // Material slot -> image index (these models have a single material).
    final slots = <String, int>{};
    for (final material in (json['materials'] as List)) {
      final m = material as Map<String, dynamic>;
      final pbr = m['pbrMetallicRoughness'] as Map<String, dynamic>?;
      final base = pbr?.remove('baseColorTexture') as Map<String, dynamic>?;
      if (base != null) slots['base'] = textures[base['index']]['source'];
      final emissive = m.remove('emissiveTexture') as Map<String, dynamic>?;
      if (emissive != null) {
        slots['emissive'] = textures[emissive['index']]['source'];
      }
      for (final unsupported in [
        'normalTexture',
        'occlusionTexture',
      ]) {
        if (m.containsKey(unsupported)) {
          throw StateError('$name uses $unsupported; extend this tool.');
        }
      }
      if (pbr?.containsKey('metallicRoughnessTexture') ?? false) {
        throw StateError('$name uses metallicRoughnessTexture.');
      }
    }

    final entry = <String, String>{};
    final imageViews = <int>{};
    slots.forEach((slot, imageIndex) {
      final image = images[imageIndex] as Map<String, dynamic>;
      final viewIndex = image['bufferView'] as int;
      imageViews.add(viewIndex);
      final ext = image['mimeType'] == 'image/png' ? 'png' : 'jpg';
      final path = 'models/textures/${name}_$slot.$ext';
      File(
        '${texDir.path}/${name}_$slot.$ext',
      ).writeAsBytesSync(glb.bufferView(viewIndex));
      entry[slot] = path;
    });
    manifest[name] = entry;

    json.remove('images');
    json.remove('textures');
    json.remove('samplers');
    glb.removeBufferViews(imageViews);
    File('${outDir.path}/$name.glb').writeAsBytesSync(glb.encode());
    stdout.writeln('$name: ${entry.values.join(', ')}');
  }

  File('${outDir.path}/textures.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert(manifest),
  );
}

/// Minimal GLB container reader/writer (JSON chunk + one BIN chunk).
class _Glb {
  _Glb(this.json, this.bin);

  final Map<String, dynamic> json;
  Uint8List bin;

  static _Glb parse(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    if (data.getUint32(0, Endian.little) != 0x46546C67) {
      throw const FormatException('Not a GLB file');
    }
    var offset = 12;
    Map<String, dynamic>? json;
    var bin = Uint8List(0);
    while (offset < bytes.length) {
      final length = data.getUint32(offset, Endian.little);
      final type = data.getUint32(offset + 4, Endian.little);
      final chunk = Uint8List.sublistView(
        bytes,
        offset + 8,
        offset + 8 + length,
      );
      if (type == 0x4E4F534A) {
        json = jsonDecode(utf8.decode(chunk)) as Map<String, dynamic>;
      } else if (type == 0x004E4942) {
        bin = Uint8List.fromList(chunk);
      }
      offset += 8 + length;
    }
    return _Glb(json!, bin);
  }

  Uint8List bufferView(int index) {
    final view = (json['bufferViews'] as List)[index] as Map<String, dynamic>;
    final start = (view['byteOffset'] as int?) ?? 0;
    return Uint8List.sublistView(
      bin,
      start,
      start + (view['byteLength'] as int),
    );
  }

  /// Drops buffer views (and their bytes) and renumbers the references.
  void removeBufferViews(Set<int> remove) {
    final views = (json['bufferViews'] as List).cast<Map<String, dynamic>>();
    final remap = <int, int>{};
    final kept = <Map<String, dynamic>>[];
    final out = BytesBuilder();
    for (var i = 0; i < views.length; i++) {
      if (remove.contains(i)) continue;
      final bytes = bufferView(i);
      // Keep 4-byte alignment for vertex data.
      while (out.length % 4 != 0) {
        out.addByte(0);
      }
      final view = Map<String, dynamic>.from(views[i])
        ..['byteOffset'] = out.length;
      out.add(bytes);
      remap[i] = kept.length;
      kept.add(view);
    }
    json['bufferViews'] = kept;
    for (final accessor in (json['accessors'] as List? ?? const [])) {
      final a = accessor as Map<String, dynamic>;
      if (a['bufferView'] != null) a['bufferView'] = remap[a['bufferView']];
    }
    bin = out.toBytes();
    (json['buffers'] as List)[0]['byteLength'] = bin.length;
  }

  Uint8List encode() {
    var jsonBytes = utf8.encode(jsonEncode(json));
    final jsonPad = (4 - jsonBytes.length % 4) % 4;
    jsonBytes = Uint8List.fromList([
      ...jsonBytes,
      ...List.filled(jsonPad, 0x20),
    ]);
    final binPad = (4 - bin.length % 4) % 4;
    final binBytes = Uint8List.fromList([...bin, ...List.filled(binPad, 0)]);
    final total = 12 + 8 + jsonBytes.length + 8 + binBytes.length;
    final out = ByteData(total);
    out.setUint32(0, 0x46546C67, Endian.little);
    out.setUint32(4, 2, Endian.little);
    out.setUint32(8, total, Endian.little);
    out.setUint32(12, jsonBytes.length, Endian.little);
    out.setUint32(16, 0x4E4F534A, Endian.little);
    final bytes = out.buffer.asUint8List();
    bytes.setRange(20, 20 + jsonBytes.length, jsonBytes);
    var o = 20 + jsonBytes.length;
    out.setUint32(o, binBytes.length, Endian.little);
    out.setUint32(o + 4, 0x004E4942, Endian.little);
    bytes.setRange(o + 8, o + 8 + binBytes.length, binBytes);
    return bytes;
  }
}
