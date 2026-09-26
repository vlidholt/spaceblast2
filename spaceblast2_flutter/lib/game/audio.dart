import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

import 'audio_unlock/audio_unlock.dart';

/// Sound effects and music. Audio is optional: if the device (or browser)
/// refuses to start, the game plays silently.
class AudioManager {
  static const effects = [
    'explosion_0',
    'explosion_1',
    'explosion_2',
    'explosion_boss',
    'explosion_player',
    'laser',
    'hit',
    'levelup',
    'pickup_0',
    'pickup_1',
    'pickup_2',
    'pickup_powerup',
    'click',
    'buy_upgrade',
  ];

  static const _volumes = {
    'hit': 0.55,
    'laser': 0.6,
    'pickup_0': 0.7,
    'click': 0.8,
  };

  final Map<String, AudioSource> _effects = {};
  final Map<String, AudioSource> _music = {};
  final Map<String, int> _lastPlayed = {};

  SoundHandle? _musicHandle;
  String? _currentMusic;
  String? _wantedMusic;

  bool _ready = false;
  bool _starting = false;
  bool get ready => _ready;

  double musicVolume = 0.55;

  /// Starts the audio engine. Safe to call repeatedly. On the web the
  /// engine starts suspended and is unlocked by the first user gesture (see
  /// installAudioUnlock).
  Future<void> start() async {
    if (_ready || _starting) return;
    _starting = true;
    installAudioUnlock();
    try {
      final soloud = SoLoud.instance;
      if (!soloud.isInitialized) {
        await soloud.init(bufferSize: kIsWeb ? 2048 : 1024);
      }
      soloud.setMaxActiveVoiceCount(32);
      await Future.wait([
        for (final name in effects)
          soloud
              .loadAsset('assets/audio/$name.wav')
              .then((s) => _effects[name] = s),
        for (final name in ['music_intro', 'music_game', 'music_boss'])
          soloud
              .loadAsset('assets/audio/$name.mp3', mode: LoadMode.disk)
              .then((s) => _music[name] = s),
      ]);
      _ready = true;
      final wanted = _wantedMusic;
      if (wanted != null) {
        _currentMusic = null;
        playMusic(wanted);
      }
    } catch (e) {
      debugPrint('Audio unavailable: $e');
    } finally {
      _starting = false;
    }
  }

  void playEffect(String name) {
    if (!_ready) return;
    final source = _effects[name];
    if (source == null) return;
    // Identical sounds on the same frame only stack up volume.
    final now = DateTime.now().millisecondsSinceEpoch;
    final last = _lastPlayed[name];
    if (last != null && now - last < 30) return;
    _lastPlayed[name] = now;
    try {
      SoLoud.instance.play(source, volume: _volumes[name] ?? 0.85);
    } catch (e) {
      debugPrint('Failed to play $name: $e');
    }
  }

  void playMusic(String name) {
    _wantedMusic = name;
    if (!_ready || _currentMusic == name) return;
    _currentMusic = name;
    final soloud = SoLoud.instance;
    final old = _musicHandle;
    if (old != null) {
      try {
        soloud.fadeVolume(old, 0, const Duration(milliseconds: 700));
        soloud.scheduleStop(old, const Duration(milliseconds: 750));
      } catch (_) {}
    }
    final source = _music[name];
    if (source == null) return;
    try {
      final handle = soloud.play(source, volume: 0, looping: true);
      soloud.fadeVolume(handle, musicVolume, const Duration(milliseconds: 900));
      _musicHandle = handle;
    } catch (e) {
      debugPrint('Failed to play music $name: $e');
    }
  }
}
