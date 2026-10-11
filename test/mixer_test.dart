import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonhush/audio/mixer.dart';
import 'package:moonhush/models/sounds.dart';

import 'fake_player.dart';

void main() {
  late Mixer mixer;

  setUp(() {
    FakeLoopPlayer.all.clear();
    mixer = Mixer(playerFactory: FakeLoopPlayer.new);
  });

  test('a sound fades in when switched on and is released after fading out', () {
    fakeAsync((async) {
      mixer.turnOn('rain', volume: 0.5);
      async.flushMicrotasks();
      final rain = playerFor('rain');
      expect(rain.playing, isTrue);
      expect(rain.volume, lessThan(0.1));

      async.elapse(const Duration(seconds: 2));
      expect(rain.volume, closeTo(0.5, 1e-9));

      mixer.turnOff('rain');
      expect(mixer.isOn('rain'), isFalse);
      async.elapse(const Duration(seconds: 1));
      expect(rain.disposed, isTrue);
      expect(mixer.hasSound, isFalse);
    });
  });

  test('a mix switches off sounds it does not contain and sets volumes', () {
    fakeAsync((async) {
      mixer.turnOn('white_noise');
      async.elapse(const Duration(seconds: 2));
      mixer.applyMix(presets.first); // Rainy night: rain_on_roof + fireplace
      async.elapse(const Duration(seconds: 2));
      expect(mixer.activeIds.toSet(), {'rain_on_roof', 'fireplace'});
      expect(playerFor('fireplace').volume, closeTo(0.45, 1e-9));
      expect(playerFor('white_noise').disposed, isTrue);
    });
  });

  test('sleep timer fades out over the last 30 seconds, then stops', () {
    fakeAsync((async) {
      mixer.setSleepTimer(const Duration(minutes: 2));
      mixer.turnOn('ocean_waves', volume: 1);
      async.elapse(const Duration(seconds: 85));
      final waves = playerFor('ocean_waves');
      expect(waves.volume, closeTo(1, 1e-9));
      expect(mixer.sleepRemaining, const Duration(seconds: 35));

      async.elapse(const Duration(seconds: 20)); // 15 s left, halfway down
      expect(waves.volume, inInclusiveRange(0.3, 0.7));

      async.elapse(const Duration(seconds: 16));
      expect(waves.disposed, isTrue);
      expect(mixer.hasSound, isFalse);
      expect(mixer.sleepRemaining, isNull);
      expect(mixer.sleepAfter, const Duration(minutes: 2), reason: 'setting is kept for next time');
    });
  });

  test('pause and resume keep the same sounds', () {
    fakeAsync((async) {
      mixer.turnOn('fan');
      async.elapse(const Duration(seconds: 2));
      mixer.pause();
      async.elapse(const Duration(seconds: 1));
      expect(mixer.isPaused, isTrue);
      expect(playerFor('fan').playing, isFalse);

      mixer.resume();
      async.elapse(const Duration(seconds: 1));
      expect(mixer.isPlaying, isTrue);
      expect(playerFor('fan').playing, isTrue);
      expect(playerFor('fan').volume, closeTo(0.6, 1e-9));
    });
  });

  test('switching a sound on during stop-all cancels the stop', () {
    fakeAsync((async) {
      mixer.turnOn('rain');
      async.elapse(const Duration(seconds: 2));
      mixer.stopAll();
      async.elapse(const Duration(milliseconds: 500));
      mixer.turnOn('wind');
      async.elapse(const Duration(seconds: 3));
      expect(mixer.isOn('wind'), isTrue);
      expect(mixer.isOn('rain'), isTrue);
      expect(playerFor('wind').volume, closeTo(0.6, 1e-9));
    });
  });
}
