import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/sounds.dart';
import 'loop_player.dart';

typedef PlayerFactory = LoopPlayer Function();

class _Channel {
  _Channel(this.player, this.volume);

  final LoopPlayer player;
  double volume;
  double fade = 0;
  double fadeTarget = 1;
  double fadeRate = 1 / 1.5; // full scale per second
  bool active = true;
}

/// Plays any number of looping sounds at once, each with its own volume.
///
/// All volume changes go through short fades so nothing starts or stops with
/// a click: a sound fades in when switched on, fades out when switched off,
/// and everything fades out slowly when the sleep timer ends.
class Mixer extends ChangeNotifier {
  Mixer({PlayerFactory? playerFactory}) : _newPlayer = playerFactory ?? JustAudioLoopPlayer.new;

  static const tick = Duration(milliseconds: 50);
  static const sleepFade = Duration(seconds: 30);

  final PlayerFactory _newPlayer;
  final _channels = <String, _Channel>{};
  final _volumes = <String, double>{};
  Timer? _ticker;

  double _master = 1;
  double _masterTarget = 1;
  double _masterRate = 2;
  bool _paused = false;
  VoidCallback? _onMasterSilent;

  Duration? _sleepAfter;
  Duration? _sleepRemaining;
  Timer? _sleepTimer;

  // ---------- reading state ----------

  bool isOn(String id) => _channels[id]?.active ?? false;
  double volumeOf(String id) => _volumes[id] ?? 0.6;
  List<String> get activeIds => [
        for (final e in _channels.entries)
          if (e.value.active) e.key
      ];
  bool get hasSound => activeIds.isNotEmpty;
  bool get isPlaying => hasSound && !_paused;
  bool get isPaused => _paused;
  Duration? get sleepAfter => _sleepAfter;
  Duration? get sleepRemaining => _sleepRemaining;
  Mix currentMix(String name) => Mix(name, {for (final id in activeIds) id: volumeOf(id)});

  // ---------- sounds ----------

  Future<void> toggle(String id) => isOn(id) ? turnOff(id) : turnOn(id);

  Future<void> turnOn(String id, {double? volume}) async {
    if (volume != null) _volumes[id] = volume;
    if (_masterTarget == 0 && !_paused) {
      // a pause or stop was fading out; switching a sound on cancels it
      _fadeMaster(1, seconds: 0.5);
    }
    final existing = _channels[id];
    if (existing != null) {
      existing
        ..active = true
        ..volume = volumeOf(id)
        ..fadeTarget = 1;
      _startTicker();
      notifyListeners();
      return;
    }
    final channel = _Channel(_newPlayer(), volumeOf(id));
    _channels[id] = channel;
    notifyListeners();
    await channel.player.load(soundById(id).asset);
    if (!identical(_channels[id], channel)) return; // removed while loading
    await channel.player.setVolume(0);
    if (_paused) {
      _paused = false;
      for (final c in _channels.values) {
        if (c != channel) await c.player.play();
      }
      _masterTarget = 1;
    }
    await channel.player.play();
    _startSleepCountdownIfArmed();
    _startTicker();
    notifyListeners();
  }

  Future<void> turnOff(String id, {double fadeSeconds = 0.8}) async {
    final channel = _channels[id];
    if (channel == null) return;
    channel
      ..active = false
      ..fadeTarget = 0
      ..fadeRate = 1 / fadeSeconds;
    _startTicker();
    notifyListeners();
    if (!hasSound) _cancelSleepCountdown(keepSetting: true);
  }

  void setVolume(String id, double volume) {
    _volumes[id] = volume;
    final channel = _channels[id];
    if (channel != null) {
      channel.volume = volume;
      _apply(channel);
    }
    notifyListeners();
  }

  Future<void> applyMix(Mix mix) async {
    for (final id in activeIds) {
      if (!mix.volumes.containsKey(id)) await turnOff(id);
    }
    for (final entry in mix.volumes.entries) {
      // a saved mix may name a sound this version doesn't ship
      if (!sounds.any((s) => s.id == entry.key)) continue;
      if (isOn(entry.key)) {
        setVolume(entry.key, entry.value);
      } else {
        await turnOn(entry.key, volume: entry.value);
      }
    }
  }

  // ---------- transport ----------

  void pause() {
    if (!isPlaying) return;
    _fadeMaster(0, seconds: 0.5, then: () async {
      for (final c in _channels.values) {
        await c.player.pause();
      }
      _paused = true;
      _sleepTimer?.cancel();
      notifyListeners();
    });
  }

  Future<void> resume() async {
    if (!_paused) return;
    _paused = false;
    for (final c in _channels.values) {
      await c.player.play();
    }
    _fadeMaster(1, seconds: 0.5);
    if (_sleepRemaining != null) _runSleepCountdown();
    notifyListeners();
  }

  void stopAll({Duration fade = const Duration(milliseconds: 1500)}) {
    _fadeMaster(0, seconds: fade.inMilliseconds / 1000, then: () async {
      for (final id in _channels.keys.toList()) {
        await _release(id);
      }
      _master = 1;
      _masterTarget = 1;
      _paused = false;
      _cancelSleepCountdown(keepSetting: true);
      notifyListeners();
    });
  }

  // ---------- sleep timer ----------

  /// Stop everything after [after] (null means play until stopped). The last
  /// 30 seconds fade out slowly so the silence doesn't wake anyone.
  void setSleepTimer(Duration? after) {
    _sleepAfter = after;
    _cancelSleepCountdown(keepSetting: true);
    _startSleepCountdownIfArmed();
    notifyListeners();
  }

  void _startSleepCountdownIfArmed() {
    if (_sleepAfter == null || _sleepRemaining != null || !hasSound) return;
    _sleepRemaining = _sleepAfter;
    _runSleepCountdown();
  }

  void _runSleepCountdown() {
    _sleepTimer?.cancel();
    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      final left = _sleepRemaining! - const Duration(seconds: 1);
      _sleepRemaining = left;
      if (left == sleepFade || (left < sleepFade && _masterTarget != 0)) {
        stopAll(fade: left);
      }
      if (left <= Duration.zero) t.cancel();
      notifyListeners();
    });
  }

  void _cancelSleepCountdown({required bool keepSetting}) {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepRemaining = null;
    if (!keepSetting) _sleepAfter = null;
  }

  // ---------- fades ----------

  void _fadeMaster(double target, {required double seconds, VoidCallback? then}) {
    _masterTarget = target;
    _masterRate = seconds <= 0 ? double.infinity : 1 / seconds;
    _onMasterSilent = then;
    _startTicker();
  }

  void _startTicker() {
    _ticker ??= Timer.periodic(tick, (_) => _step());
  }

  void _step() {
    final dt = tick.inMilliseconds / 1000;
    var moving = false;

    _master = _approach(_master, _masterTarget, _masterRate * dt);
    if (_master != _masterTarget) moving = true;

    for (final id in _channels.keys.toList()) {
      final c = _channels[id]!;
      c.fade = _approach(c.fade, c.fadeTarget, c.fadeRate * dt);
      if (c.fade != c.fadeTarget) {
        moving = true;
      } else if (!c.active && c.fade == 0) {
        _release(id);
        continue;
      }
      _apply(c);
    }

    if (_master == _masterTarget && _onMasterSilent != null) {
      final then = _onMasterSilent!;
      _onMasterSilent = null;
      then();
    }
    if (!moving && _onMasterSilent == null) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  static double _approach(double value, double target, double step) {
    if ((target - value).abs() <= step) return target;
    return value + (target > value ? step : -step);
  }

  void _apply(_Channel c) => c.player.setVolume(c.volume * c.fade * _master);

  Future<void> _release(String id) async {
    final c = _channels.remove(id);
    if (c == null) return;
    await c.player.pause();
    await c.player.dispose();
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _sleepTimer?.cancel();
    for (final c in _channels.values) {
      c.player.dispose();
    }
    super.dispose();
  }
}
