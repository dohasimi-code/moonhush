# Moonhush

Sleep sounds you can mix. Switch on rain, waves, wind, a fireplace or soft
noise, set each one's volume, save your favourite mixes, and let the sleep
timer fade everything out after you fall asleep. Playback continues with the
screen off and can be controlled from the lock screen.

Built with Flutter for Android and iOS (`com.moonhush.app`).

## Run

```sh
flutter pub get
flutter test
flutter run
```

Every push to `main` runs the tests and builds an Android APK, which can be
downloaded from the workflow run's artifacts on GitHub (Actions tab).

## Code

- `lib/audio/mixer.dart`: plays several looping sounds at once, with fades and the sleep timer
- `lib/audio/audio_handler.dart`: lock screen, notification and background playback
- `lib/models/sounds.dart`: the sound list and built-in mixes
- `lib/ui/`: the home screen and theme

## Sounds

`assets/sounds/` holds 2-minute seamless loops (AAC). Real recordings are CC0
from Freesound and are turned into loops with `tools/sounds/make_loop.py`;
white, pink and brown noise come from `tools/sounds/generate.py`. Sounds not
yet replaced by recordings are still synthesized placeholders. Sources and
licences are listed in [CREDITS.md](CREDITS.md).
