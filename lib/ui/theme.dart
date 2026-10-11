import 'package:flutter/material.dart';

/// Night palette: deep indigo ground, moonlight as the only accent.
class Night {
  static const ground = Color(0xFF0D1020);
  static const dusk = Color(0xFF161A31);
  static const tile = Color(0xFF1B2040);
  static const line = Color(0xFF2B315A);
  static const ink = Color(0xFFE8E6F2);
  static const mist = Color(0xFF9EA3C4);
  static const moon = Color(0xFFF3DFA8);
}

ThemeData buildTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: Night.ground,
    colorScheme: base.colorScheme.copyWith(
      primary: Night.moon,
      onPrimary: Night.ground,
      surface: Night.dusk,
      onSurface: Night.ink,
      outline: Night.line,
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: Night.moon,
      inactiveTrackColor: Night.line,
      thumbColor: Night.moon,
      overlayShape: RoundSliderOverlayShape(overlayRadius: 14),
      trackHeight: 3,
    ),
    textTheme: base.textTheme.apply(bodyColor: Night.ink, displayColor: Night.ink),
  );
}
