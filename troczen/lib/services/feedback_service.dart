import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

/// Service d'envoi de feedback utilisateur
/// 🔒 Sécurisé: Passe par le backend qui gère le token GitHub
class FeedbackService {
  final String _baseUrl;

  FeedbackService({String? baseUrl})
      : _baseUrl = baseUrl ?? 'https://api.troczen.local';

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
      final response = await http.post(
        Uri.parse('$_baseUrl/api/feedback'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'type': type,
          'title': title,
          'description': description,
          'email': email ?? 'anonymous',
          'app_version': appVersion ?? 'unknown',
          'platform': platform ?? 'unknown',
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
