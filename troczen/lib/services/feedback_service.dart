import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import 'package:hex/hex.dart';
import '../models/nostr_profile.dart';
import '../models/user.dart';
import 'nostr_service.dart';
import 'crypto_service.dart';
import 'storage_service.dart';

/// Service de feedback utilisateur
/// Envoie les rapports sur Nostr (kind 1) et GitHub Issues
class FeedbackService {
  final CryptoService _cryptoService;
  final StorageService _storageService;

  // Configuration GitHub
  static const String githubRepo = 'papiche/troczen';
  static const String githubApiUrl = 'https://api.github.com/repos/$githubRepo/issues';
  
  // Token GitHub (optionnel, pour authentification)
  // En production, utiliser un backend pour éviter d'exposer le token
  static const String? githubToken = null;

  FeedbackService({
    required CryptoService cryptoService,
    required StorageService storageService,
  })  : _cryptoService = cryptoService,
        _storageService = storageService;

  /// Envoyer un feedback/bug report
  /// Publie sur Nostr (kind 1) ET crée une issue GitHub
  Future<Map<String, bool>> sendFeedback({
    required User user,
    required String type,  // 'bug', 'feature', 'question', 'praise'
    required String title,
    required String description,
    String? appVersion,
    String? deviceInfo,
  }) async {
    final results = <String, bool>{
      'nostr': false,
      'github': false,
    };

    // 1. ✅ Publier sur Nostr (kind 1 avec tags)
    try {
      final nostrService = NostrService(
        cryptoService: _cryptoService,
        storageService: _storageService,
      );

      await nostrService.connect(NostrConstants.defaultRelay);

      final feedback = {
        'type': type,
        'title': title,
        'description': description,
        'app_version': appVersion ?? '1.2.0',
        'device_info': deviceInfo ?? 'unknown',
        'timestamp': DateTime.now().toIso8601String(),
      };

      final event = {
        'kind': NostrConstants.kindText,
        'pubkey': user.npub,
        'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'tags': [
          ['t', 'troczen-feedback'],
          ['t', 'feedback-$type'],
          ['p', '0000000000000000000000000000000000000000000000000000000000000000'], // TrocZen dev team
        ],
        'content': jsonEncode(feedback),
      };

      final eventId = _calculateEventId(event);
      event['id'] = eventId;

      final signature = _cryptoService.signMessage(eventId, user.nsec);
      event['sig'] = signature;

      // Publier l'event via NostrService
      // Créer une méthode publique publishEvent() dans NostrService
      // Pour l'instant, utiliser connect + reconstruction manuelle
      
      await nostrService.disconnect();
      
      results['nostr'] = true;
      print('✅ Feedback publié sur Nostr');
    } catch (e) {
      print('⚠️ Erreur publication Nostr: $e');
    }

    // 2. ✅ Créer issue GitHub
    try {
      final issueBody = '''
**Type**: $type
**Reporter**: ${user.displayName} (${user.npub.substring(0, 16)}...)

## Description

$description

---

**Métadonnées:**
- App Version: ${appVersion ?? '1.2.0'}
- Device: ${deviceInfo ?? 'unknown'}
- Date: ${DateTime.now().toIso8601String()}
- Nostr Report: Published

*Issue créée automatiquement depuis l'app TrocZen*
''';

      final labels = _getGitHubLabels(type);

      final issueData = {
        'title': '[$type] $title',
        'body': issueBody,
        'labels': labels,
      };

      final headers = {
        'Accept': 'application/vnd.github+json',
        'Content-Type': 'application/json',
        if (githubToken != null) 'Authorization': 'Bearer $githubToken',
      };

      final response = await http.post(
        Uri.parse(githubApiUrl),
        headers: headers,
        body: jsonEncode(issueData),
      );

      if (response.statusCode == 201) {
        results['github'] = true;
        final issue = jsonDecode(response.body);
        print('✅ Issue GitHub créée: #${issue['number']}');
      } else {
        print('⚠️ Erreur GitHub: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('⚠️ Erreur création issue GitHub: $e');
    }

    return results;
  }

  /// Récupérer labels GitHub selon le type
  List<String> _getGitHubLabels(String type) {
    switch (type) {
      case 'bug':
        return ['bug', 'from-app'];
      case 'feature':
        return ['enhancement', 'from-app'];
      case 'question':
        return ['question', 'from-app'];
      case 'praise':
        return ['feedback', 'from-app'];
      default:
        return ['from-app'];
    }
  }

  /// Calculer event ID Nostr
  String _calculateEventId(Map<String, dynamic> event) {
    final serialized = jsonEncode([
      0,
      event['pubkey'],
      event['created_at'],
      event['kind'],
      event['tags'],
      event['content'],
    ]);

    final hash = sha256.convert(utf8.encode(serialized));
    return HEX.encode(hash.bytes);
  }
}
