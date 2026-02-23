import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'storage_service.dart';
import '../config/app_config.dart';

/// Service d'envoi de feedback utilisateur
/// 🔒 Sécurisé: Passe par le backend qui gère le token GitHub
class FeedbackService {
  final String _baseUrl;
  final StorageService _storage = StorageService();

  FeedbackService({String? baseUrl})
      : _baseUrl = baseUrl ?? AppConfig.defaultApiUrl;

  /// Récupère les identifiants utilisateur (G1PUB et npub Nostr)
  Future<Map<String, String>> _getUserIdentifiers() async {
    try {
      final user = await _storage.getUser();
      if (user != null) {
        return {
          'g1pub': user.g1pub ?? 'non défini',
          'npub_hex': user.npub,
          'npub_bech32': user.npubBech32,
          'display_name': user.displayName,
        };
      }
    } catch (e) {
      debugPrint('⚠️ Impossible de récupérer les identifiants utilisateur: $e');
    }
    return {
      'g1pub': 'non défini',
      'npub_hex': 'non défini',
      'npub_bech32': 'non défini',
      'display_name': 'anonyme',
    };
  }

  /// Construit la description complète avec les identifiants utilisateur
  Future<String> _buildDescriptionWithIdentifiers(String description) async {
    final identifiers = await _getUserIdentifiers();
    
    return '''
---
### Identifiants utilisateur
- **G1PUB**: `${identifiers['g1pub']}`
- **Nostr npub (hex)**: `${identifiers['npub_hex']}`
- **Nostr npub (bech32)**: `${identifiers['npub_bech32']}`
- **Nom**: ${identifiers['display_name']}

---

$description
''';
  }

  /// Envoyer un feedback via le backend
  ///
  /// [type] : 'bug', 'feature', 'feedback', 'question'
  /// [title] : Titre court du feedback
  /// [description] : Description détaillée
  /// [email] : Email de contact (optionnel)
  /// [appVersion] : Version de l'app
  /// [platform] : Plateforme (Android, iOS, etc.)
  Future<FeedbackResult> sendFeedback({
    required String type,
    required String title,
    required String description,
    String? email,
    String? appVersion,
    String? platform,
  }) async {
    try {
      // Ajouter les identifiants utilisateur à la description
      final fullDescription = await _buildDescriptionWithIdentifiers(description);
      
      // Récupérer les identifiants pour les métadonnées
      final identifiers = await _getUserIdentifiers();
      
      final response = await http.post(
        Uri.parse('$_baseUrl/api/feedback'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'type': type,
          'title': title,
          'description': fullDescription,
          'email': email ?? 'anonymous',
          'app_version': appVersion ?? 'unknown',
          'platform': platform ?? 'unknown',
          'user_g1pub': identifiers['g1pub'],
          'user_npub': identifiers['npub_hex'],
          'user_npub_bech32': identifiers['npub_bech32'],
          'user_display_name': identifiers['display_name'],
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        return FeedbackResult(
          success: true,
          issueNumber: data['issue_number'],
          issueUrl: data['issue_url'],
          message: data['message'],
        );
      } else {
        final error = jsonDecode(response.body);
        return FeedbackResult(
          success: false,
          error: error['error'] ?? 'Erreur inconnue',
        );
      }
    } catch (e) {
      debugPrint('❌ Erreur envoi feedback: $e');
      return FeedbackResult(
        success: false,
        error: 'Impossible de se connecter au serveur',
      );
    }
  }

  /// Envoyer un rapport de bug
  Future<FeedbackResult> reportBug({
    required String title,
    required String description,
    String? email,
    String? appVersion,
    String? platform,
  }) {
    return sendFeedback(
      type: 'bug',
      title: title,
      description: description,
      email: email,
      appVersion: appVersion,
      platform: platform,
    );
  }

  /// Suggérer une fonctionnalité
  Future<FeedbackResult> suggestFeature({
    required String title,
    required String description,
    String? email,
    String? appVersion,
    String? platform,
  }) {
    return sendFeedback(
      type: 'feature',
      title: title,
      description: description,
      email: email,
      appVersion: appVersion,
      platform: platform,
    );
  }

  /// Envoyer un feedback général
  Future<FeedbackResult> sendGeneralFeedback({
    required String title,
    required String description,
    String? email,
    String? appVersion,
    String? platform,
  }) {
    return sendFeedback(
      type: 'feedback',
      title: title,
      description: description,
      email: email,
      appVersion: appVersion,
      platform: platform,
    );
  }
}

/// Résultat d'envoi de feedback
class FeedbackResult {
  final bool success;
  final int? issueNumber;
  final String? issueUrl;
  final String? message;
  final String? error;

  FeedbackResult({
    required this.success,
    this.issueNumber,
    this.issueUrl,
    this.message,
    this.error,
  });
}
