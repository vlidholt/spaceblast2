import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

bool _installed = false;

/// Makes Web Audio reliable on iOS Safari.
///
/// flutter_soloud's engine (miniaudio) resumes its AudioContext on the first
/// touchend/click only, and only if the device already exists at that moment.
/// Here a permanent listener resumes any suspended or interrupted context on
/// every user gesture (iOS also suspends audio after calls, app switches or
/// the screen locking), and the audio session is set to "playback" so the
/// ringer switch does not mute the game (plain HTML audio ignores it too).
void installAudioUnlock() {
  if (_installed) return;
  _installed = true;

  _setPlaybackSession();

  final handler = ((web.Event _) => _resumeAll()).toJS;
  for (final type in ['touchstart', 'touchend', 'click', 'keydown']) {
    web.document.addEventListener(
      type,
      handler,
      web.AddEventListenerOptions(capture: true),
    );
  }
}

void _setPlaybackSession() {
  try {
    final navigator = globalContext['navigator'] as JSObject;
    final session = navigator['audioSession'];
    if (session != null && session.isA<JSObject>()) {
      (session as JSObject)['type'] = 'playback'.toJS;
    }
  } catch (_) {
    // Not supported by this browser.
  }
}

void _resumeAll() {
  _setPlaybackSession();
  try {
    final miniaudio = globalContext['miniaudio'];
    if (miniaudio == null || !miniaudio.isA<JSObject>()) return;
    final devices = (miniaudio as JSObject)['devices'];
    if (devices == null || !devices.isA<JSArray>()) return;
    for (final device in (devices as JSArray<JSAny?>).toDart) {
      if (device == null || !device.isA<JSObject>()) continue;
      final context = (device as JSObject)['webaudio'];
      if (context == null || !context.isA<JSObject>()) continue;
      final ctx = context as JSObject;
      final state = (ctx['state'] as JSString?)?.toDart;
      if (state != 'running' && state != 'closed') {
        ctx.callMethod('resume'.toJS);
      }
    }
  } catch (_) {
    // Never let audio housekeeping break input handling.
  }
}

/// The state of the first Web Audio context, for diagnostics.
String audioContextState() {
  try {
    final miniaudio = globalContext['miniaudio'] as JSObject?;
    final devices = miniaudio?['devices'] as JSArray<JSAny?>?;
    final list = devices?.toDart ?? const [];
    final states = [
      for (final d in list)
        if (d != null && d.isA<JSObject>())
          ((((d as JSObject)['webaudio'] as JSObject?)?['state']) as JSString?)
                  ?.toDart ??
              'none',
    ];
    return states.isEmpty ? 'no devices' : states.join(',');
  } catch (e) {
    return 'unknown ($e)';
  }
}
