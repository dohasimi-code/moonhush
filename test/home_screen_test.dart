import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonhush/audio/mixer.dart';
import 'package:moonhush/main.dart';
import 'package:moonhush/models/mix_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_player.dart';

void main() {
  testWidgets('tapping a sound starts it and shows it as playing', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final mixer = Mixer(playerFactory: FakeLoopPlayer.new);
    await tester.pumpWidget(MoonhushApp(mixer: mixer, store: MixStore()));
    await tester.pumpAndSettle();

    expect(find.text('Tap a sound to start'), findsOneWidget);
    await tester.tap(find.byKey(const Key('tile-rain')));
    await tester.pump(const Duration(seconds: 2));

    expect(mixer.isOn('rain'), isTrue);
    expect(find.byKey(const Key('status')), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(const Key('status'))).data, 'Rain');

    mixer.dispose();
  });

  testWidgets('a saved mix appears in the mixes row', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final mixer = Mixer(playerFactory: FakeLoopPlayer.new);
    await tester.pumpWidget(MoonhushApp(mixer: mixer, store: MixStore()));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.byKey(const Key('tile-brown_noise')), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.byKey(const Key('tile-brown_noise')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tile-brown_noise')));
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.byTooltip('Save mix'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('mix-name')), 'Cabin');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(CustomScrollView), const Offset(0, 2000));
    await tester.pumpAndSettle();
    expect(find.text('Cabin'), findsOneWidget);
    final saved = await MixStore().load();
    expect(saved.single.volumes, {'brown_noise': 0.6});

    mixer.dispose();
  });
}
