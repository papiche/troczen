import 'package:flutter/foundation.dart';
import 'storage_service.dart';

/// Service de log centralisé qui conditionne l'affichage des logs
/// au mode DEBUG (marché "HACKATHON") ou au mode debug Flutter.
class Logger {
  static final StorageService _storage = StorageService();
  static bool _isDebugMode = false;
  static bool _initialized = false;

  /// Vérifie si le mode HACKATHON est actif
  /// Doit être appelé au démarrage de l'application ou dans les vues principales
  static Future<void> checkDebugMode() async {
    if (_initialized) return;
    
    try {
      final market = await _storage.getMarket();
      _isDebugMode = market?.name.toUpperCase() == 'HACKATHON';
      _initialized = true;
      
      if (_isDebugMode) {
        debugPrint('🐛 MODE DEBUG ACTIVÉ (Marché: HACKATHON) 🐛');
      }
    } catch (e) {
      // En cas d'erreur, on reste en mode non-debug
      debugPrint('Logger: Erreur lors de la vérification du mode debug: $e');
    }
  }

  /// Force le mode debug (utile pour les tests)
  static void setDebugMode(bool enabled) {
    _isDebugMode = enabled;
    _initialized = true;
    if (enabled) {
      debugPrint('🐛 MODE DEBUG FORCÉ 🐛');
    }
  }

  /// Réinitialise l'état du logger (utile pour les tests)
  static void reset() {
    _isDebugMode = false;
    _initialized = false;
  }

  /// Vérifie si le mode debug est actif
  static bool get isDebugMode => _isDebugMode || kDebugMode;

  /// Log standard - affiché uniquement en mode debug
  static void log(String tag, String message) {
    if (_isDebugMode || kDebugMode) {
      final time = DateTime.now().toIso8601String().split('T').last;
      debugPrint('[$time][$tag] $message');
    }
  }

  /// Log d'erreur - toujours affiché
  static void error(String tag, String message, [dynamic error]) {
    final time = DateTime.now().toIso8601String().split('T').last;
    final errorMsg = error != null ? ' | Error: $error' : '';
    debugPrint('❌ [$time][$tag] $message$errorMsg');
  }

  /// Log d'avertissement - toujours affiché
  static void warn(String tag, String message) {
    final time = DateTime.now().toIso8601String().split('T').last;
    debugPrint('⚠️ [$time][$tag] $message');
  }

  /// Log de succès - affiché uniquement en mode debug
  static void success(String tag, String message) {
    if (_isDebugMode || kDebugMode) {
      final time = DateTime.now().toIso8601String().split('T').last;
      debugPrint('✅ [$time][$tag] $message');
    }
  }

  /// Log d'information - affiché uniquement en mode debug
  static void info(String tag, String message) {
    if (_isDebugMode || kDebugMode) {
      final time = DateTime.now().toIso8601String().split('T').last;
      debugPrint('ℹ️ [$time][$tag] $message');
    }
  }

  /// Log de debug détaillé - affiché uniquement en mode debug
  static void debug(String tag, String message) {
    if (_isDebugMode || kDebugMode) {
      final time = DateTime.now().toIso8601String().split('T').last;
      debugPrint('🔍 [$time][$tag] $message');
    }
  }
}
