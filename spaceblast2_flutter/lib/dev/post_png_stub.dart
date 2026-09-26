import 'dart:io';
import 'dart:typed_data';

/// Posts [bytes] to a local capture server (development only).
Future<void> postPng(String url, Uint8List bytes, {String? only}) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(Uri.parse(url));
    request.add(bytes);
    await request.close();
  } finally {
    client.close();
  }
}

/// Reloads the page (a full restart on the web). No-op elsewhere.
void reloadPage() {}

/// The platform description.
String userAgent() => Platform.operatingSystem;

/// Posts [text] to a local receiver (development only).
Future<void> postText(String url, String text) async {
  final client = HttpClient();
  try {
    final request = await client.postUrl(Uri.parse(url));
    request.write(text);
    await request.close();
  } finally {
    client.close();
  }
}
