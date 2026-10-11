import 'package:audio_service/audio_service.dart';

import '../models/sounds.dart';
import 'mixer.dart';

/// Connects the mixer to the lock screen, notification and headphone buttons,
/// and keeps playback alive when the app is in the background.
class MoonhushAudioHandler extends BaseAudioHandler {
  MoonhushAudioHandler(this.mixer) {
    mixer.addListener(_publish);
    _publish();
  }

  final Mixer mixer;

  void _publish() {
    final names = [for (final id in mixer.activeIds) soundById(id).name];
    mediaItem.add(MediaItem(
      id: 'moonhush-mix',
      title: names.isEmpty ? 'Moonhush' : names.join(' + '),
      album: 'Moonhush',
    ));
    playbackState.add(PlaybackState(
      controls: [
        if (mixer.isPlaying) MediaControl.pause else MediaControl.play,
        MediaControl.stop,
      ],
      systemActions: const {MediaAction.play, MediaAction.pause, MediaAction.stop},
      androidCompactActionIndices: const [0, 1],
      processingState: mixer.hasSound ? AudioProcessingState.ready : AudioProcessingState.idle,
      playing: mixer.isPlaying,
    ));
  }

  @override
  Future<void> play() => mixer.resume();

  @override
  Future<void> pause() async => mixer.pause();

  @override
  Future<void> stop() async => mixer.stopAll();
}
