import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'sounds.dart';

/// Mixes the user saved, kept on the device.
class MixStore {
  static const _key = 'saved_mixes';

  Future<List<Mix>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    return [for (final m in jsonDecode(raw) as List) Mix.fromJson(m as Map<String, dynamic>)];
  }

  Future<void> save(List<Mix> mixes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode([for (final m in mixes) m.toJson()]));
  }
}
