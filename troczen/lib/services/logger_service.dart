import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'storage_service.dart';
import 'feedback_service.dart';

/// Service de log centralisé qui conditionne l'affichage des logs
/// au mode DEBUG (Marché Global Ğ1) ou au mode debug Flutter.
///
/// En Marché Global Ğ1 (transparence publique):
/// - Les logs sont stockés en mémoire pour export ultérieur
/// - Un accès facile aux logs est disponible via getLogs() et exportLogs()
/// - Les logs peuvent être transmis via /api/feedback pour soumission d'issues
class Logger {
  static final StorageService _storage = StorageService();
  static final FeedbackService _feedbackService = FeedbackService();
  
  static bool _isDebugMode = false;
  static bool _initialized = false;
  
  /// Buffer circulaire pour stocker les logs (actif en permanence pour le support utilisateur)
  static final List<LogEntry> _logBuffer = [];
  
  /// Taille maximale du buffer de logs en mode debug (en nombre d'entrées)
  static const int _maxBufferSizeDebug = 1000;
  
  /// Taille maximale du buffer de logs en production (en nombre d'entrées)
  static const int _maxBufferSizeProd = 200;

  /// Vérifie si le mode Marché Global Ğ1 est actif (seed à zéro = transparence)
  /// Doit être appelé au démarrage de l'application ou dans les vues principales
  static Future<void> checkDebugMode() async {
    if (_initialized) return;
    
    try {
      final market = await _storage.getMarket();
      final marketName = market?.name.toUpperCase() ?? '';
      // Le mode debug est activé pour le Marché Global (transparence publique)
      _isDebugMode = marketName == 'MARCHÉ GLOBAL Ğ1' ||
                     marketName == 'MARCHÉ GLOBAL G1' ||
                     marketName == 'HACKATHON' ||
                     market?.seedMarket == ('0' * 64);
      _initialized = true;
      
      if (_isDebugMode) {
        debugPrint('🌐 MODE DEBUG ACTIVÉ (Marché Global Ğ1 - Transparence publique) 🌐');
        debugPrint('📋 Les logs sont stockés en mémoire et peuvent être exportés');
        _addLog('SYSTEM', 'Marché Global Ğ1 activé - Logs en mémoire activés (Transparence)', 'info');
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
      _addLog('SYSTEM', 'Mode debug forcé', 'info');
    }
  }

  /// Réinitialise l'état du logger (utile pour les tests)
  static void reset() {
    _isDebugMode = false;
    _initialized = false;
    _logBuffer.clear();
  }

  /// Vérifie si le mode debug est actif
  static bool get isDebugMode => _isDebugMode || kDebugMode;
  
  /// Retourne le nombre de logs stockés
  static int get logCount => _logBuffer.length;
  
  /// Retourne tous les logs stockés
  static List<LogEntry> getLogs() => List.unmodifiable(_logBuffer);
  
  /// Retourne les logs filtrés par niveau
  static List<LogEntry> getLogsByLevel(String level) {
    return _logBuffer.where((log) => log.level == level).toList();
  }
  
  /// Retourne les logs filtrés par tag
  static List<LogEntry> getLogsByTag(String tag) {
    return _logBuffer.where((log) => log.tag == tag).toList();
  }
  
  /// Exporte les logs au format JSON
  static String exportLogsJson() {
    final logs = _logBuffer.map((log) => log.toJson()).toList();
    return jsonEncode({
      'exportTime': DateTime.now().toIso8601String(),
      'globalMarketMode': _isDebugMode,
      'logCount': logs.length,
      'logs': logs,
    });
  }
  
  /// Exporte les logs au format texte lisible
  static String exportLogsText() {
    final buffer = StringBuffer();
    buffer.writeln('=== TROCZEN LOG EXPORT ===');
    buffer.writeln('Export Time: ${DateTime.now().toIso8601String()}');
    buffer.writeln('Marché Global Mode: $_isDebugMode');
    buffer.writeln('Log Count: ${_logBuffer.length}');
    buffer.writeln('==========================');
    buffer.writeln();
    
    for (final log in _logBuffer) {
      buffer.writeln(log.toString());
    }
    
    return buffer.toString();
  }
  
  /// Transmet les logs à l'API pour soumission d'issue via /api/feedback
  /// Utilise le FeedbackService existant pour créer une issue GitHub
  /// Retourne true si la transmission a réussi
  static Future<bool> submitLogsToApi({String? issueDescription}) async {
    if (!_isDebugMode) {
      warn('Logger', 'Tentative de soumission de logs hors mode Marché Global');
      return false;
    }
    
    try {
      // Construire la description avec les logs
      final logsPreview = _logBuffer.take(50).toList();
      final logsText = logsPreview.map((log) => log.toString()).join('\n');
      
      final fullDescription = '''$issueDescription

---
### Logs récents (${_logBuffer.length} au total)

```
$logsText
${_logBuffer.length > 50 ? '\n... et ${_logBuffer.length - 50} logs supplémentaires' : ''}
```

---
*Soumis depuis le Marché Global Ğ1 de TrocZen*
''';

      // Utiliser le FeedbackService existant
      final result = await _feedbackService.reportBug(
        title: '[Marché Global] Issue avec logs',
        description: fullDescription,
        appVersion: '3.6.1',
        platform: defaultTargetPlatform.name,
      );
      
      if (result.success) {
        success('Logger', 'Logs transmis avec succès - Issue #${result.issueNumber}');
        return true;
      } else {
        error('Logger', 'Échec de transmission des logs', result.error);
        return false;
      }
    } catch (e) {
      error('Logger', 'Erreur lors de la transmission des logs', e);
      return false;
    }
  }
  
  /// Efface le buffer de logs
  static void clearLogs() {
    _logBuffer.clear();
    log('Logger', 'Buffer de logs effacé');
  }

  /// Ajoute un log au buffer (Actif en permanence pour le support utilisateur)
  static void _addLog(String tag, String message, String level) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      tag: tag,
      message: message,
      level: level,
    );
    
    // Buffer circulaire strict (ex: 200 logs max en prod, 1000 en mode Debug)
    final limit = isDebugMode ? _maxBufferSizeDebug : _maxBufferSizeProd;
    if (_logBuffer.length >= limit) {
      _logBuffer.removeAt(0);
    }
    
    _logBuffer.add(entry);
  }

  /// Log standard - affiché uniquement en mode debug
  static void log(String tag, String message) {
    if (_isDebugMode || kDebugMode) {
      final time = DateTime.now().toIso8601String().split('T').last;
      debugPrint('[$time][$tag] $message');
    }
    _addLog(tag, message, 'log');
  }

  /// Log d'erreur - toujours affiché
  static void error(String tag, String message, [dynamic error]) {
    final time = DateTime.now().toIso8601String().split('T').last;
    final errorMsg = error != null ? ' | Error: $error' : '';
    debugPrint('❌ [$time][$tag] $message$errorMsg');
    _addLog(tag, '$message$errorMsg', 'error');
  }

  /// Log d'avertissement - toujours affiché
  static void warn(String tag, String message) {
    final time = DateTime.now().toIso8601String().split('T').last;
    debugPrint('⚠️ [$time][$tag] $message');
    _addLog(tag, message, 'warn');
  }

  /// Log de succès - affiché uniquement en mode debug
  static void success(String tag, String message) {
    if (_isDebugMode || kDebugMode) {
      final time = DateTime.now().toIso8601String().split('T').last;
      debugPrint('✅ [$time][$tag] $message');
    }
    _addLog(tag, message, 'success');
  }

  /// Log d'information - affiché uniquement en mode debug
  static void info(String tag, String message) {
    if (_isDebugMode || kDebugMode) {
      final time = DateTime.now().toIso8601String().split('T').last;
      debugPrint('ℹ️ [$time][$tag] $message');
    }
    _addLog(tag, message, 'info');
  }

  /// Log de debug détaillé - affiché uniquement en mode debug
  static void debug(String tag, String message) {
    if (_isDebugMode || kDebugMode) {
      final time = DateTime.now().toIso8601String().split('T').last;
      debugPrint('🔍 [$time][$tag] $message');
    }
    _addLog(tag, message, 'debug');
  }
}

/// Entrée de log individuelle
class LogEntry {
  final DateTime timestamp;
  final String tag;
  final String message;
  final String level; // log, error, warn, success, info, debug
  
  const LogEntry({
    required this.timestamp,
    required this.tag,
    required this.message,
    required this.level,
  });
  
  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'tag': tag,
    'message': message,
    'level': level,
  };
  
  factory LogEntry.fromJson(Map<String, dynamic> json) => LogEntry(
    timestamp: DateTime.parse(json['timestamp']),
    tag: json['tag'],
    message: json['message'],
    level: json['level'],
  );
  
  @override
  String toString() {
    final time = timestamp.toIso8601String().split('T').last;
    final icon = _getIcon();
    return '$icon [$time][$tag] $message';
  }
  
  String _getIcon() {
    switch (level) {
      case 'error': return '❌';
      case 'warn': return '⚠️';
      case 'success': return '✅';
      case 'info': return 'ℹ️';
      case 'debug': return '🔍';
      default: return '📝';
    }
  }
}
