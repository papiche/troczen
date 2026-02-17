import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// Service API TrocZen pour upload logos uniquement
/// Toutes les opérations Nostr se font directement via le relais
class ApiService {
  // URLs par défaut (production)
  static const String defaultApiUrl = 'https://troczen.copylaradio.com';
  static const String defaultRelayUrl = 'wss://relay.copylaradio.com';
  
  // URLs locales (borne wifi/portail captif)
  static const String localApiUrl = 'http://zen.local:5000';
  static const String localRelayUrl = 'ws://zen.local:7777';
  static const List<String> localHosts = [
    'http://192.168.101.1:5000',  // AP direct
    'http://10.0.0.1:5000',     // Routeur standard
    'http://zen.local:5000',    // mDNS
  ];

  String _currentApiUrl = defaultApiUrl;
  String _currentRelayUrl = defaultRelayUrl;
  bool _isLocal = false;

  /// Détecte automatiquement si connecté à une borne locale
  Future<bool> detectLocalNetwork() async {
    // Tester chaque URL locale
    for (final url in localHosts) {
      try {
        final response = await http.get(
          Uri.parse('$url/health'),
        ).timeout(const Duration(seconds: 2));

        if (response.statusCode == 200) {
          // Borne locale détectée !
          _currentApiUrl = url;
          _isLocal = true;
          
          // Extraire l'IP/host pour le relay WebSocket
          final host = Uri.parse(url).host;
          final port = Uri.parse(url).port;
          _currentRelayUrl = 'ws://$host:7777';  // Port relay local

          print('✅ Borne locale détectée: $_currentApiUrl');
          return true;
        }
      } catch (e) {
        // Timeout ou erreur - pas cette URL
        continue;
      }
    }

    // Aucune borne locale - utiliser l'API publique
    _currentApiUrl = defaultApiUrl;
    _currentRelayUrl = defaultRelayUrl;
    _isLocal = false;
    
    print('📡 Utilisation API publique: $_currentApiUrl');
    return false;
  }

  /// Upload image (logo, bandeau, avatar) pour profils Nostr
  /// Seule opération API nécessaire - pour stocker l'image
  Future<Map<String, dynamic>?> uploadImage({
    required String npub,
    required File imageFile,
    required String type,  // 'logo', 'banner', ou 'avatar'
  }) async {
    try {
      final uri = Uri.parse('$_currentApiUrl/api/upload/image');
      final request = http.MultipartRequest('POST', uri);
      
      request.fields['npub'] = npub;
      request.fields['type'] = type;
      request.files.add(await http.MultipartFile.fromPath(
        'file',
        imageFile.path,
      ));

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 201) {
        return json.decode(response.body);
      } else {
        print('Erreur upload: ${response.body}');
        return null;
      }
    } catch (e) {
      print('Erreur upload image ($type): $e');
      return null;
    }
  }

  /// Méthode alias pour compatibilité avec l'ancien nom
  Future<Map<String, dynamic>?> uploadLogo({
    required String npub,
    required File imageFile,
  }) async {
    return uploadImage(npub: npub, imageFile: imageFile, type: 'logo');
  }

  // Getters
  String get apiUrl => _currentApiUrl;
  String get relayUrl => _currentRelayUrl;
  bool get isLocal => _isLocal;

  /// Force l'utilisation de l'API publique
  void usePublicApi() {
    _currentApiUrl = defaultApiUrl;
    _currentRelayUrl = defaultRelayUrl;
    _isLocal = false;
  }

  /// Force l'utilisation d'une URL personnalisée
  void setCustomApi(String apiUrl, String relayUrl) {
    _currentApiUrl = apiUrl;
    _currentRelayUrl = relayUrl;
    _isLocal = false;
  }
}
