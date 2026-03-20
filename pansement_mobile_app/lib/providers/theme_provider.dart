import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _keyThemeMode = 'theme_mode'; // 'light' | 'dark'

/// Provider qui expose le ThemeMode et le persiste (SharedPreferences).
final themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  return ThemeModeNotifier();
});

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier() : super(ThemeMode.light) {
    _load();
  }

  Future<void> _load() async {
    // Rehydrate le thème persistant au démarrage.
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_keyThemeMode);
    if (stored == 'dark') {
      state = ThemeMode.dark;
    } else {
      state = ThemeMode.light;
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (state == mode) return;
    // Mise à jour immédiate UI + persistance locale.
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _keyThemeMode,
      mode == ThemeMode.dark ? 'dark' : 'light',
    );
  }

  /// Bascule entre clair et sombre (utilisé par le switch).
  bool get isDark => state == ThemeMode.dark;

  Future<void> setDark(bool value) async {
    await setThemeMode(value ? ThemeMode.dark : ThemeMode.light);
  }
}
