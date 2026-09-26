import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Posts [bytes] to a local capture server (development only).
Future<void> postPng(String url, Uint8List bytes, {String? only}) async {
  // Several tabs may run the app; only the visible one reports.
  if (web.document.hidden) return;
  if (only != null && !userAgent().contains(only)) return;
  await web.window
      .fetch(
        url.toJS,
        web.RequestInit(method: 'POST', body: bytes.toJS),
      )
      .toDart;
}

/// Reloads the page (a full restart on the web).
void reloadPage() => web.window.location.reload();

/// The browser's user agent.
String userAgent() => web.window.navigator.userAgent;

/// Posts [text] to a local receiver (development only).
Future<void> postText(String url, String text) async {
  await web.window
      .fetch(url.toJS, web.RequestInit(method: 'POST', body: text.toJS))
      .toDart;
}
