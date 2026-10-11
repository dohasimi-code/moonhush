import 'package:flutter/foundation.dart';

/// The sound library. Each id matches an asset in `assets/sounds/{id}.m4a`.
class Sound {
  const Sound(this.id, this.name, this.group);

  final String id;
  final String name;
  final SoundGroup group;

  // The browser preview ships MP3 copies; the phone apps use AAC, which loops
  // without a gap.
  String get asset => 'assets/sounds/$id.${kIsWeb ? 'mp3' : 'm4a'}';
}

enum SoundGroup { nature, noise }

// Version 1 ships only the real recordings and the noises. Rain on roof,
// thunderstorm, ocean waves, fireplace, night crickets, fan and heartbeat
// come back once real recordings replace the synthesized drafts.
const sounds = <Sound>[
  Sound('rain', 'Rain', SoundGroup.nature),
  Sound('stream', 'Stream', SoundGroup.nature),
  Sound('wind', 'Wind', SoundGroup.nature),
  Sound('white_noise', 'White noise', SoundGroup.noise),
  Sound('pink_noise', 'Pink noise', SoundGroup.noise),
  Sound('brown_noise', 'Brown noise', SoundGroup.noise),
];

Sound soundById(String id) => sounds.firstWhere((s) => s.id == id);

/// A named set of sounds with a volume for each.
class Mix {
  const Mix(this.name, this.volumes);

  final String name;
  final Map<String, double> volumes;

  Map<String, dynamic> toJson() => {'name': name, 'volumes': volumes};

  factory Mix.fromJson(Map<String, dynamic> json) => Mix(
        json['name'] as String,
        (json['volumes'] as Map).map((k, v) => MapEntry(k as String, (v as num).toDouble())),
      );
}

const presets = <Mix>[
  Mix('Rainy night', {'rain': 0.8, 'brown_noise': 0.3}),
  Mix('Forest creek', {'stream': 0.8, 'wind': 0.25}),
  Mix('Stormy evening', {'wind': 0.7, 'rain': 0.5}),
  Mix('Deep focus', {'brown_noise': 0.7, 'stream': 0.2}),
  Mix('For baby', {'white_noise': 0.5, 'rain': 0.2}),
];
