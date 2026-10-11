import 'package:just_audio/just_audio.dart';

/// One looping sound. Kept behind an interface so the mixer can be tested
/// without real audio.
abstract class LoopPlayer {
  Future<void> load(String asset);
  Future<void> play();
  Future<void> pause();
  Future<void> setVolume(double volume);
  Future<void> dispose();
}

class JustAudioLoopPlayer implements LoopPlayer {
  final _player = AudioPlayer();

  @override
  Future<void> load(String asset) async {
    await _player.setAsset(asset);
    await _player.setLoopMode(LoopMode.one);
  }

  @override
  Future<void> play() async {
    // play() completes only when playback stops, so don't await it.
    _player.play();
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Future<void> dispose() => _player.dispose();
}
