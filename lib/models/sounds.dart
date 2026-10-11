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

const sounds = <Sound>[
  Sound('rain', 'Rain', SoundGroup.nature),
  Sound('rain_on_roof', 'Rain on roof', SoundGroup.nature),
  Sound('thunderstorm', 'Thunderstorm', SoundGroup.nature),
  Sound('ocean_waves', 'Ocean waves', SoundGroup.nature),
  Sound('stream', 'Stream', SoundGroup.nature),
  Sound('wind', 'Wind', SoundGroup.nature),
  Sound('fireplace', 'Fireplace', SoundGroup.nature),
  Sound('night_crickets', 'Night crickets', SoundGroup.nature),
  Sound('white_noise', 'White noise', SoundGroup.noise),
  Sound('pink_noise', 'Pink noise', SoundGroup.noise),
  Sound('brown_noise', 'Brown noise', SoundGroup.noise),
  Sound('fan', 'Fan', SoundGroup.noise),
  Sound('heartbeat', 'Heartbeat', SoundGroup.noise),
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
  Mix('Rainy night', {'rain_on_roof': 0.8, 'fireplace': 0.45}),
  Mix('Seaside', {'ocean_waves': 0.9, 'wind': 0.25}),
  Mix('Mountain cabin', {'fireplace': 0.8, 'wind': 0.5, 'rain': 0.25}),
  Mix('Summer evening', {'night_crickets': 0.8, 'stream': 0.4}),
  Mix('For baby', {'heartbeat': 0.7, 'pink_noise': 0.35}),
];
