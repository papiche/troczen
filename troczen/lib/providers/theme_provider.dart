import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ThemeProvider extends ChangeNotifier {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  static const String _themeModeKey = 'theme_mode';

  ThemeMode _themeMode = ThemeMode.dark; // Default to dark mode as it was the original

  ThemeMode get themeMode => _themeMode;

  ThemeProvider() {
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    try {
      final savedTheme = await _secureStorage.read(key: _themeModeKey);
      if (savedTheme != null) {
        _themeMode = savedTheme == 'light' ? ThemeMode.light : ThemeMode.dark;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Erreur lors du chargement du thème: $e');
    }
  }

  Future<void> toggleTheme() async {
    _themeMode = _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
    try {
      await _secureStorage.write(
        key: _themeModeKey,
        value: _themeMode == ThemeMode.light ? 'light' : 'dark',
      );
    } catch (e) {
      debugPrint('Erreur lors de la sauvegarde du thème: $e');
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    try {
      await _secureStorage.write(
        key: _themeModeKey,
        value: _themeMode == ThemeMode.light ? 'light' : 'dark',
      );
    } catch (e) {
      debugPrint('Erreur lors de la sauvegarde du thème: $e');
    }
  }
}
