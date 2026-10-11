import 'package:moonhush/audio/loop_player.dart';

class FakeLoopPlayer implements LoopPlayer {
  static final all = <FakeLoopPlayer>[];
  FakeLoopPlayer() {
    all.add(this);
  }

  String? asset;
  bool playing = false;
  bool disposed = false;
  double volume = 1;

  @override
  Future<void> load(String asset) async => this.asset = asset;
  @override
  Future<void> play() async => playing = true;
  @override
  Future<void> pause() async => playing = false;
  @override
  Future<void> setVolume(double v) async => volume = v;
  @override
  Future<void> dispose() async => disposed = true;
}

FakeLoopPlayer playerFor(String id) => FakeLoopPlayer.all.lastWhere((p) => p.asset == 'assets/sounds/$id.m4a');
