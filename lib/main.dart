import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';

import 'audio/audio_handler.dart';
import 'audio/mixer.dart';
import 'models/mix_store.dart';
import 'ui/home_screen.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration.music());

  final mixer = Mixer();
  await AudioService.init(
    builder: () => MoonhushAudioHandler(mixer),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.moonhush.app.playback',
      androidNotificationChannelName: 'Playback',
      androidNotificationOngoing: true,
      androidStopForegroundOnPause: true,
    ),
  );
  runApp(MoonhushApp(mixer: mixer, store: MixStore()));
}

class MoonhushApp extends StatelessWidget {
  const MoonhushApp({super.key, required this.mixer, required this.store});

  final Mixer mixer;
  final MixStore store;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Moonhush',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: HomeScreen(mixer: mixer, store: store),
    );
  }
}
